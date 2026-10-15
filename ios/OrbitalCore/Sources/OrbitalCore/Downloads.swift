import Foundation

public enum DownloadState: String, Sendable, Codable { case queued, downloading, paused, failed, done }

/// Una descarga para ver sin conexión. NO guarda la URL de la fuente ni la del complemento (llevan tu clave de
/// Real-Debrid): la URL de la fuente vive en el Keychain bajo `SecretKey.download(id)`.
public struct DownloadItem: Sendable, Codable, Equatable, Identifiable {
    public var id: String                 // «metaID|videoID»
    public var kind: String
    public var metaID: String
    public var videoID: String
    public var title: String              // el que se muestra (en tu idioma)
    public var originalTitle: String      // el de Cinemeta: lo que se guarda en Stremio
    public var subtitle: String           // «T2 · E5 · Trojan's Horse»
    public var poster: String?
    public var addon: String              // solo el nombre («Torrentio»): para mostrar y emparejar
    public var release: String            // nombre del archivo de la fuente: para encontrarla de nuevo si el enlace caduca
    public var sourceIndex: Int
    public var expectedBytes: Int64?
    public var writtenBytes: Int64 = 0
    public var state: DownloadState = .queued
    public var relativePath: String       // dentro de la carpeta de descargas
    public var subtitleFiles: [String] = []
    public var attempts = 0
    public var refreshes = 0              // cuántas veces se pidió un enlace nuevo (tope: `Downloads.maxRefreshes`)
    public var lastError: String?
    public var createdAt: Double
    public var finishedAt: Double?

    public init(id: String, kind: String, metaID: String, videoID: String, title: String, originalTitle: String, subtitle: String, poster: String?,
                addon: String, release: String = "", sourceIndex: Int, expectedBytes: Int64?, relativePath: String, createdAt: Double) {
        self.id = id; self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.title = title; self.originalTitle = originalTitle
        self.subtitle = subtitle; self.poster = poster; self.addon = addon; self.release = release; self.sourceIndex = sourceIndex
        self.expectedBytes = expectedBytes; self.relativePath = relativePath; self.createdAt = createdAt
    }

    /// Tolerante: un campo nuevo o ausente en un índice viejo no hace perder toda la lista (y un `addonURL` viejo, que llevaba la
    /// clave de Real-Debrid, simplemente se ignora y desaparece al volver a guardar).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "movie"
        metaID = try c.decode(String.self, forKey: .metaID)
        videoID = try c.decode(String.self, forKey: .videoID)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        originalTitle = try c.decodeIfPresent(String.self, forKey: .originalTitle) ?? ""
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        poster = try c.decodeIfPresent(String.self, forKey: .poster)
        addon = try c.decodeIfPresent(String.self, forKey: .addon) ?? ""
        release = try c.decodeIfPresent(String.self, forKey: .release) ?? ""
        sourceIndex = try c.decodeIfPresent(Int.self, forKey: .sourceIndex) ?? 0
        expectedBytes = try c.decodeIfPresent(Int64.self, forKey: .expectedBytes)
        writtenBytes = try c.decodeIfPresent(Int64.self, forKey: .writtenBytes) ?? 0
        state = try c.decodeIfPresent(DownloadState.self, forKey: .state) ?? .queued
        relativePath = try c.decode(String.self, forKey: .relativePath)
        subtitleFiles = try c.decodeIfPresent([String].self, forKey: .subtitleFiles) ?? []
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        refreshes = try c.decodeIfPresent(Int.self, forKey: .refreshes) ?? 0
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        finishedAt = try c.decodeIfPresent(Double.self, forKey: .finishedAt)
    }

    enum Keys: String, CodingKey {
        case id, kind, metaID, videoID, title, originalTitle, subtitle, poster, addon, release, sourceIndex, expectedBytes, writtenBytes, state
        case relativePath, subtitleFiles, attempts, refreshes, lastError, createdAt, finishedAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(metaID, forKey: .metaID); try c.encode(videoID, forKey: .videoID)
        try c.encode(title, forKey: .title); try c.encode(originalTitle, forKey: .originalTitle); try c.encode(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(poster, forKey: .poster); try c.encode(addon, forKey: .addon); try c.encode(release, forKey: .release)
        try c.encode(sourceIndex, forKey: .sourceIndex); try c.encodeIfPresent(expectedBytes, forKey: .expectedBytes); try c.encode(writtenBytes, forKey: .writtenBytes)
        try c.encode(state, forKey: .state); try c.encode(relativePath, forKey: .relativePath); try c.encode(subtitleFiles, forKey: .subtitleFiles)
        try c.encode(attempts, forKey: .attempts); try c.encode(refreshes, forKey: .refreshes); try c.encodeIfPresent(lastError, forKey: .lastError)
        try c.encode(createdAt, forKey: .createdAt); try c.encodeIfPresent(finishedAt, forKey: .finishedAt)
    }

    public static func makeID(metaID: String, videoID: String) -> String { "\(metaID)|\(videoID)" }
    public var progress: Double? { expectedBytes.flatMap { $0 > 0 ? min(1, Double(writtenBytes) / Double($0)) : nil } }
}

public extension SecretKey {
    static func download(_ id: String) -> String { "download:\(id)" }
}

public enum DownloadEvent: Sendable, Equatable {
    /// `total` es el tamaño completo del archivo (no lo que falta).
    case progress(id: String, written: Int64, total: Int64?)
    case finished(id: String)
    case failed(id: String, status: Int?, message: String)
}

public enum DownloadMessages {
    /// Lo que se le dice a la persona cuando el servidor contesta con un error (nunca «HTTP 403» a secas).
    public static func forStatus(_ status: Int) -> String {
        switch status {
        case 401, 403, 404, 410: "El enlace de la fuente caducó o ya no existe. Toca ▶ para buscar otro."
        case 416: "Lo bajado no cuadra con el archivo: se empieza de nuevo."
        case 429: "La fuente pidió esperar un poco. Se vuelve a intentar."
        case 500...599: "El servidor de la fuente falló. Se vuelve a intentar."
        default: "La descarga falló (código \(status))."
        }
    }
}

/// Quien baja de verdad (en la app, `URLSession` en segundo plano). En las pruebas, uno falso.
public protocol DownloadTransport: Sendable {
    func start(id: String, url: URL, resumeFrom: Int64, file: URL) async
    /// Pausa: detiene la descarga pero conserva lo bajado (si el transporte puede) para reanudar.
    func cancel(id: String) async
    /// Borrar: detiene la descarga y olvida todo lo bajado.
    func discard(id: String) async
    var events: AsyncStream<DownloadEvent> { get }
}

public extension DownloadTransport {
    func discard(id: String) async { await cancel(id: id) }
}

public enum DownloadError: Error, Sendable, Equatable, CustomStringConvertible {
    case notEnoughSpace(needed: Int64, free: Int64)
    case alreadyDownloaded
    case noURL
    case unsafePath
    public var description: String {
        switch self {
        case .notEnoughSpace(let needed, let free): return "No hay espacio: hacen falta \(needed / 1_000_000) MB y hay \(free / 1_000_000) MB libres."
        case .alreadyDownloaded: return "Ya está descargado."
        case .noURL: return "Esta fuente no tiene un enlace para descargar."
        case .unsafePath: return "El nombre de este título no sirve para guardarlo."
        }
    }
}

/// La cola de descargas: dos a la vez, reanuda, pide un enlace nuevo si el de Real-Debrid caducó (como mucho dos veces) y
/// reintenta con espera creciente sin frenar a las demás. Cada cambio se avisa a `onChange` (la app lo guarda en disco).
public actor Downloads {
    public static let maxActive = 2
    public static let maxAttempts = 5
    public static let maxRefreshes = 2
    public static let spaceMargin: Int64 = 500_000_000   // deja al menos 500 MB libres
    static let expiredStatuses: Set<Int> = [401, 403, 404, 410]

    private let transport: DownloadTransport
    private let secrets: SecretsStore
    private let root: URL
    private let freeSpace: @Sendable () -> Int64
    private let refresh: @Sendable (DownloadItem) async -> URL?
    private let subtitles: @Sendable (DownloadItem) async -> [(name: String, data: Data)]
    private let clock: @Sendable () -> Date
    private let backoff: @Sendable (Int) async -> Void
    private let onChange: @Sendable ([DownloadItem]) -> Void
    private var items: [String: DownloadItem] = [:]
    private var waiting = Set<String>()      // esperando su reintento (no se arrancan hasta que pase la espera)
    private var listening: Task<Void, Never>?
    private nonisolated let updatesHub = UpdatesHub()

    /// - refresh: pide un enlace nuevo de ese título (mismo complemento y fuente); nil si no hay.
    /// - subtitles: descarga los subtítulos de ese título (nombre de archivo y contenido).
    public init(transport: DownloadTransport, secrets: SecretsStore, root: URL, saved: [DownloadItem] = [],
                freeSpace: @escaping @Sendable () -> Int64, refresh: @escaping @Sendable (DownloadItem) async -> URL?,
                subtitles: @escaping @Sendable (DownloadItem) async -> [(name: String, data: Data)] = { _ in [] },
                clock: @escaping @Sendable () -> Date = { Date() }, backoff: @escaping @Sendable (Int) async -> Void = { attempt in
                    try? await Task.sleep(nanoseconds: UInt64(min(60, pow(2, Double(attempt)))) * 1_000_000_000) },
                onChange: @escaping @Sendable ([DownloadItem]) -> Void = { _ in }) {
        self.transport = transport; self.secrets = secrets; self.root = root; self.freeSpace = freeSpace; self.refresh = refresh
        self.subtitles = subtitles; self.clock = clock; self.backoff = backoff; self.onChange = onChange
        for var item in saved {
            // Tras cerrar la app lo que bajaba queda en cola: se retoma al arrancar.
            if item.state == .downloading { item.state = .queued }
            items[item.id] = item
        }
    }

    public func start() {
        guard listening == nil else { return }
        let events = transport.events
        listening = Task { [weak self] in for await event in events { await self?.handle(event) } }
        Task { await pump() }
    }

    public var all: [DownloadItem] { items.values.sorted { $0.createdAt < $1.createdAt } }
    public func item(_ id: String) -> DownloadItem? { items[id] }
    /// El archivo de una descarga, siempre DENTRO de la carpeta de descargas (un id raro no puede escapar de ella).
    public func fileURL(_ item: DownloadItem) -> URL { DownloadFiles.contained(root: root, relativePath: item.relativePath, id: item.id) }
    public var usedBytes: Int64 { items.values.reduce(0) { $0 + $1.writtenBytes } }

    /// Un flujo nuevo con cada cambio de la cola (cada pantalla pide el suyo: al cerrar una, las demás siguen).
    public nonisolated func makeUpdates() -> AsyncStream<[DownloadItem]> { updatesHub.makeStream() }

    private func changed() { let snapshot = all; onChange(snapshot); updatesHub.send(snapshot) }

    /// Lo que falta por bajar de las que ya están en marcha o en cola (para no prometer un espacio dos veces).
    private func pendingBytes(excluding id: String) -> Int64 {
        items.values.filter { $0.id != id && ($0.state == .downloading || $0.state == .queued) }
            .reduce(0) { $0 + max(0, ($1.expectedBytes ?? 0) - $1.writtenBytes) }
    }

    /// Añade a la cola. `url` es el enlace de la fuente (se guarda en el Keychain, no en el archivo de la cola).
    public func enqueue(_ item: DownloadItem, url: URL) throws {
        if let existing = items[item.id] {
            if existing.state == .done { throw DownloadError.alreadyDownloaded }
            if existing.state == .downloading || existing.state == .queued { return }   // ya está en marcha
        }
        if let size = item.expectedBytes {
            let free = freeSpace(), needed = Int64(Double(size) * 1.05) + Self.spaceMargin + pendingBytes(excluding: item.id)
            if needed > free { throw DownloadError.notEnoughSpace(needed: needed, free: free) }
        }
        secrets.set(SecretKey.download(item.id), url.absoluteString)
        var new = item
        new.state = .queued; new.attempts = 0; new.refreshes = 0; new.lastError = nil
        items[item.id] = new
        changed()
        Task { await pump() }
    }

    public func pause(_ id: String) async {
        guard var item = items[id], item.state == .downloading || item.state == .queued else { return }
        waiting.remove(id)
        await transport.cancel(id: id)
        guard items[id] != nil else { return }            // lo borraron mientras se pausaba
        item.state = .paused
        items[id] = item
        changed()
        await pump()
    }

    public func resume(_ id: String) {
        guard var item = items[id], item.state == .paused || item.state == .failed else { return }
        item.state = .queued; item.attempts = 0; item.refreshes = 0; item.lastError = nil
        items[id] = item
        changed()
        Task { await pump() }
    }

    /// Borra la descarga y su archivo.
    public func remove(_ id: String) async {
        guard let item = items.removeValue(forKey: id) else { return }
        waiting.remove(id)
        await transport.discard(id: id)
        let folder = fileURL(item).deletingLastPathComponent()
        // Nunca se borra la carpeta de descargas entera ni nada fuera de ella.
        if DownloadFiles.isStrictlyInside(folder, root: root) { try? FileManager.default.removeItem(at: folder) }
        secrets.set(SecretKey.download(id), nil)
        changed()
        await pump()
    }

    // MARK: cola
    private func pump() async {
        var active = items.values.filter { $0.state == .downloading }.count
        for var item in all where item.state == .queued && !waiting.contains(item.id) && active < Self.maxActive {
            guard let url = secrets.get(SecretKey.download(item.id)).flatMap(URL.init(string:)) else {
                item.state = .failed; item.lastError = DownloadError.noURL.description
                items[item.id] = item; continue
            }
            let file = fileURL(item)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let onDisk = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            // Se reanuda donde está el archivo parcial de verdad.
            item.writtenBytes = onDisk
            item.state = .downloading
            items[item.id] = item
            active += 1
            await transport.start(id: item.id, url: url, resumeFrom: onDisk, file: file)
        }
        changed()
    }

    /// Reintento con espera creciente SIN detener la cola (los eventos de las demás descargas siguen llegando).
    private func scheduleRetry(_ id: String, attempt: Int) {
        waiting.insert(id)
        Task {
            await backoff(attempt)
            waiting.remove(id)
            await pump()
        }
    }

    /// Menos de 2 MB cuando se esperaban más de 50: una lista de reproducción o una página de error, nunca un video.
    static func notTheVideo(size: Int64, advertised: Int64?) -> Bool {
        guard let advertised else { return false }
        return advertised > 50_000_000 && size < 2_000_000
    }

    private func handle(_ event: DownloadEvent) async {
        switch event {
        case .progress(let id, let written, let total):
            guard var item = items[id], item.state == .downloading else { return }
            item.writtenBytes = written
            // El tamaño del servidor manda (la fuente puede anunciar el de todo un paquete de temporada), salvo que sea
            // diminuto frente a lo anunciado: una lista HLS de 6 kB o una página de error no son el video, y la revisión
            // al terminar lo tiene que poder ver.
            if let total, !Self.notTheVideo(size: total, advertised: item.expectedBytes) { item.expectedBytes = total }
            items[id] = item
            changed()
        case .finished(let id):
            guard var item = items[id] else { return }
            let file = fileURL(item)
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            // Un «200» con una página de error o un video de aviso es muy menor de lo esperado: no es el archivo.
            if let expected = item.expectedBytes, expected > 10_000_000, size * 2 < expected || Self.notTheVideo(size: size, advertised: expected) {
                try? FileManager.default.removeItem(at: file)
                await fail(id, status: nil, message: "El archivo bajado está incompleto o no es el video")
                return
            }
            item.state = .done; item.finishedAt = clock().timeIntervalSince1970; item.attempts = 0; item.refreshes = 0; item.lastError = nil
            if size > 0 { item.writtenBytes = size; item.expectedBytes = size }
            secrets.set(SecretKey.download(id), nil)  // el enlace ya no hace falta
            items[id] = item
            changed()
            await saveSubtitles(for: id)
            changed()
            await pump()
        case .failed(let id, let status, let message):
            guard let item = items[id], item.state == .downloading else { return }
            if status == 416, let file = Optional(fileURL(item)) { try? FileManager.default.removeItem(at: file) }   // el parcial no cuadra: de nuevo desde cero
            await fail(id, status: status, message: message)
        }
    }

    /// Un fallo: enlace nuevo si caducó (con tope), reintento con espera, o «falló» al agotar los intentos.
    private func fail(_ id: String, status: Int?, message: String) async {
        guard var item = items[id] else { return }
        item.attempts += 1
        item.lastError = message
        if item.attempts >= Self.maxAttempts {
            item.state = .failed
            items[id] = item
            changed()
            await pump()
            return
        }
        if let status, Self.expiredStatuses.contains(status), item.refreshes < Self.maxRefreshes {
            item.refreshes += 1
            items[id] = item
            let current = secrets.get(SecretKey.download(id))
            let fresh = await refresh(item)
            // Mientras se pedía el enlace nuevo pudieron pausar o borrar la descarga: se revisa.
            guard let now = items[id], now.state == .downloading else { return }
            if let fresh, fresh.absoluteString != current {
                secrets.set(SecretKey.download(id), fresh.absoluteString)
                item = now
                item.state = .queued
                items[id] = item
                changed()
                scheduleRetry(id, attempt: item.attempts)
                await pump()
                return
            }
            item = now        // el mismo enlace muerto (o ninguno): cuenta como fallo normal
        }
        item.state = .queued
        items[id] = item
        changed()
        scheduleRetry(id, attempt: item.attempts)
        await pump()
    }

    private func saveSubtitles(for id: String) async {
        guard let snapshot = items[id] else { return }
        let found = await subtitles(snapshot)
        guard var item = items[id] else { return }          // lo borraron mientras se bajaban los subtítulos
        let folder = fileURL(item).deletingLastPathComponent().appendingPathComponent("subs")
        guard DownloadFiles.isStrictlyInside(folder, root: root) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for sub in found {
            let name = DownloadFiles.component(sub.name)
            guard (try? sub.data.write(to: folder.appendingPathComponent(name))) != nil else { continue }
            item.subtitleFiles.append("subs/\(name)")
        }
        items[id] = item
    }

    /// Para «reponer el siguiente episodio»: ¿qué episodio sigue a los ya descargados de esa serie y todavía no está?
    public func nextToDownload(metaID: String, meta: JSON, ahead: Int = 1) -> [String] {
        let have = Set(items.values.filter { $0.metaID == metaID }.map(\.videoID))
        let ids = CinemetaParsing.seasons(meta).filter { !$0.isSpecials }.flatMap { $0.episodes.map(\.id) }
        guard let lastDone = ids.lastIndex(where: { have.contains($0) }) else { return [] }
        return Array(ids.dropFirst(lastDone + 1).filter { !have.contains($0) }.prefix(ahead))
    }

    /// Quita lo ya visto (para «borrar al terminar de verlo»).
    public func removeWatched(isWatched: @Sendable (DownloadItem) -> Bool) async {
        for item in all where item.state == .done && isWatched(item) { await remove(item.id) }
    }
}

public enum DownloadFiles {
    /// La extensión del archivo a partir de la URL (o `mkv`).
    public static func fileExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ["mkv", "mp4", "m4v", "mov", "avi", "webm", "ts"].contains(ext) ? ext : "mkv"
    }

    /// Un nombre de carpeta o archivo seguro: sin caracteres raros, nunca vacío, nunca «.» ni «..», con largo acotado.
    public static func component(_ text: String) -> String {
        let cleaned = String(text.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "_" }.prefix(80))
        return cleaned.allSatisfy({ $0 == "." }) ? "_" : cleaned
    }

    /// Carpeta del título: ids de complementos o de Stremio (que no controlamos) no pueden salirse de la carpeta de descargas.
    public static func relativePath(metaID: String, videoID: String, ext: String) -> String {
        "\(component(metaID))/\(component(videoID))/video.\(component(ext))"
    }

    static func isStrictlyInside(_ url: URL, root: URL) -> Bool {
        let base = root.standardizedFileURL.path, path = url.standardizedFileURL.path
        return path.hasPrefix(base + "/") && path.count > base.count + 1
    }

    /// La ruta bajo la carpeta de descargas; si una ruta guardada (de un índice viejo o dañado) se saldría de ella, se usa una segura.
    static func contained(root: URL, relativePath: String, id: String) -> URL {
        let candidate = root.appendingPathComponent(relativePath)
        if isStrictlyInside(candidate, root: root) { return candidate }
        let safe = String(SHA1.hex(Array(id.utf8)).prefix(16))
        return root.appendingPathComponent("_invalid").appendingPathComponent(safe).appendingPathComponent("video.mkv")
    }
}

/// Reparte la cola a cada suscriptor (el último valor al suscribirse y cada cambio después).
final class UpdatesHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<[DownloadItem]>.Continuation] = [:]
    private var last: [DownloadItem]?

    func makeStream() -> AsyncStream<[DownloadItem]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
                if let last { continuation.yield(last) }
            }
            continuation.onTermination = { [weak self] _ in self?.lock.withLock { self?.continuations[id] = nil } }
        }
    }

    func send(_ items: [DownloadItem]) {
        let targets = lock.withLock { last = items; return Array(continuations.values) }
        for continuation in targets { continuation.yield(items) }
    }
}
