import Foundation
import OrbitalCore

#if DEBUG   // solo la demo: DemoHTTPClient no existe en la versión del iPhone

/// La guía de la primera vez en la demo (`-demo-first-run`), sin salir a internet:
/// - Real-Debrid contesta según la clave que escribas: una que empieza con «BAD» no la reconoce, con «FREE» es una cuenta
///   gratuita y cualquier otra completa es Premium con 143 días. Tarda ~1,5 s, para ver «comprobando».
/// - Trakt da el código «7F3K-9QP2» y lo «apruebas» solo a los 6 s; luego trae unos vistos y una watchlist de ejemplo.
/// - Real-Debrid con código (RC1) da «R3D7B2KQ» y también se aprueba solo a los 6 s.
extension DemoHTTPClient {
    nonisolated(unsafe) private static var codeAskedAt: Date?
    nonisolated(unsafe) private static var debridAskedAt: Date?
    private static let guideLock = NSLock()
    /// Lo que tarda «aprobar» el código en la demo: da tiempo de ver (y capturar) la pantalla del código.
    static let guideApproveAfter: TimeInterval = 6

    func guideDemo(_ request: HTTPRequest) async -> HTTPResponse? {
        guard Demo.firstRun else { return nil }
        let url = request.url, path = url.path
        func json(_ value: JSON, status: Int = 200) -> HTTPResponse { HTTPResponse(status: status, data: value.serialized()) }
        if url.host == "api.real-debrid.com", path.hasSuffix("/user") {
            try? await Task.sleep(for: .milliseconds(1500))   // ds-exception: demora de red simulada (solo modo demo), para ver «comprobando»
            let token = (request.headers["Authorization"] ?? "").replacingOccurrences(of: "Bearer ", with: "")
            if token.hasPrefix("BAD") { return json(["error": "bad_token", "error_code": 8], status: 401) }
            let free = token.hasPrefix("FREE")
            let expires = ISO8601DateFormatter().string(from: Date().addingTimeInterval(143 * 86_400 + 3600))
            return json(["id": 1, "username": "fernando", "type": free ? "free" : "premium", "premium": .int(free ? 0 : 143 * 86_400), "expiration": .string(expires)])
        }
        // RC1 · Real-Debrid con código: «R3D7 B2KQ», que se «aprueba» solo a los 6 s, y una llave de demostración.
        if url.host == "api.real-debrid.com", path.hasPrefix("/oauth/v2/") {
            switch path {
            case "/oauth/v2/device/code":
                Self.guideLock.withLock { Self.debridAskedAt = Date() }
                return json(["device_code": "demo", "user_code": "R3D7B2KQ", "verification_url": "https://real-debrid.com/device", "interval": 1, "expires_in": 600])
            case "/oauth/v2/device/credentials":
                let asked = Self.guideLock.withLock { Self.debridAskedAt } ?? Date()
                guard Date().timeIntervalSince(asked) >= Self.guideApproveAfter else { return json([:], status: 403) }
                return json(["client_id": "demo", "client_secret": "demo"])
            case "/oauth/v2/token":
                return json(["access_token": .string(String(repeating: "DEMOK3Y", count: 7) + "XYZ"), "refresh_token": "demo", "expires_in": 3600])
            default: return nil
            }
        }
        guard url.host == "api.trakt.tv" else { return nil }
        switch path {
        case "/oauth/device/code":
            Self.guideLock.withLock { Self.codeAskedAt = Date() }
            return json(["device_code": "demo", "user_code": "7F3K-9QP2", "verification_url": "https://trakt.tv/activate", "interval": 1, "expires_in": 600])
        case "/oauth/device/token":
            let asked = Self.guideLock.withLock { Self.codeAskedAt } ?? Date()
            guard Date().timeIntervalSince(asked) >= Self.guideApproveAfter else { return json([:], status: 400) }
            return json(["access_token": "DEMO", "refresh_token": "DEMO", "expires_in": 7_776_000, "created_at": .int(Int(Date().timeIntervalSince1970))])
        case "/users/settings": return json(["user": ["username": "fernando", "name": "fernando"]])
        case "/sync/last_activities":
            return json(["movies": ["watched_at": "2026-10-28T20:00:00.000Z", "paused_at": "2026-10-28T20:00:00.000Z"],
                         "episodes": ["watched_at": "2026-10-28T20:00:00.000Z"], "watchlist": ["updated_at": "2026-10-28T20:00:00.000Z"]])
        case "/sync/watched/movies":
            return json(.array(["tt0816692", "tt1160419", "tt0111161", "tt0068646", "tt0468569"].map {
                ["last_watched_at": "2026-10-20T20:00:00.000Z", "movie": ["title": "Demo", "ids": ["imdb": .string($0)]]] }))
        case "/sync/watchlist":
            return json(.array(["tt15398776", "tt1375666", "tt0133093"].map {
                ["type": "movie", "listed_at": "2026-10-20T20:00:00.000Z", "movie": ["title": "Demo", "year": 2020, "ids": ["imdb": .string($0), "trakt": 1]]] }))
        default: return nil
        }
    }
}
#endif
