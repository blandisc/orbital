import Foundation
import OrbitalCore

#if DEBUG   // solo la demo: DemoHTTPClient no existe en la versión del iPhone

extension DemoHTTPClient {
    /// `-demo-rd-request …`: Real-Debrid todavía no tiene tu versión (latino, «por bajar») y otra en inglés sí arranca; con
    /// `none`, nadie lo tiene. Para ver «Pedir a la nube» y los estados del pedido. `-demo-rd-no-instant`: sin la de inglés
    /// (RX2-A: la hoja de lo que baja sin otra que ya arranque); `-demo-rd-instant-latino`: la que arranca es latina 720p (en
    /// tus idiomas: «Ver Latino · 720p, ya arranca»). nil: no aplica (`ready` o sin la bandera).
    static func requestStreams() -> HTTPResponse? {
        guard let rd = Demo.rdRequest, rd != "ready" else { return nil }
        guard rd != "none" else { return HTTPResponse(status: 200, data: JSON.object(["streams": []]).serialized()) }
        let arguments = ProcessInfo.processInfo.arguments
        let pending = "https://demo.orbital.invalid/resolve/realdebrid/DEMO/\(demoTorrent)/null/1/Demo.S02E06.1080p.LATINO.mkv"
        let instantTitle = arguments.contains("-demo-rd-instant-latino") ? "The.Office.S02E06.720p.WEB-DL.LATINO\n👤 40 💾 700 MB ⚙️ Cinecalidad\n🇲🇽"
                                                                          : "Demo.S02E06.720p.WEB-DL.ENG\n👤 40 💾 700 MB ⚙️ EZTV"
        let instant: [JSON] = arguments.contains("-demo-rd-no-instant") ? [] : [
            ["name": "[RD+] Torrentio\n720p", "title": .string(instantTitle),
             "url": "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8"]]
        return HTTPResponse(status: 200, data: JSON.object(["streams": .array([
            ["name": "[RD download] Torrentio\n1080p", "title": "Demo.S02E06.1080p.WEB-DL.LATINO\n👤 12 💾 1.2 GB ⚙️ Cinecalidad\n🇲🇽", "url": .string(pending)],
        ] + instant)]).serialized())
    }
}

#endif
