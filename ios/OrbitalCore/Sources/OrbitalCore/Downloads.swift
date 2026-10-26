import CryptoKit
import Foundation

public enum DownloadState: String, Sendable, Codable { case queued, downloading, paused, failed, done }

/// Una descarga para ver sin conexión. NO guarda la URL de la fuente ni la del complemento (llevan tu clave de
/// Real-Debrid): la URL de la fuente vive en el Keychain bajo `SecretKey.download(id)`.
extension DownloadItem {
    /// La calidad de la copia, del nombre del archivo de su fuente («4K», «1080p»…): distingue qué versión tienes.
    public var quality: String? {
        let name = release.lowercased()
        if name.contains("2160p") || name.contains("4k") || name.contains("uhd") { return "4K" }
        return ["1440p", "1080p", "720p", "480p"].first { name.contains($0) }
    }
}

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
    /// Cuántas veces se intentó bajar sus subtítulos sin red de por medio (ver `Downloads.retryMissingSubtitles`).
    public var subtitleTries = 0
    /// Lo que se sabe de cada subtítulo guardado (idioma, fuente, copia, si es para sordos): para nombrarlos sin red.
    public var savedSubtitles: [SavedSubtitle] = []
    /// Ya se bajaron todos los que había (una búsqueda con red y sin fallas sueltas).
    public var subtitlesComplete = false

    /// Todos los guardados con su información; los de antes (sin índice: `es.srt`) con el idioma de su nombre.
    public var allSavedSubtitles: [SavedSubtitle] {
        subtitleFiles.compactMap { file in savedSubtitles.first { $0.file == file } ?? SavedSubtitle.legacy(file: file) }
    }
    public var attempts = 0
    public var refreshes = 0              // cuántas veces se pidió un enlace nuevo (tope: `Downloads.maxRefreshes`)
    /// Las fuentes que ya se probaron y no dieron el video (el aviso corto de Torrentio, una página de error): no se vuelven a elegir.
    public var skippedReleases: [String] = []
    public var lastError: String?
    /// En espera de red (no se guarda: es del momento).
    public var waitingForNetwork = false
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
        subtitleTries = try c.decodeIfPresent(Int.self, forKey: .subtitleTries) ?? 0
        savedSubtitles = try c.decodeIfPresent([SavedSubtitle].self, forKey: .savedSubtitles) ?? []
        subtitlesComplete = try c.decodeIfPresent(Bool.self, forKey: .subtitlesComplete) ?? false
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        refreshes = try c.decodeIfPresent(Int.self, forKey: .refreshes) ?? 0
        skippedReleases = try c.decodeIfPresent([String].self, forKey: .skippedReleases) ?? []
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        finishedAt = try c.decodeIfPresent(Double.self, forKey: .finishedAt)
    }

    enum Keys: String, CodingKey {
        case id, kind, metaID, videoID, title, originalTitle, subtitle, poster, addon, release, sourceIndex, expectedBytes, writtenBytes, state
        case relativePath, subtitleFiles, subtitleTries, savedSubtitles, subtitlesComplete, attempts, refreshes, skippedReleases, lastError, createdAt, finishedAt
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(id, forKey: .id); try c.encode(kind, forKey: .kind); try c.encode(metaID, forKey: .metaID); try c.encode(videoID, forKey: .videoID)
        try c.encode(title, forKey: .title); try c.encode(originalTitle, forKey: .originalTitle); try c.encode(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(poster, forKey: .poster); try c.encode(addon, forKey: .addon); try c.encode(release, forKey: .release)
        try c.encode(sourceIndex, forKey: .sourceIndex); try c.encodeIfPresent(expectedBytes, forKey: .expectedBytes); try c.encode(writtenBytes, forKey: .writtenBytes)
        try c.encode(state, forKey: .state); try c.encode(relativePath, forKey: .relativePath); try c.encode(subtitleFiles, forKey: .subtitleFiles)
        try c.encode(subtitleTries, forKey: .subtitleTries)
        try c.encode(savedSubtitles, forKey: .savedSubtitles); try c.encode(subtitlesComplete, forKey: .subtitlesComplete)
        try c.encode(attempts, forKey: .attempts); try c.encode(refreshes, forKey: .refreshes); try c.encode(skippedReleases, forKey: .skippedReleases); try c.encodeIfPresent(lastError, forKey: .lastError)
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
    /// El sistema la tiene en espera de red (con «Solo con Wi‑Fi», sin Wi‑Fi).
    case waiting(id: String)
}

public enum DownloadMessages {
    /// Lo que se le dice a la persona cuando el servidor contesta con un error (nunca «HTTP 403» a secas).
    public static func forStatus(_ status: Int) -> String {
        switch status {
        case 401, 403, 404, 410: "El enlace de esta versión caducó o ya no existe. Toca ▶ para buscar otro."
        case 416: "Lo bajado no cuadra con el archivo: se empieza de nuevo."
        case 429: "El servidor pidió esperar un poco. Se vuelve a intentar."
        case 500...599: "El servidor falló. Se vuelve a intentar."
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
        case .notEnoughSpace(let needed, let free): return "Hacen falta \(needed / 1_000_000) MB y hay \(free / 1_000_000) MB libres."
        case .alreadyDownloaded: return "Ya está descargado."
        case .noURL: return "Esta versión no tiene un enlace para descargar."
        case .unsafePath: return "El nombre de este título no sirve para guardarlo."
        }
    }
}

/// Otra fuente del mismo video, para cuando la de una descarga no da el archivo.
public struct DownloadSource: Sendable, Equatable {
    public var url: URL, addon: String, release: String, sourceIndex: Int, size: Int64?
    public init(url: URL, addon: String, release: String, sourceIndex: Int, size: Int64?) {
        self.url = url; self.addon = addon; self.release = release; self.sourceIndex = sourceIndex; self.size = size
    }
}

/// La cola de descargas: dos a la vez, reanuda, pide un enlace nuevo si el de Real-Debrid caducó (como mucho dos veces) y
/// reintenta con espera creciente sin frenar a las demás. Cada cambio se avisa a `onChange` (la app lo guarda en disco).
public actor Downloads {
    public static let maxActive = 2
    public static let maxAttempts = 5
    public static let maxRefreshes = 2
    /// Cuántas fuentes distintas se prueban cuando la de una descarga no da el video.
    public static let maxSourceSwaps = 3
    public static let spaceMargin: Int64 = 500_000_000   // deja al menos 500 MB libres
    static let expiredStatuses: Set<Int> = [401, 403, 404, 410]

    private let transport: DownloadTransport
    private let secrets: SecretsStore
    private let root: URL
    private let freeSpace: @Sendable () -> Int64
    private let refresh: @Sendable (DownloadItem) async -> URL?
    private let otherSource: @Sendable (DownloadItem) async -> DownloadSource?
    private let subtitles: @Sendable (DownloadItem) async -> SubtitleFetch?
    private let clock: @Sendable () -> Date
    private let backoff: @Sendable (Int) async -> Void
    private let onChange: @Sendable ([DownloadItem]) -> Void
    private var items: [String: DownloadItem] = [:]
    private var waiting = Set<String>()      // esperando su reintento (no se arrancan hasta que pase la espera)
    /// Un solo `pump` a la vez (el actor deja entrar otro en cada `await`: dos podían arrancar la misma o pasarse del tope).
    private var pumping = false, pumpAgain = false
    /// La app se va a segundo plano: se crean de una vez todas las de la cola. Una tarea creada en segundo plano (la siguiente
    /// al terminar una, un reintento) iOS la trata como «discrecional» y puede esperar horas a Wi‑Fi y carga; creadas antes,
    /// el sistema las va bajando en orden (dos a la vez por servidor) sin esa espera.
    private var backgrounded = false

    public func setBackgrounded(_ value: Bool) async {
        backgrounded = value
        if value { await pump() } else { await retryMissingSubtitles() }
    }
    private var listening: Task<Void, Never>?
    private nonisolated let updatesHub = UpdatesHub()

    /// - refresh: pide un enlace nuevo de ese título (mismo complemento y fuente); nil si no hay.
    /// - otherSource: otra fuente del mismo video que no esté en `skippedReleases` (la de ahora mandó algo que no es el video).
    /// - subtitles: baja los subtítulos de ese título que aún no tiene (contenido e información); nil si no hubo red.
    public init(transport: DownloadTransport, secrets: SecretsStore, root: URL, saved: [DownloadItem] = [],
                freeSpace: @escaping @Sendable () -> Int64, refresh: @escaping @Sendable (DownloadItem) async -> URL?,
                otherSource: @escaping @Sendable (DownloadItem) async -> DownloadSource? = { _ in nil },
                subtitles: @escaping @Sendable (DownloadItem) async -> SubtitleFetch? = { _ in SubtitleFetch(files: []) },
                clock: @escaping @Sendable () -> Date = { Date() }, backoff: @escaping @Sendable (Int) async -> Void = { attempt in
                    try? await Task.sleep(nanoseconds: UInt64(min(60, pow(2, Double(attempt)))) * 1_000_000_000) },
                onChange: @escaping @Sendable ([DownloadItem]) -> Void = { _ in }) {
        self.transport = transport; self.secrets = secrets; self.root = root; self.freeSpace = freeSpace; self.refresh = refresh; self.otherSource = otherSource
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
        Task { await pump(); await retryMissingSubtitles() }
    }

    public var all: [DownloadItem] { items.values.sorted { $0.createdAt < $1.createdAt } }
    public func item(_ id: String) -> DownloadItem? { items[id] }
    /// El archivo de una descarga, siempre DENTRO de la carpeta de descargas (un id raro no puede escapar de ella).
    public func fileURL(_ item: DownloadItem) -> URL { DownloadFiles.contained(root: root, relativePath: item.relativePath, id: item.id) }
    public var usedBytes: Int64 { items.values.reduce(0) { $0 + $1.writtenBytes } }

    /// Un flujo nuevo con cada cambio de la cola (cada pantalla pide el suyo: al cerrar una, las demás siguen).
    public nonisolated func makeUpdates() -> AsyncStream<[DownloadItem]> { updatesHub.makeStream() }

    /// `persist: false` para el avance: antes cada avance (4 por segundo con dos descargas) reescribía todo el índice en disco.
    /// Al relanzar, lo bajado se recupera del archivo y de los datos de reanudación, no del índice.
    private func changed(persist: Bool = true) { let snapshot = all; if persist { onChange(snapshot) }; updatesHub.send(snapshot) }

    /// Lo que falta por bajar de las que ya están en marcha o en cola (para no prometer un espacio dos veces).
    private func pendingBytes(excluding id: String) -> Int64 {
        items.values.filter { $0.id != id && ($0.state == .downloading || $0.state == .queued) }
            .reduce(0) { $0 + max(0, ($1.expectedBytes ?? 0) - $1.writtenBytes) }
    }

    /// Añade a la cola. `url` es el enlace de la fuente (se guarda en el Keychain, no en el archivo de la cola).
    /// ¿Cabe esta descarga si se borra `freeing`? La misma cuenta que `enqueue` (con su margen y lo que falta de las demás):
    /// cambiar de fuente no borra tu copia si la nueva no va a caber.
    public func canFit(_ item: DownloadItem, freeing: String) -> Bool {
        guard let size = item.expectedBytes else { return true }
        let old = items[freeing]?.writtenBytes ?? 0
        let needed = Int64(Double(size) * 1.05) + Self.spaceMargin + pendingBytes(excluding: item.id)
        return needed <= freeSpace() + old
    }

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
        guard let before = items[id], before.state == .downloading || before.state == .queued else { return }
        waiting.remove(id)
        await transport.cancel(id: id)
        // Se vuelve a leer después de esperar: la borraron o terminó mientras se pausaba (no se pisa un «listo» con «en pausa»).
        guard var item = items[id], item.state == .downloading || item.state == .queued else { return }
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
        if pumping { pumpAgain = true; return }
        pumping = true
        repeat { pumpAgain = false; await pumpOnce() } while pumpAgain
        pumping = false
    }

    private func pumpOnce() async {
        var active = items.values.filter { $0.state == .downloading }.count
        let limit = backgrounded ? Int.max : Self.maxActive
        for var item in all where item.state == .queued && !waiting.contains(item.id) && active < limit {
            guard let latest = items[item.id], latest.state == .queued, latest.createdAt == item.createdAt else { continue }   // cambió mientras arrancaba otra
            item = latest
            guard let url = secrets.get(SecretKey.download(item.id)).flatMap(URL.init(string:)) else {
                item.state = .failed; item.lastError = DownloadError.noURL.description
                items[item.id] = item; continue
            }
            let file = fileURL(item)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let onDisk = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            // Ya estaba completo (terminó en segundo plano y la app se cerró antes de anotarlo): se anota, no se baja otra vez.
            if let expected = item.expectedBytes, expected > Self.wholeVideoMinimum, onDisk >= expected {
                item.state = .done; item.writtenBytes = onDisk; item.finishedAt = clock().timeIntervalSince1970; item.lastError = nil
                items[item.id] = item
                secrets.set(SecretKey.download(item.id), nil)
                let id = item.id
                Task { await saveSubtitles(for: id); changed() }   // también sus subtítulos, como al terminar normal
                continue
            }
            // Se reanuda donde está el archivo parcial de verdad. En segundo plano lo bajado vive en los datos de reanudación
            // del sistema, no en el archivo: el avance no se regresa a cero al retomarla (al bloquear el iPhone parecía que
            // se reiniciaba); el primer avance real lo corrige si de verdad empezó de nuevo.
            item.writtenBytes = max(onDisk, item.writtenBytes)
            item.state = .downloading
            items[item.id] = item
            active += 1
            await transport.start(id: item.id, url: url, resumeFrom: onDisk, file: file)
            // Mientras arrancaba la borraron o la pausaron: la tarea que se acaba de crear no se queda bajando a escondidas.
            if items[item.id] == nil { await transport.discard(id: item.id) }
            else if items[item.id]?.state != .downloading { await transport.cancel(id: item.id) }
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

    /// Un video de verdad (no un tamaño anunciado a medias): solo con esto se da por completo un archivo que ya estaba en disco.
    static let wholeVideoMinimum: Int64 = 50_000_000

    /// Menos de 2 MB cuando se esperaban más de 50: una lista de reproducción o una página de error, nunca un video.
    static func notTheVideo(size: Int64, advertised: Int64?) -> Bool {
        guard let advertised else { return false }
        return advertised > 50_000_000 && size < 2_000_000
    }

    private func handle(_ event: DownloadEvent) async {
        switch event {
        case .waiting(let id):
            guard var item = items[id], item.state == .downloading, !item.waitingForNetwork else { return }
            item.waitingForNetwork = true
            items[id] = item
            changed()
        case .progress(let id, let written, let total):
            guard var item = items[id], item.state == .downloading else { return }
            item.writtenBytes = written
            item.waitingForNetwork = false
            // El tamaño del servidor manda (la fuente puede anunciar el de todo un paquete de temporada), salvo que sea
            // diminuto frente a lo anunciado: una lista HLS de 6 kB o una página de error no son el video, y la revisión
            // al terminar lo tiene que poder ver.
            if let total, !Self.notTheVideo(size: total, advertised: item.expectedBytes) { item.expectedBytes = total }
            items[id] = item
            changed(persist: false)
        case .finished(let id):
            guard var item = items[id] else { return }
            let file = fileURL(item)
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            // Un «200» con una página de error o un video de aviso es muy menor de lo esperado: no es el archivo.
            if let expected = item.expectedBytes, expected > 10_000_000, size * 2 < expected || Self.notTheVideo(size: size, advertised: expected) {
                try? FileManager.default.removeItem(at: file)
                // Muy chico frente a lo esperado: esa fuente no da el video (Real-Debrid no la tiene lista). Se prueba otra en vez de
                // insistir cinco veces con la misma.
                if Self.notTheVideo(size: size, advertised: expected), await swapSource(id) { return }
                await fail(id, status: nil, message: "El archivo bajado está incompleto o no es el video")
                return
            }
            item.state = .done; item.finishedAt = clock().timeIntervalSince1970; item.attempts = 0; item.refreshes = 0; item.lastError = nil
            if size > 0 { item.writtenBytes = size; item.expectedBytes = size }
            secrets.set(SecretKey.download(id), nil)  // el enlace ya no hace falta
            items[id] = item
            changed()
            // La siguiente arranca ya; los subtítulos se bajan aparte (antes la cola esperaba hasta 20 s por idioma).
            await pump()
            Task { await self.saveSubtitles(for: id); self.changedAfterSubtitles() }
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
            // Mientras se pedía el enlace nuevo pudieron pausar, borrar o cambiar por otra versión la descarga: se revisa.
            guard let now = items[id], now.state == .downloading, now.createdAt == item.createdAt else { return }
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

    /// Cambia la fuente de una descarga por otra del mismo video y la vuelve a formar desde cero. false: no hay otra.
    private func swapSource(_ id: String) async -> Bool {
        guard var item = items[id], item.skippedReleases.count < Self.maxSourceSwaps else { return false }
        item.skippedReleases.append(item.release.isEmpty ? "#\(item.sourceIndex)" : item.release)
        items[id] = item
        guard let next = await otherSource(item) else { return false }
        // Mientras se buscaba pudieron pausar, borrar o cambiar la descarga: se revisa.
        guard var fresh = items[id], fresh.state == .downloading, fresh.createdAt == item.createdAt else { return true }
        await transport.discard(id: id)
        fresh.addon = next.addon; fresh.release = next.release; fresh.sourceIndex = next.sourceIndex; fresh.expectedBytes = next.size
        fresh.writtenBytes = 0; fresh.attempts = 0; fresh.refreshes = 0; fresh.lastError = nil; fresh.state = .queued
        secrets.set(SecretKey.download(id), next.url.absoluteString)
        items[id] = fresh
        changed()
        await pump()
        return true
    }

    private func changedAfterSubtitles() { changed() }

    /// Las descargas terminadas a las que les faltan subtítulos (no había red al terminar, alguno falló, o son de antes y
    /// solo tienen `es.srt`): se vuelven a pedir al abrir la app y al volver a ella, y solo se bajan los que no están. Sin red
    /// no cuenta como intento; con red, a lo más `maxSubtitleTries`.
    public func retryMissingSubtitles() async {
        for item in all where item.state == .done && !item.subtitlesComplete && item.subtitleTries < Self.maxSubtitleTries {
            await saveSubtitles(for: item.id)
        }
        changed()
    }
    static let maxSubtitleTries = 3
    private var fetchingSubtitles = Set<String>()

    private func saveSubtitles(for id: String) async {
        guard let snapshot = items[id], fetchingSubtitles.insert(id).inserted else { return }
        defer { fetchingSubtitles.remove(id) }
        let fetched = await subtitles(snapshot)
        // Lo borraron (o lo cambiaron por otra versión) mientras se bajaban los subtítulos: no son de esta.
        guard var item = items[id], item.createdAt == snapshot.createdAt else { return }
        guard let fetch = fetched else { return }   // sin red: se intenta otra vez (`retryMissingSubtitles`)
        item.subtitleTries += 1
        let folder = fileURL(item).deletingLastPathComponent().appendingPathComponent("subs")
        guard DownloadFiles.isStrictlyInside(folder, root: root) else { items[id] = item; return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Lo que ya está (también los de antes, sin índice): el mismo archivo no se guarda dos veces, aunque venga de otro enlace.
        var hashes = Set<String>()
        var ids = Set(item.savedSubtitles.compactMap(\.fileID))
        for file in item.subtitleFiles {
            if let sha = item.savedSubtitles.first(where: { $0.file == file })?.sha { hashes.insert(sha) }
            else if let data = try? Data(contentsOf: folder.deletingLastPathComponent().appendingPathComponent(file)) { hashes.insert(Self.sha(data)) }
        }
        var saveFailed = false
        for sub in fetch.files {
            let sha = Self.sha(sub.data)
            guard hashes.insert(sha).inserted else { continue }
            if let fileID = sub.info.fileID, !ids.insert(fileID).inserted { continue }
            let name = Self.freeName(language: sub.info.language, taken: Set(item.subtitleFiles), folder: folder)
            guard (try? sub.data.write(to: folder.appendingPathComponent(name))) != nil else { saveFailed = true; continue }
            var info = sub.info
            info.file = "subs/\(name)"; info.sha = sha
            item.subtitleFiles.append(info.file)
            item.savedSubtitles.append(info)
        }
        item.subtitlesComplete = fetch.complete && !saveFailed
        items[id] = item
    }

    /// «es-1.srt», «es-2.srt»…: el primero libre (ni en la lista ni en disco; `es.srt` de antes se queda como está).
    static func freeName(language: String, taken: Set<String>, folder: URL) -> String {
        var n = 1
        while taken.contains("subs/\(language)-\(n).srt") || FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(language)-\(n).srt").path) { n += 1 }
        return "\(language)-\(n).srt"
    }

    static func sha(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Un subtítulo que buscaste para una descarga (en «Buscar subtítulos»): se guarda junto al video, para verlo sin conexión.
    @discardableResult
    public func addSubtitle(id: String, name: String, data: Data) -> Bool {
        guard var item = items[id] else { return false }
        let folder = fileURL(item).deletingLastPathComponent().appendingPathComponent("subs")
        guard DownloadFiles.isStrictlyInside(folder, root: root) else { return false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = DownloadFiles.component(name)
        guard (try? data.write(to: folder.appendingPathComponent(file))) != nil else { return false }
        if !item.subtitleFiles.contains("subs/\(file)") { item.subtitleFiles.append("subs/\(file)") }
        items[id] = item
        changed()
        return true
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
