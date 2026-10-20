import Foundation
import OrbitalCore

/// Descargas con `URLSession` en segundo plano: el sistema sigue bajando con la app suspendida y la relanza al
/// terminar (no sobreviven a cerrar la app a la fuerza: iOS las cancela).
///
/// - **Pausa o corte**: se conserva lo bajado con los *datos de reanudación* de `URLSession` y se continúa con ellos
///   mientras el enlace siga valiendo.
/// - **Enlace caducado** (Real-Debrid): el enlace nuevo no puede usar esos datos (están atados al enlace viejo), así que
///   se baja de nuevo desde cero con el enlace nuevo.
/// - **Relanzar la app**: una descarga que el sistema siguió en segundo plano se *adopta*, no se reinicia.
final class BackgroundDownloadTransport: NSObject, DownloadTransport, URLSessionDownloadDelegate, @unchecked Sendable {
    static let identifier = "com.example.orbital.ios.downloads"

    private struct Context: Codable {
        var file: String            // relativo a `root`: la ruta del contenedor cambia al actualizar la app
        var url: String
        var usedResumeData = false
        /// La marca de la tarea de ahora (`id#token`). Antes las tareas se reconocían solo por `id`, y al cambiar una
        /// descarga por otra versión la nueva «adoptaba» la vieja que se estaba cancelando: bajaba unos KB y se atoraba.
        var token: String?
    }

    /// `id#token` → (id, token). Las tareas de versiones anteriores no traen token.
    private static func parse(_ description: String?) -> (id: String, token: String?)? {
        guard let description else { return nil }
        guard let hash = description.lastIndex(of: "#") else { return (description, nil) }
        return (String(description[..<hash]), String(description[description.index(after: hash)...]))
    }

    /// El contexto de una tarea, solo si es la tarea vigente de esa descarga (no una vieja que se está cancelando).
    private func current(_ task: URLSessionTask) -> (id: String, context: Context)? {
        guard let (id, token) = Self.parse(task.taskDescription), let context = lock.withLock({ contexts[id] }) else { return nil }
        return context.token == token ? (id, context) : nil
    }

    private let lock = NSLock()
    private var contexts: [String: Context] = [:]
    private var lastProgress: [String: Date] = [:]
    private var session: URLSession!
    private let continuation: AsyncStream<DownloadEvent>.Continuation
    let events: AsyncStream<DownloadEvent>
    private let defaults: UserDefaults
    private let root: URL
    private let resumeFolder: URL
    var allowsCellular: @Sendable () -> Bool = { false }
    /// Lo guarda `AppDelegate.application(_:handleEventsForBackgroundURLSession:)`.
    var backgroundCompletion: (() -> Void)?

    init(root: URL = AppFiles.downloadsRoot, defaults: UserDefaults = .standard) {
        self.root = root
        self.defaults = defaults
        resumeFolder = AppFiles.support.appendingPathComponent("Resume", isDirectory: true)
        try? FileManager.default.createDirectory(at: resumeFolder, withIntermediateDirectories: true)
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        super.init()
        contexts = (defaults.data(forKey: "orbital.download-contexts").flatMap { try? JSONDecoder().decode([String: Context].self, from: $0) }) ?? [:]
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false          // las pides tú: que empiecen ya
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    // MARK: archivos
    private func relative(_ file: URL) -> String { file.path.hasPrefix(root.path + "/") ? String(file.path.dropFirst(root.path.count + 1)) : file.path }
    private func absolute(_ path: String) -> URL { path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path) }
    private func resumeFile(_ id: String) -> URL { resumeFolder.appendingPathComponent(Data(id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")) }
    private func saveContexts() { defaults.set(try? JSONEncoder().encode(contexts), forKey: "orbital.download-contexts") }

    // MARK: DownloadTransport
    func start(id: String, url: URL, resumeFrom: Int64, file: URL) async {
        // Si el sistema siguió bajando mientras la app estaba cerrada, esa tarea sigue viva: se adopta (no se reinicia).
        // Solo una tarea viva de verdad (no una que se está cancelando) y que sea la vigente de esta descarga.
        let tasks = await session.allTasks
        let token = lock.withLock { contexts[id]?.token }
        if let live = tasks.first(where: { Self.parse($0.taskDescription)?.id == id && ($0.state == .running || $0.state == .suspended) }),
           Self.parse(live.taskDescription)?.token == token, token != nil || live.taskDescription == id {
            live.resume()
            return
        }
        let resumeURL = resumeFile(id)
        let sameLink = lock.withLock { contexts[id]?.url == url.absoluteString }
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
        let newToken = UUID().uuidString
        task.taskDescription = "\(id)#\(newToken)"
        lock.withLock { contexts[id] = Context(file: relative(file), url: url.absoluteString, usedResumeData: usedResume, token: newToken); saveContexts() }
        try? FileManager.default.removeItem(at: resumeURL)
        task.resume()
    }

    /// Pausa: se detiene y se guardan los datos de reanudación.
    func cancel(id: String) async {
        let tasks = await session.allTasks
        for task in tasks where Self.parse(task.taskDescription)?.id == id && (task.state == .running || task.state == .suspended) {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                guard let download = task as? URLSessionDownloadTask else { task.cancel(); return done.resume() }
                download.cancel(byProducingResumeData: { [weak self] data in
                    if let self, let data { try? data.write(to: self.resumeFile(id), options: .atomic) }
                    done.resume()
                })
            }
        }
    }

    /// Borrar: se detiene y se olvida todo.
    func discard(id: String) async {
        let tasks = await session.allTasks
        for task in tasks where Self.parse(task.taskDescription)?.id == id { task.cancel() }
        try? FileManager.default.removeItem(at: resumeFile(id))
        lock.withLock { contexts[id] = nil; lastProgress[id] = nil; saveContexts() }
    }

    // MARK: URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let (id, context) = current(downloadTask) else { return }   // una tarea vieja (cambiada o cancelada): no cuenta
        let response = downloadTask.response as? HTTPURLResponse
        var base: Int64 = 0
        var total: Int64? = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        if !context.usedResumeData, response?.statusCode == 206, let range = response?.value(forHTTPHeaderField: "Content-Range"),
           let parts = range.split(separator: "/").last, let full = Int64(parts) { total = full; base = full - max(totalBytesExpectedToWrite, 0) }
        let now = Date()
        let due = lock.withLock { () -> Bool in
            if let last = lastProgress[id], now.timeIntervalSince(last) < 0.5 { return false }
            lastProgress[id] = now; return true
        }
        // Con datos de reanudación `totalBytesWritten` ya incluye lo que se había bajado.
        if due { continuation.yield(.progress(id: id, written: base + totalBytesWritten, total: total)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (id, context) = current(downloadTask) else {
            // Sin contexto pero sin otra tarea vigente (se perdió al cerrar la app): que la cola lo vuelva a pedir, no que se
            // quede «descargando» para siempre.
            if let id = Self.parse(downloadTask.taskDescription)?.id, lock.withLock({ contexts[id] }) == nil {
                continuation.yield(.failed(id: id, status: nil, message: "Se perdió la descarga; se vuelve a pedir"))
            }
            return
        }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Un 403/404/410 no es un archivo: Real-Debrid dice que el enlace caducó.
            continuation.yield(.failed(id: id, status: status, message: DownloadMessages.forStatus(status)))
            return
        }
        let destination = absolute(context.file)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if status == 206, !context.usedResumeData {
                // Un trozo (se pidió con Range): solo sirve si el parcial está ahí; si no, se pide completo otra vez.
                guard FileManager.default.fileExists(atPath: destination.path) else {
                    continuation.yield(.failed(id: id, status: nil, message: "Falta el archivo parcial"))
                    return
                }
                let handle = try FileHandle(forWritingTo: destination)
                defer { try? handle.close() }
                try handle.seekToEnd()
                let reader = try FileHandle(forReadingFrom: location)
                defer { try? reader.close() }
                while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty { try handle.write(contentsOf: chunk) }
            } else {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            }
            var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
            var mutable = destination; try? mutable.setResourceValues(excluded)
            try? FileManager.default.removeItem(at: resumeFile(id))
            continuation.yield(.finished(id: id))
        } catch {
            continuation.yield(.failed(id: id, status: nil, message: "No pude guardar el archivo: \(error.localizedDescription)"))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (id, _) = current(task) else { return }   // una tarea vieja: ni borra el contexto de la nueva ni la marca fallida
        guard let error else { lock.withLock { contexts[id] = nil; saveContexts() }; return }
        let nsError = error as NSError
        // Un corte (sin red, tiempo agotado) trae datos para continuar: se guardan.
        if let data = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data { try? data.write(to: resumeFile(id), options: .atomic) }
        if nsError.code == NSURLErrorCancelled { return }   // lo cancelamos nosotros (pausa o borrar)
        continuation.yield(.failed(id: id, status: (task.response as? HTTPURLResponse)?.statusCode, message: error.localizedDescription))
    }

    /// Sin la red que pide (con «Solo con Wi‑Fi», sin Wi‑Fi): se dice «Esperando Wi‑Fi» en vez de parecer que baja.
    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        guard let (id, _) = current(task) else { return }
        continuation.yield(.waiting(id: id))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in self?.backgroundCompletion?(); self?.backgroundCompletion = nil }
    }
}
