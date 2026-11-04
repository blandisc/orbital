#if DEBUG
import Foundation
import OrbitalAddons
import OrbitalCore
import OrbitalModels

/// `-demo-viento before|ready|ready-unlisted` con `-demo-title movie:tt0061752`: «El viento tiene miedo» (México, 1968) como
/// la probó Fernando el 3 nov, con los nombres reales de Torrentio. Nada sale a internet.
/// - `before`: Real-Debrid solo tiene la de voz rusa (va a «Más idiomas»): la ficha dice «Pedirlo y avisarme» sin prometer
///   otra versión que la lista no enseña.
/// - `ready`: ya pediste la de YTS 1080p y Real-Debrid la terminó, pero Torrentio la sigue llamando «[RD download]»: «Ver»
///   pone esa y «Versión» dice «Al instante · la pediste».
/// - `ready-unlisted`: igual, pero Torrentio ni la lista (con «solo lo que ya está»): se ve con el enlace de tu Real-Debrid.
enum DemoViento {
    static var mode: String? { Demo.value(after: "-demo-viento") }
    static let id = "tt0061752"
    static let yts1080 = "b3bdbf12d9d59e94fcff16bf1e7f893a37a75d78"
    static let video = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"

    /// Lo que da Torrentio para la película (3 nov 2026): huella, archivo, calidad, nombre y la línea de abajo.
    static let rows: [(hash: String, file: Int, quality: String, title: String, ruso: Bool)] = [
        (yts1080, 0, "1080p", "Even the Wind Is afraid 1968 1080p BluRay\n👤 11 💾 1.5 GB ⚙️ YTS", false),
        ("f43bffedb4b30be2967e5aec91588e0bf9688858", 0, "1080p", "Even.the.Wind.Is.Afraid.1968.SPANISH.1080p.BluRay.x265-VXT\n👤 4 💾 1.4 GB ⚙️ RARBG\n🇪🇸", false),
        ("71dba5d524b5c6dda7eeb5bc83e8118ae8fe9ad1", 0, "720p", "Even the Wind Is afraid 1968 720p BluRay\n👤 5 💾 826.66 MB ⚙️ YTS", false),
        ("568ad8f0058b1faeab84044284d026b08fd75a1c", 0, "DVDRip", "Даже ветер может бояться / Hasta el viento tiene miedo [1968 DVDRip] VO\n👤 3 💾 1.46 GB ⚙️ Rutracker\n🇷🇺", true),
    ]

    static func respond(_ request: HTTPRequest) -> HTTPResponse? {
        guard let mode else { return nil }
        let url = request.url
        func json(_ value: JSON, _ status: Int = 200) -> HTTPResponse { HTTPResponse(status: status, data: value.serialized()) }
        // Tu complemento con Real-Debrid.
        if url.host == "demo.orbital.invalid", url.path == "/stream/movie/\(id).json" {
            let streams: [JSON] = rows.compactMap { r in
                if mode == "ready-unlisted", r.hash == yts1080 { return nil }
                let mark = r.ruso ? "[RD+]" : "[RD download]"
                return ["name": .string("\(mark) Torrentio\n\(r.quality)"), "title": .string(r.title),
                        "url": .string("https://demo.orbital.invalid/resolve/realdebrid/DEMO/\(r.hash)/null/\(r.file)/x.mkv")]
            }
            return json(["streams": .array(streams)])
        }
        // Tu Torrentio sin Real-Debrid (lo que existe, para pedir).
        if url.host == "torrentio.strem.fun", url.path.hasSuffix("/stream/movie/\(id).json") {
            return json(["streams": .array(rows.map { r in
                ["name": .string("Torrentio\n\(r.quality)"), "title": .string(r.title), "infoHash": .string(r.hash), "fileIdx": .int(r.file)]
            })])
        }
        // Tu Real-Debrid: el pedido listo, su enlace y el enlace para verlo.
        if url.host == "api.real-debrid.com", url.path.hasSuffix("/torrents/info/DEMOVIENTO") {
            return json(["id": "DEMOVIENTO", "hash": .string(yts1080), "filename": "Even.The.Wind.Is.Afraid.1968.1080p.BluRay.x264.AAC-[YTS.MX].mp4",
                         "status": "downloaded", "progress": 100,
                         "files": [["id": 1, "path": "/Even.The.Wind.Is.Afraid.1968.1080p.BluRay.x264.AAC-[YTS.MX].mp4", "bytes": 1_500_000_000, "selected": 1]],
                         "links": ["https://real-debrid.com/d/DEMOVIENTO"]])
        }
        if url.host == "api.real-debrid.com", url.path.hasSuffix("/unrestrict/link") { return json(["download": .string(video)]) }
        // TMDB en «es-MX»: como la de verdad, el título en inglés (no traduce al mismo idioma) y el original en español.
        if url.host == "api.themoviedb.org", url.path.hasSuffix("/find/\(id)") { return json(["movie_results": [["id": 41]]]) }
        if url.host == "api.themoviedb.org", url.path.hasSuffix("/movie/41") {
            return json(["id": 41, "title": "Even the Wind Is Afraid", "original_title": "Hasta el viento tiene miedo", "original_language": "es",
                         "overview": "Unas alumnas castigadas en un internado se enfrentan al fantasma de una compañera que murió en la torre.",
                         "genres": [["name": "Terror"]]])
        }
        return nil
    }

    /// La libreta con el pedido ya listo (`ready`, `ready-unlisted`).
    @MainActor static func seed(_ services: Services) {
        guard let mode, mode.hasPrefix("ready") else { return }
        var request = DebridRequest(hash: yts1080, fileIdx: 0, rdID: "DEMOVIENTO", title: "Hasta el viento tiene miedo", kind: "movie", metaID: id,
                                    videoIDs: [id], language: "es-419", release: "Even the Wind Is afraid 1968 1080p BluRay", device: services.deviceName,
                                    createdAt: Date().addingTimeInterval(-3 * 3600), rdStatus: "downloaded", percent: 100, state: .ready)
        request.notified = true; request.nudged = true; request.pending = false
        services.debridRequests.requester.book.put(request)
        services.debridRequests.reloadForDemo()
    }
}
#endif
