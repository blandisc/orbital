import Foundation

public enum DownloadState: String, Sendable, Codable { case queued, downloading, paused, failed, done }

/// Una descarga para ver sin conexión. NO guarda la URL de la fuente (lleva tu clave de Real-Debrid): esa
/// vive en el Keychain bajo `SecretKey.download(id)`.
public struct DownloadItem: Sendable, Codable, Equatable, Identifiable {
    public var id: String                 // «metaID|videoID»
    public var kind: String
    public var metaID: String
    public var videoID: String
    public var title: String              // el que se muestra (en tu idioma)
    public var originalTitle: String      // el de Cinemeta: lo que se guarda en Stremio
    public var subtitle: String           // «T2 · E5 · Trojan's Horse»
    public var poster: String?
    public var addonURL: String           // para pedir un enlace nuevo
    public var sourceIndex: Int           // qué fuente era (índice estable)
    public var expectedBytes: Int64?
    public var writtenBytes: Int64 = 0
    public var state: DownloadState = .queued
    public var relativePath: String       // dentro de la carpeta de descargas
    public var subtitleFiles: [String] = []
    public var attempts = 0
    public var lastError: String?
    public var createdAt: Double
    public var finishedAt: Double?

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

/// Quien baja de verdad (en la app, `URLSession` en segundo plano). En las pruebas, uno falso.
public protocol DownloadTransport: Sendable {
    func start(id: String, url: URL, resumeFrom: Int64, file: URL) async
    func cancel(id: String) async
    var events: AsyncStream<DownloadEvent> { get }
}

public enum DownloadError: Error, Sendable, Equatable, CustomStringConvertible {
    case notEnoughSpace(needed: Int64, free: Int64)
    case alreadyDownloaded
    case noURL
    public var description: String {
        switch self {
        case .notEnoughSpace(let needed, let free): return "No hay espacio: hacen falta \(needed / 1_000_000) MB y hay \(free / 1_000_000) MB libres."
        case .alreadyDownloaded: return "Ya está descargado."
        case .noURL: return "Esta fuente no tiene un enlace para descargar."
        }
    }
}

/// La cola de descargas: dos a la vez, reanuda con `Range`, pide un enlace nuevo si el de Real-Debrid caducó,
/// y reintenta con espera creciente. Cada cambio se guarda en `store` (sobrevive a cerrar la app).
public actor Downloads {
    public static let maxActive = 2
    public static let maxAttempts = 5
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
    private var listening: Task<Void, Never>?

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
    public func fileURL(_ item: DownloadItem) -> URL { root.appendingPathComponent(item.relativePath) }
    public var usedBytes: Int64 { items.values.reduce(0) { $0 + $1.writtenBytes } }

    private func changed() { onChange(all) }

    /// Añade a la cola. `url` es el enlace de la fuente (se guarda en el Keychain, no en el archivo de la cola).
    public func enqueue(_ item: DownloadItem, url: URL) throws {
        if let existing = items[item.id], existing.state == .done { throw DownloadError.alreadyDownloaded }
        if let size = item.expectedBytes {
            let free = freeSpace(), needed = Int64(Double(size) * 1.05) + Self.spaceMargin
            if needed > free { throw DownloadError.notEnoughSpace(needed: needed, free: free) }
        }
        secrets.set(SecretKey.download(item.id), url.absoluteString)
        var new = item
        new.state = .queued; new.attempts = 0; new.lastError = nil
        items[item.id] = new
        changed()
        Task { await pump() }
    }

    public func pause(_ id: String) async {
        guard var item = items[id], item.state == .downloading || item.state == .queued else { return }
        await transport.cancel(id: id)
        item.state = .paused
        items[id] = item
        changed()
        await pump()
    }

    public func resume(_ id: String) {
        guard var item = items[id], item.state == .paused || item.state == .failed else { return }
        item.state = .queued; item.attempts = 0; item.lastError = nil
        items[id] = item
        changed()
        Task { await pump() }
    }

    /// Borra la descarga y su archivo.
    public func remove(_ id: String) async {
        guard let item = items.removeValue(forKey: id) else { return }
        await transport.cancel(id: id)
        try? FileManager.default.removeItem(at: fileURL(item).deletingLastPathComponent())
        secrets.set(SecretKey.download(id), nil)
        changed()
        await pump()
    }

    // MARK: cola
    private func pump() async {
        var active = items.values.filter { $0.state == .downloading }.count
        for var item in all where item.state == .queued && active < Self.maxActive {
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

    private func handle(_ event: DownloadEvent) async {
        switch event {
        case .progress(let id, let written, let total):
            guard var item = items[id], item.state == .downloading else { return }
            item.writtenBytes = written
            if let total { item.expectedBytes = total }
            items[id] = item
            changed()
        case .finished(let id):
            guard var item = items[id] else { return }
            item.state = .done; item.finishedAt = clock().timeIntervalSince1970; item.attempts = 0; item.lastError = nil
            if let size = (try? FileManager.default.attributesOfItem(atPath: fileURL(item).path)[.size] as? Int64) { item.writtenBytes = size; item.expectedBytes = size }
            secrets.set(SecretKey.download(id), nil)  // el enlace ya no hace falta
            items[id] = item
            await saveSubtitles(for: id)
            changed()
            await pump()
        case .failed(let id, let status, let message):
            guard var item = items[id], item.state == .downloading else { return }
            item.attempts += 1
            item.lastError = message
            if let status, Self.expiredStatuses.contains(status), let fresh = await refresh(item) {
                // El enlace de Real-Debrid caducó: enlace nuevo y se continúa con Range desde lo que ya hay.
                secrets.set(SecretKey.download(id), fresh.absoluteString)
                item.state = .queued
                items[id] = item
                changed()
                await pump()
                return
            }
            if item.attempts >= Self.maxAttempts {
                item.state = .failed
                items[id] = item
                changed()
                await pump()
                return
            }
            item.state = .queued
            items[id] = item
            changed()
            await backoff(item.attempts)
            await pump()
        }
    }

    private func saveSubtitles(for id: String) async {
        guard var item = items[id] else { return }
        let found = await subtitles(item)
        let folder = fileURL(item).deletingLastPathComponent().appendingPathComponent("subs")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for sub in found {
            let name = sub.name.replacingOccurrences(of: "/", with: "_")
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

    /// Carpeta del título: sin caracteres que molesten en un nombre de archivo.
    public static func relativePath(metaID: String, videoID: String, ext: String) -> String {
        func clean(_ s: String) -> String { String(s.map { $0.isLetter || $0.isNumber || "-_.".contains($0) ? $0 : "_" }) }
        return "\(clean(metaID))/\(clean(videoID))/video.\(ext)"
    }
}
