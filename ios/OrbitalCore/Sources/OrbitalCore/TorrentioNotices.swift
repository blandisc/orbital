import Foundation

/// Lo que Torrentio manda en lugar de una película cuando Real-Debrid no puede (R5/R6): una «versión» llamada «RD error»
/// o un video corto fijo de aviso (`providers/static_videos.rs` en su código: `videos/downloading_v3.mp4`,
/// `videos/failed_access_v3.mp4`…). Nunca es el título: no se ofrece, no se reproduce y dice por qué falló.
public enum StreamNotice: String, Sendable, Equatable, CaseIterable {
    /// Real-Debrid lo está bajando (`downloading`): la versión no estaba lista; ya se le pidió.
    case downloading
    /// Sin acceso (`failed_access`, la versión «RD error»): clave que ya no sirve, Premium vencido o cuenta sin Premium.
    /// Se pregunta a Real-Debrid cuál de las tres (`DebridAccount.refreshAfterTrouble`).
    case access
    /// Real-Debrid bloqueó la cuenta o la conexión (`blocked_access`).
    case blocked
    /// Real-Debrid no deja bajar ese archivo (`failed_infringement`: derechos reclamados).
    case infringing
    /// Llegaste al límite de Real-Debrid (`limits_exceeded`: demasiadas descargas a la vez).
    case limits
    /// Real-Debrid no pudo bajarlo o abrirlo (`failed_download`, `failed_rar`, `failed_too_big`, `failed_opening`,
    /// `failed_unexpected` y los que salgan).
    case downloadFailed

    /// Cuenta de Real-Debrid (no de esta versión): hay que preguntarle a Real-Debrid qué pasa.
    public var aboutTheAccount: Bool { self == .access || self == .blocked }
}

public enum TorrentioNotices {
    /// El nombre de los videos de aviso, sin su versión (`_v2`, `_v3` cambian): se reconocen por la ruta `/videos/…`.
    static let videos: [String: StreamNotice] = [
        "downloading": .downloading,
        "failed_access": .access, "blocked_access": .blocked,
        "failed_infringement": .infringing, "limits_exceeded": .limits,
        "failed_download": .downloadFailed, "download_failed": .downloadFailed, "failed_rar": .downloadFailed,
        "failed_too_big": .downloadFailed, "failed_opening": .downloadFailed, "failed_unexpected": .downloadFailed,
    ]
    static let videoPath = try! NSRegularExpression(pattern: #"^/videos/([a-z_]+?)(_v\d+)?\.mp4$"#)

    /// El aviso que es esta dirección (o nil si es un video de verdad). Solo la ruta: no se abre nada (ni se le pide a
    /// Real-Debrid), así que reconocerla no cuesta una conexión más.
    public static func notice(url: URL?) -> StreamNotice? {
        guard let path = url?.path, let match = videoPath.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let range = Range(match.range(at: 1), in: path) else { return nil }
        return videos[String(path[range])] ?? .downloadFailed   // otro aviso de Torrentio que todavía no se conoce
    }

    /// El de una versión de un complemento: su dirección o su nombre («Torrentio\nRD error»).
    public static func notice(name: String, url: URL?) -> StreamNotice? {
        if let byURL = notice(url: url) { return byURL }
        let lower = name.lowercased()
        return lower.contains("rd error") || lower.contains("[rd error]") ? .access : nil
    }
}

/// Las versiones de Real-Debrid que ya se pidieron al intentar verlas (abrir un «[RD download]» le pide a Real-Debrid que lo
/// baje): un reintento no las vuelve a pedir; se dice que ya está pedida. Solo en memoria: la libreta de pedidos llega en
/// la Fase 2.
public final class QueuedOnRealDebrid: @unchecked Sendable {
    public static let shared = QueuedOnRealDebrid()
    /// Lo que tarda Real-Debrid en bajar algo común; pasado eso, abrirla de nuevo ya no la pide otra vez.
    public static let keepFor: TimeInterval = 6 * 3600
    private let lock = NSLock()
    private var queued: [String: Date] = [:]
    public init() {}

    public func mark(_ key: String, at now: Date = Date()) { lock.withLock { queued[key] = now } }
    public func contains(_ key: String, now: Date = Date()) -> Bool {
        lock.withLock {
            queued = queued.filter { now.timeIntervalSince($0.value) < Self.keepFor }
            return queued[key] != nil
        }
    }
}
