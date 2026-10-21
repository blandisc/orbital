import Foundation
import OrbitalCore

/// Descargas con `URLSession` en segundo plano: el sistema sigue bajando con la app suspendida y la relanza al
/// terminar (no sobreviven a cerrar la app a la fuerza: iOS las cancela).
///
/// - **Por partes**: un archivo grande se baja en `parts` pedazos a la vez (cada uno con su `Range`), porque una sola
///   conexión rara vez llena la línea con Real-Debrid. Cada pedazo es una tarea en segundo plano con sus propios datos de
///   reanudación; al terminar todos, se juntan en el video. Si el servidor no acepta pedazos, se baja de una pieza.
/// - **Pausa o corte**: se conserva lo bajado con los *datos de reanudación* de `URLSession` y se continúa con ellos
///   mientras el enlace siga valiendo.
/// - **Enlace caducado** (Real-Debrid): los pedazos ya terminados se quedan; los demás se piden otra vez con el enlace nuevo.
/// - **Relanzar la app**: una descarga que el sistema siguió en segundo plano se *adopta*, no se reinicia; si se cerró a media
///   unión de pedazos, la unión se retoma donde iba.
final class BackgroundDownloadTransport: NSObject, DownloadTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.example.orbital.ios.downloads"
    /// Cuántos pedazos a la vez por archivo, y desde qué tamaño vale la pena partirlo.
    static let parts = 4
    static let partsMinimumBytes: Int64 = 200_000_000

    private struct Part: Codable {
        var start: Int64
        var end: Int64            // incluido
        var done = false
        var size: Int64 { end - start + 1 }
    }

    private struct Context: Codable {
        var file: String            // relativo a `root`: la ruta del contenedor cambia al actualizar la app
        var url: String
        var usedResumeData = false
        /// La marca de las tareas de ahora (`id#token` o `id#token#pedazo`). Antes las tareas se reconocían solo por `id`, y al
        /// cambiar una descarga por otra versión la nueva «adoptaba» la vieja que se estaba cancelando y se atoraba.
        var token: String?
        /// Por partes: los pedazos, el tamaño total, el enlace ya resuelto (sin pasar por la redirección de Torrentio cada
        /// vez) y hasta qué pedazo ya se juntó en el video.
        var parts: [Part]?
        var total: Int64?
        var resolved: String?
        var assembled: Int?
    }

    /// `id#token#pedazo` → (id, token, pedazo). Las tareas de versiones anteriores no traen token.
    private static func parse(_ description: String?) -> (id: String, token: String?, part: Int?)? {
        guard let description else { return nil }
        let pieces = description.components(separatedBy: "#")
        switch pieces.count {
        case 1: return (description, nil, nil)
        case 2: return (pieces[0], pieces[1], nil)
        default: return (pieces[0], pieces[1], Int(pieces[2]))
        }
    }

    /// El contexto de una tarea, solo si es la vigente de esa descarga (no una vieja que se está cancelando).
    private func current(_ task: URLSessionTask) -> (id: String, part: Int?, context: Context)? {
        guard let (id, token, part) = Self.parse(task.taskDescription), let context = lock.withLock({ contexts[id] }) else { return nil }
        return context.token == token ? (id, part, context) : nil
    }

    private let lock = NSLock()
    private var contexts: [String: Context] = [:]
    private var lastProgress: [String: Date] = [:]
    /// Lo bajado de cada pedazo en marcha (para el avance de todo el archivo).
    private var partWritten: [String: [Int: Int64]] = [:]
    /// Ya se avisó el fallo de esta tanda (varios pedazos pueden fallar a la vez: un solo aviso).
    private var failedTokens = Set<String>()
    /// Cuántas veces el servidor dijo «espera» (429/503) a cada pedazo: se reintenta solo ese, sin tirar los demás.
    private var throttled: [String: Int] = [:]
    static let throttleRetries = 8
    private var session: URLSession!
    private let continuation: AsyncStream<DownloadEvent>.Continuation
    let events: AsyncStream<DownloadEvent>
    private let defaults: UserDefaults
    private let root: URL
    private let resumeFolder: URL
    private let partsFolder: URL
    var allowsCellular: @Sendable () -> Bool = { false }
    /// Lo guarda `AppDelegate.application(_:handleEventsForBackgroundURLSession:)`.
    var backgroundCompletion: (() -> Void)?

    init(root: URL = AppFiles.downloadsRoot, defaults: UserDefaults = .standard) {
        self.root = root
        self.defaults = defaults
        resumeFolder = AppFiles.support.appendingPathComponent("Resume", isDirectory: true)
        partsFolder = AppFiles.support.appendingPathComponent("Parts", isDirectory: true)
        try? FileManager.default.createDirectory(at: resumeFolder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: partsFolder, withIntermediateDirectories: true)
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        super.init()
        contexts = (defaults.data(forKey: "orbital.download-contexts").flatMap { try? JSONDecoder().decode([String: Context].self, from: $0) }) ?? [:]
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false          // las pides tú: que empiecen ya
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = Self.parts * Downloads.maxActive
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    // MARK: archivos
    private func relative(_ file: URL) -> String { file.path.hasPrefix(root.path + "/") ? String(file.path.dropFirst(root.path.count + 1)) : file.path }
    private func absolute(_ path: String) -> URL { path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path) }
    private func safe(_ id: String) -> String { Data(id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") }
    private func resumeFile(_ id: String, part: Int? = nil) -> URL { resumeFolder.appendingPathComponent(safe(id) + (part.map { "-\($0)" } ?? "")) }
    private func partFolder(_ id: String) -> URL { partsFolder.appendingPathComponent(safe(id), isDirectory: true) }
    private func partFile(_ id: String, _ part: Int) -> URL { partFolder(id).appendingPathComponent("\(part)") }
    private func saveContexts() { defaults.set(try? JSONEncoder().encode(contexts), forKey: "orbital.download-contexts") }

    // MARK: DownloadTransport
    func start(id: String, url: URL, resumeFrom: Int64, file: URL) async {
        let tasks = await session.allTasks.filter { Self.parse($0.taskDescription)?.id == id }
        let existing = lock.withLock { contexts[id] }
        // Por partes, con el mismo enlace: se retoma (los pedazos vivos se adoptan, los que faltan se piden, y si ya estaban
        // todos, se juntan).
        if let existing, existing.parts != nil, existing.url == url.absoluteString {
            return startParts(id: id, context: existing, live: tasks)
        }
        // De una pieza: si el sistema siguió bajando con la app cerrada, la tarea viva se adopta.
        if let existing, existing.parts == nil, let token = existing.token,
           let live = tasks.first(where: { $0.state == .running || $0.state == .suspended }), Self.parse(live.taskDescription)?.token == token {
            live.resume()
            return
        }
        // Nueva (o con enlace nuevo): ¿cuánto mide y acepta pedazos? Así se decide si se parte.
        // (Con pedazos de antes y enlace renovado, aunque ya haya una parte del video juntada en disco: sigue por pedazos.)
        if resumeFrom == 0 || existing?.parts != nil, let probe = await probe(url), probe.total >= Self.partsMinimumBytes {
            var context = Context(file: relative(file), url: url.absoluteString, token: UUID().uuidString, total: probe.total, resolved: probe.resolved.absoluteString)
            // Enlace renovado del mismo archivo: los pedazos terminados se quedan.
            if let old = existing?.parts, existing?.total == probe.total { context.parts = old; context.assembled = existing?.assembled }
            else { context.parts = Self.split(probe.total); try? FileManager.default.removeItem(at: partFolder(id)) }
            for task in tasks { task.cancel() }
            for i in 0..<Self.parts { try? FileManager.default.removeItem(at: resumeFile(id, part: i)) }   // atados al enlace viejo
            lock.withLock { contexts[id] = context; partWritten[id] = nil; saveContexts() }
            continuation.yield(.progress(id: id, written: written(id, context), total: probe.total))
            return startParts(id: id, context: context, live: [])
        }
        startSingle(id: id, url: url, resumeFrom: resumeFrom, file: file, existing: existing)
    }

    /// Los pedazos parejos de un archivo de `total` bytes.
    private static func split(_ total: Int64) -> [Part] {
        let size = (total + Int64(parts) - 1) / Int64(parts)
        return (0..<parts).compactMap { i in
            let start = Int64(i) * size
            return start < total ? Part(start: start, end: min(total, start + size) - 1) : nil
        }
    }

    /// Cuánto mide de verdad y si el servidor da pedazos: un `Range: bytes=0-0` (sigue la redirección de Torrentio a
    /// Real-Debrid; ese enlace final es el que piden los pedazos).
    private func probe(_ url: URL) async -> (total: Int64, resolved: URL)? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("Orbital", forHTTPHeaderField: "User-Agent")
        request.allowsCellularAccess = allowsCellular()
        guard let (_, response) = try? await URLSession(configuration: .ephemeral).data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 206,
              let range = http.value(forHTTPHeaderField: "Content-Range"), let total = range.split(separator: "/").last.flatMap({ Int64($0) }),
              let resolved = http.url else { return nil }
        return (total, resolved)
    }

    private func startParts(id: String, context: Context, live: [URLSessionTask]) {
        guard let parts = context.parts, let token = context.token else { return }
        if parts.allSatisfy(\.done) { return assemble(id) }
        let running = Set(live.compactMap { task -> Int? in
            guard let p = Self.parse(task.taskDescription), p.token == token, task.state == .running || task.state == .suspended else { return nil }
            task.resume()
            return p.part
        })
        lock.withLock { _ = failedTokens.remove(token) }
        guard let target = URL(string: context.resolved ?? context.url) else { return }
        for (i, part) in parts.enumerated() where !part.done && !running.contains(i) {
            let resume = resumeFile(id, part: i)
            let task: URLSessionDownloadTask
            if let data = try? Data(contentsOf: resume), !data.isEmpty { task = session.downloadTask(withResumeData: data) }
            else {
                var request = URLRequest(url: target)
                request.allowsCellularAccess = allowsCellular()
                request.setValue("Orbital", forHTTPHeaderField: "User-Agent")
                request.setValue("bytes=\(part.start)-\(part.end)", forHTTPHeaderField: "Range")
                task = session.downloadTask(with: request)
            }
            try? FileManager.default.removeItem(at: resume)
            task.taskDescription = "\(id)#\(token)#\(i)"
            task.resume()
        }
    }

    private func startSingle(id: String, url: URL, resumeFrom: Int64, file: URL, existing: Context?) {
        let resumeURL = resumeFile(id)
        let sameLink = existing?.url == url.absoluteString
        let task: URLSessionDownloadTask
        var usedResume = false
        if sameLink, let data = try? Data(contentsOf: resumeURL), !data.isEmpty {
            task = session.downloadTask(withResumeData: data)
            usedResume = true
        } else {
            try? FileManager.default.removeItem(at: resumeURL)     // enlace nuevo: lo bajado con el viejo no sirve
            var request = URLRequest(url: url)
            request.allowsCellularAccess = allowsCellular()
            request.setValue("Orbital", forHTTPHeaderField: "User-Agent")
            if resumeFrom > 0 { request.setValue("bytes=\(resumeFrom)-", forHTTPHeaderField: "Range") }
            task = session.downloadTask(with: request)
        }
        let token = UUID().uuidString
        task.taskDescription = "\(id)#\(token)"
        lock.withLock { contexts[id] = Context(file: relative(file), url: url.absoluteString, usedResumeData: usedResume, token: token); saveContexts() }
        try? FileManager.default.removeItem(at: resumeURL)
        task.resume()
    }

    /// Pausa: se detiene y se guardan los datos de reanudación (de cada pedazo).
    func cancel(id: String) async {
        let tasks = await session.allTasks
        for task in tasks where Self.parse(task.taskDescription)?.id == id && (task.state == .running || task.state == .suspended) {
            let part = Self.parse(task.taskDescription)?.part
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                guard let download = task as? URLSessionDownloadTask else { task.cancel(); return done.resume() }
                download.cancel(byProducingResumeData: { [weak self] data in
                    if let self, let data { try? data.write(to: self.resumeFile(id, part: part), options: .atomic) }
                    done.resume()
                })
            }
        }
    }

    /// Borrar: se detiene y se olvida todo (también los pedazos).
    func discard(id: String) async {
        let tasks = await session.allTasks
        for task in tasks where Self.parse(task.taskDescription)?.id == id { task.cancel() }
        try? FileManager.default.removeItem(at: resumeFile(id))
        for i in 0..<Self.parts { try? FileManager.default.removeItem(at: resumeFile(id, part: i)) }
        try? FileManager.default.removeItem(at: partFolder(id))
        lock.withLock { contexts[id] = nil; lastProgress[id] = nil; partWritten[id] = nil; saveContexts() }
    }

    // MARK: avance
    private func written(_ id: String, _ context: Context) -> Int64 {
        guard let parts = context.parts else { return 0 }
        let live = lock.withLock { partWritten[id] ?? [:] }
        return parts.enumerated().reduce(0) { sum, item in sum + (item.element.done ? item.element.size : min(item.element.size, live[item.offset] ?? 0)) }
    }

    private func report(_ id: String, written: Int64, total: Int64?) {
        let now = Date()
        let due = lock.withLock { () -> Bool in
            if let last = lastProgress[id], now.timeIntervalSince(last) < 0.5 { return false }
            lastProgress[id] = now; return true
        }
        if due { continuation.yield(.progress(id: id, written: written, total: total)) }
    }

    // MARK: URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (id, part, context) = current(downloadTask) else { return }   // una tarea vieja (cambiada o cancelada): no cuenta
        if let part, context.parts != nil {
            // Con datos de reanudación `totalBytesWritten` ya incluye lo que ese pedazo había bajado.
            lock.withLock { partWritten[id, default: [:]][part] = totalBytesWritten }
            return report(id, written: written(id, context), total: context.total)
        }
        let response = downloadTask.response as? HTTPURLResponse
        var base: Int64 = 0
        var total: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        if !context.usedResumeData, response?.statusCode == 206, let range = response?.value(forHTTPHeaderField: "Content-Range"),
           let parts = range.split(separator: "/").last, let full = Int64(parts) { total = full; base = full - max(totalBytesExpectedToWrite, 0) }
        report(id, written: base + totalBytesWritten, total: total)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (id, part, context) = current(downloadTask) else {
            // Sin contexto pero sin otra tarea vigente (se perdió al cerrar la app): que la cola lo vuelva a pedir, no que se
            // quede «descargando» para siempre.
            if let id = Self.parse(downloadTask.taskDescription)?.id, lock.withLock({ contexts[id] }) == nil {
                continuation.yield(.failed(id: id, status: nil, message: "Se perdió la descarga; se vuelve a pedir"))
            }
            return
        }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Demasiadas conexiones a la vez (el servidor dice «espera»): ese pedazo se pide otra vez en un rato, cuando otro
            // termine y libere lugar; los demás siguen.
            if let part, context.parts != nil, status == 429 || status == 503 { return retryPart(id, part: part, token: context.token) }
            // Un 403/404/410 no es un archivo: Real-Debrid dice que el enlace caducó.
            if context.parts != nil { return failParts(id, token: context.token, status: status, message: DownloadMessages.forStatus(status)) }
            continuation.yield(.failed(id: id, status: status, message: DownloadMessages.forStatus(status)))
            return
        }
        if let part, let parts = context.parts, part < parts.count { return finishPart(id, part: part, location: location, status: status, parts: parts) }
        let destination = absolute(context.file)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if status == 206, !context.usedResumeData {
                // Un trozo (se pidió con Range): solo sirve si el parcial está ahí; si no, se pide completo otra vez.
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    continuation.yield(.failed(id: id, status: nil, message: "Falta el archivo parcial"))
                    return
                }
                try append(location, to: destination)
            } else {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            }
            excludeFromBackup(destination)
            try? FileManager.default.removeItem(at: resumeFile(id))
            continuation.yield(.finished(id: id))
        } catch {
            continuation.yield(.failed(id: id, status: nil, message: "No pude guardar el archivo: \(error.localizedDescription)"))
        }
    }

    private func retryPart(_ id: String, part: Int, token: String?) {
        let key = "\(id)#\(part)"
        let attempt = lock.withLock { () -> Int in throttled[key, default: 0] += 1; return throttled[key]! }
        guard attempt <= Self.throttleRetries else {
            return failParts(id, token: token, status: 429, message: DownloadMessages.forStatus(429))
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(min(30, 2 << min(attempt, 4))) * 1_000_000_000)
            guard let context = lock.withLock({ contexts[id] }), context.token == token else { return }
            let live = await session.allTasks.filter { Self.parse($0.taskDescription)?.id == id }
            startParts(id: id, context: context, live: live)
        }
    }

    /// Un pedazo terminó: se guarda aparte (hay que sacarlo antes de que el sistema lo borre) y, si era el último, se junta todo.
    private func finishPart(_ id: String, part: Int, location: URL, status: Int, parts: [Part]) {
        let size = (try? FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64) ?? 0
        let token = lock.withLock { contexts[id]?.token }
        // Un 200 a una petición de pedazo trae el archivo entero (el servidor ignoró el Range): no sirve como pedazo.
        guard status == 206, size == parts[part].size else {
            return failParts(id, token: token, status: nil, message: "El servidor no mandó el pedazo completo")
        }
        do {
            try FileManager.default.createDirectory(at: partFolder(id), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: partFile(id, part))
            try FileManager.default.moveItem(at: location, to: partFile(id, part))
        } catch {
            return failParts(id, token: token, status: nil, message: "No pude guardar el archivo: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: resumeFile(id, part: part))
        let allDone = lock.withLock { () -> Bool in
            throttled["\(id)#\(part)"] = nil
            contexts[id]?.parts?[part].done = true
            partWritten[id]?[part] = nil
            saveContexts()
            return contexts[id]?.parts?.allSatisfy(\.done) ?? false
        }
        if allDone { assemble(id) }
        else if let context = lock.withLock({ contexts[id] }) { report(id, written: written(id, context), total: context.total) }
    }

    /// Junta los pedazos en el video, en orden. Se anota cada pedazo ya puesto: si la app se cierra a media unión, se sigue
    /// desde ahí (el archivo se recorta al inicio del pedazo que faltaba antes de agregarlo otra vez).
    private func assemble(_ id: String) {
        guard let context = lock.withLock({ contexts[id] }), let parts = context.parts else { return }
        let destination = absolute(context.file)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            var next = (context.assembled ?? -1) + 1
            if next == 0 {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: partFile(id, 0), to: destination)
                lock.withLock { contexts[id]?.assembled = 0; saveContexts() }
                next = 1
            }
            for i in next..<parts.count {
                let handle = try FileHandle(forWritingTo: destination)
                try handle.truncate(atOffset: UInt64(parts[i].start))
                try handle.close()
                try append(partFile(id, i), to: destination)
                try? FileManager.default.removeItem(at: partFile(id, i))
                lock.withLock { contexts[id]?.assembled = i; saveContexts() }
            }
            try? FileManager.default.removeItem(at: partFolder(id))
            excludeFromBackup(destination)
            lock.withLock { contexts[id] = nil; partWritten[id] = nil; saveContexts() }
            continuation.yield(.finished(id: id))
        } catch {
            continuation.yield(.failed(id: id, status: nil, message: "No pude guardar el archivo: \(error.localizedDescription)"))
        }
    }

    private func append(_ source: URL, to destination: URL) throws {
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        while let chunk = try reader.read(upToCount: 8 << 20), !chunk.isEmpty { try handle.write(contentsOf: chunk) }
    }

    private func excludeFromBackup(_ file: URL) {
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var mutable = file; try? mutable.setResourceValues(excluded)
    }

    /// Un pedazo falló: se detienen los demás (guardando lo que llevan) y se avisa una sola vez; la cola reintenta y los pedazos
    /// siguen donde iban.
    private func failParts(_ id: String, token: String?, status: Int?, message: String) {
        guard let token, lock.withLock({ failedTokens.insert(token).inserted }) else { return }
        Task {
            await cancel(id: id)
            continuation.yield(.failed(id: id, status: status, message: message))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (id, part, context) = current(task) else { return }   // una tarea vieja: ni borra el contexto de la nueva ni la marca fallida
        guard let error else {
            if context.parts == nil { lock.withLock { contexts[id] = nil; saveContexts() } }
            return
        }
        let nsError = error as NSError
        // Un corte (sin red, tiempo agotado) trae datos para continuar: se guardan.
        if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { try? data.write(to: resumeFile(id, part: part), options: .atomic) }
        if nsError.code == NSURLErrorCancelled { return }   // lo cancelamos nosotros (pausa, borrar u otro pedazo falló)
        let status = (task.response as? HTTPURLResponse)?.statusCode
        if context.parts != nil { return failParts(id, token: context.token, status: status, message: error.localizedDescription) }
        continuation.yield(.failed(id: id, status: status, message: error.localizedDescription))
    }

    /// Sin la red que pide (con «Solo con Wi‑Fi», sin Wi‑Fi): se dice «Esperando Wi‑Fi» en vez de parecer que baja.
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        guard let (id, _, _) = current(task) else { return }
        continuation.yield(.waiting(id: id))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in self?.backgroundCompletion?(); self?.backgroundCompletion = nil }
    }
}
