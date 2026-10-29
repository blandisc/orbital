import CryptoKit
import Foundation

/// Los tipos de las descargas: el elemento y su estado, los eventos del transporte, los mensajes, el transporte y la fuente.

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
