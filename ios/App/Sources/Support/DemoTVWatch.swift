#if DEBUG
import Foundation
import OrbitalCore

/// La TV de mentira para «Cómo lo ves» (IV-A, IV-B) y la tarjeta de lo enfocado (CT-A), para probarlas en el simulador:
/// - Con `-demo-tv-horror` las pistas de audio y subtítulos cambian de verdad al elegirlas, y `/api/stremio/sources` da
///   versiones con su huella; `/api/stremio/play` con `source_key` cambia «la versión puesta» (se ve en el nombre del audio).
/// - `-demo-tv-focus`: la TV en su Inicio con «Dune: Parte dos» enfocada (y `-demo-tv-focus game`: un juego, sin IMDb).
final class DemoTVWatch: @unchecked Sendable {
    static let shared = DemoTVWatch()
    private let lock = NSLock()
    private var audio = "1", subtitle: String? = "3", version = "4K · HDR"
    /// Lo último que se pidió reproducir (las pruebas de interfaz lo leen en el letrero de la pista de audio).
    private(set) var played: String?

    static let versions: [(key: String, res: String, hdr: Bool, size: String, langs: [String], audio: String)] = [
        ("rd|aaa|0", "4K", true, "18.2 GB", ["Inglés", "Español"], "Atmos"),
        ("rd|bbb|0", "1080p", false, "4.1 GB", ["Español"], "5.1"),
        ("rd|ccc|0", "720p", false, "1.3 GB", ["Inglés"], ""),
    ]

    var tracks: JSON {
        lock.withLock {
            let audios: [(String, String)] = [("1", "Inglés 5.1 · \(version)"), ("2", "Español latino")]
            let subs: [(String, String)] = [("3", "Español"), ("4", "Inglés · SDH")]
            return ["audio": .array(audios.map { ["id": .string($0.0), "label": .string($0.1), "selected": .bool($0.0 == audio)] }),
                    "subtitles": .array(subs.map { ["id": .string($0.0), "label": .string($0.1), "selected": .bool($0.0 == subtitle)] })]
        }
    }

    /// Un cambio de pista que mandó el control.
    func control(_ body: JSON?) {
        guard let action = body?["action"]?.string, let track = body?["track"]?.string else { return }
        lock.withLock {
            if action == "audio" { audio = track }
            if action == "subtitles" { subtitle = track == "no" ? nil : track }
        }
    }

    func respond(_ path: String, query: String?, body: JSON?) -> HTTPResponse? {
        if path == "/api/stremio/sources" {
            let rows: [JSON] = Self.versions.enumerated().map { i, v in
                ["id": .int(i), "key": .string(v.key), "resolution": .string(v.res), "hdr": .bool(v.hdr), "size": .string(v.size),
                 "cached": true, "debrid": true, "languages": .array(v.langs.map { .string($0) }), "audio": .string(v.audio), "dub": false]
            }
            return HTTPResponse(status: 200, data: JSON.object(["sources": .array(rows)]).serialized())
        }
        if path == "/api/stremio/play" {
            let key = body?["source_key"]?.string
            lock.withLock {
                played = key
                if let v = Self.versions.first(where: { $0.key == key }) { version = v.hdr ? "\(v.res) · HDR" : v.res }
            }
            return HTTPResponse(status: 200, data: JSON.object(["ok": true]).serialized())
        }
        return nil
    }

    /// `-demo-tv-focus`: la TV en su Inicio con algo enfocado.
    static var focusUI: JSON? {
        guard Demo.has("-demo-tv-focus") else { return nil }
        let what = Demo.value(after: "-demo-tv-focus") == "game" ? "game" : "dune"
        let focus: JSON = what == "game"
            ? ["title": "Elden Ring", "image": "https://cdn.cloudflare.steamstatic.com/steam/apps/1245620/library_600x900.jpg", "kind": "game",
               "id": .null, "detail": "Steam · 72 h", "watchable": false]
            : ["title": "Dune: Parte dos", "image": .null, "kind": "movie", "id": "tt15239678", "detail": "2024 · Ciencia ficción", "watchable": true]
        return ["screen": "home", "text_field": false, "section": "Inicio", "focus": focus,
                "legend": ["select": what == "game" ? "Jugar" : "Ver", "back": "Atrás", "alt": "Mi lista", "options": "Más", "menu": "Menú", "search": "Buscar"],
                "volume": ["level": 40, "muted": false, "extra_max": 200]]
    }
}
#endif
