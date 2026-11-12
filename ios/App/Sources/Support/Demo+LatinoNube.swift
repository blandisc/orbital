#if DEBUG
import Foundation
import OrbitalCore

/// `-demo-latino-nube` con `-demo-title movie:tt1160419 -demo-open sources`: «Versión» como la vio Fernando el 12 nov con Los
/// Simpson T11E2 (solo llegó Comet, todo en inglés, y Torrentio, que tenía el latino, no contestó a tiempo). Nada sale a internet.
/// - Torrentio (con Real-Debrid) tarda más que su tope: «No contestó a tiempo: Torrentio · Reintentar».
/// - Comet da tres en inglés que arrancan al instante; una es «Multi»: se revisa por dentro (su encabezado dice inglés y
///   francés: «Comprobado»). Con `-demo-latino-nube found`, su encabezado trae una pista «Español Latino» y pasa a latino.
/// - Tu Torrentio sin Real-Debrid sí tiene una en latino: «Hay latino, pero hay que pedirlo a la nube» arriba de la lista.
enum DemoLatinoNube {
    static var mode: String? { Demo.has("-demo-latino-nube") ? (Demo.value(after: "-demo-latino-nube") ?? "") : nil }
    static var isOn: Bool { mode != nil }
    static let id = "tt1160419"
    static let lanes = ["torrentio", "comet"]
    static let multi = "https://demo.orbital.invalid/comet/playback/multi.mkv"
    static let latinoHash = "6c3f0b4a1e2d5f7a8b9c0d1e2f3a4b5c6d7e8f90"

    static func respond(_ request: HTTPRequest) async -> HTTPResponse? {
        guard let mode else { return nil }
        let url = request.url
        func json(_ value: JSON) -> HTTPResponse { HTTPResponse(status: 200, data: value.serialized()) }
        if url.host == "demo.orbital.invalid", let lane = lanes.first(where: { url.path.hasPrefix("/\($0)/") }) {
            let name = lane == "torrentio" ? "Torrentio" : "Comet"
            if url.path.hasSuffix("/manifest.json") {
                return json(["id": .string("orbital.demo.\(lane)"), "name": .string(name), "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]])
            }
            if lane == "torrentio", url.path.contains("/stream/") {
                try? await Task.sleep(for: .seconds(StreamFinder.perAddonWait + 2))   // ds-exception: demora de red simulada (solo modo demo)
                return json(["streams": []])
            }
            if url.absoluteString == multi {
                // El encabezado del MKV «Multi»: lo que lee «revisar por dentro».
                let audio: [(language: String, name: String?)] = mode == "found" ? [("eng", "English"), ("spa", "Español Latino")] : [("eng", "English"), ("fre", "Français")]
                let data = MatroskaTracks.sampleHeader(audio: audio)
                return HTTPResponse(status: 206, data: data, headers: ["content-range": "bytes 0-\(data.count - 1)/2000000000"])
            }
            if lane == "comet", url.path.contains("/stream/") {
                let rows: [(String, String, String)] = [
                    ("1080p", "📄 Dune.2021.1080p.WEB-DL.DDP5.1.Atmos.H.264-FLUX.mp4\n💾 8.1 GB 🔎 Real-Debrid", "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"),
                    ("1080p", "📄 Dune.2021.MULTi.1080p.BluRay.x264-AMIABLE.mkv\n💾 12.4 GB 🔎 Real-Debrid", multi),
                    ("720p", "📄 Dune.2021.720p.WEBRip.x264.AAC-YTS.mp4\n💾 1.3 GB 🔎 Real-Debrid", "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8?v=2"),
                ]
                return json(["streams": .array(rows.map { r in ["name": .string("[RD\u{26A1}] Comet \(r.0)"), "description": .string(r.1), "url": .string(r.2)] })])
            }
        }
        // Tu Torrentio sin Real-Debrid: lo que existe, también el latino.
        if url.host == "torrentio.strem.fun", url.path.hasSuffix("/stream/movie/\(id).json") {
            return json(["streams": [
                ["name": "Torrentio\n1080p", "title": "Dune (2021) 1080p BluRay Latino\n👤 15 💾 2.3 GB ⚙️ Cinecalidad\n🇲🇽", "infoHash": .string(latinoHash), "fileIdx": 0],
                ["name": "Torrentio\n1080p", "title": "Dune.2021.1080p.WEB-DL.DDP5.1.Atmos.H.264-FLUX\n👤 90 💾 8.1 GB ⚙️ TorrentGalaxy", "infoHash": "1111111111111111111111111111111111111111", "fileIdx": 0],
            ]])
        }
        return nil
    }
}
#endif
