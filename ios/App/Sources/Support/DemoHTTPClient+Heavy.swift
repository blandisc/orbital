import Foundation
import OrbitalCore

#if DEBUG
extension DemoHTTPClient {
    /// `-demo-heavy` (N5-A): como «Dune: Parte dos» del escenario 05: la inglesa al instante es un REMUX 4K de 64 GB que aquí
    /// no se ve bien; gana la castellana y la ficha dice por qué. nil sin la bandera.
    static func heavyStreams(keyless: Bool = false) -> HTTPResponse? {
        guard Demo.has("-demo-heavy") else { return nil }
        let video = "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"
        let streams: [JSON] = [
            ["name": "[RD+] Torrentio\n4k DV", "title": "Dune.Part.Two.2024.UHD.BluRay.2160p.TrueHD.Atmos.7.1.DV.HEVC.REMUX-FraMeSToR\n👤 317 💾 64.29 GB ⚙️ ThePirateBay",
             "url": .string(video + "?v=heavy")],
            ["name": "[RD+] Torrentio\n1080p", "title": "Dune Parte Dos (2024) [Bluray 1080p][Esp]\n👤 38 💾 9.62 GB ⚙️ MejorTorrent\n🇪🇸", "url": .string(video + "?v=es")],
            ["name": "[RD download] Torrentio\n1080p", "title": "Duna Parte Dos (2024) 1080p Latino\n👤 20 💾 3.1 GB ⚙️ Cinecalidad\n🇲🇽",
             "url": "https://demo.orbital.invalid/resolve/realdebrid/DEMO/9006fbf91001e7053c648dfe71836ffd2f2ca0f4/null/0/lat.mkv"],
        ]
        // Torrentio sin Real-Debrid (lo que existe, para pedir): las mismas, con su huella.
        let hashes = ["eee7f700c17bb89a63d0991ebb5f0b20de1b1d69", "eca99591be0c9d5961688422a1457671bb20b92f", "9006fbf91001e7053c648dfe71836ffd2f2ca0f4"]
        let out = keyless ? zip(streams, hashes).map { s, h -> JSON in
            var o = s.object ?? [:]; o["url"] = nil; o["infoHash"] = .string(h); o["fileIdx"] = 0
            o["name"] = .string((o["name"]?.string ?? "").replacingOccurrences(of: "[RD+] ", with: "").replacingOccurrences(of: "[RD download] ", with: ""))
            return .object(o)
        } : streams
        return HTTPResponse(status: 200, data: JSON.object(["streams": .array(out)]).serialized())
    }
}
#endif
