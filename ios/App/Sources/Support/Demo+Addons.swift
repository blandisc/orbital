#if DEBUG
import Foundation
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// Complementos y Torrentio de mentira (Fase 3), para ver en el simulador las páginas nuevas sin cuentas de verdad:
///
/// - `-demo-addons health`: la lista con cómo le va a cada uno (Torrentio y OpenSubtitles contestan, Jackett lento,
///   ThePirateBay+ no contesta desde el sábado y se salta).
/// - `-demo-addons two-torrentio`: un Torrentio traído de Stremio y el de Orbital ya cambiado: se pregunta con cuál quedarse (C5).
/// - `-demo-torrentio empty`: tus filtros dejarían 0 versiones (T9), para ver el aviso y su arreglo.
/// - `-demo-settings-page torrentio|addons|realdebrid`: abre esa página de Ajustes.
/// - `-demo-rd-points N`: tus puntos de Real-Debrid (D4); canjear contesta la demo, nada sale a Real-Debrid.
///
/// Con `-demo-rd premium`. Torrentio lo contesta la demo (nunca sale a internet con la clave de mentira).
extension Demo {
    static var addons: String? { value(after: "-demo-addons") }
    static var torrentio: String? { value(after: "-demo-torrentio") }
    static var rdPoints: Int { value(after: "-demo-rd-points").flatMap(Int.init) ?? 1200 }

    @MainActor static func seedAddons(_ services: Services) {
        guard addons != nil || torrentio != nil else { return }
        let list = services.addonList
        list.startWithRecommended()
        if addons == "health" {
            list.importOnce([.init(name: "ThePirateBay+", url: "https://thepiratebay-plus.demo.invalid/manifest.json", resources: ["stream"]),
                             .init(name: "Jackett", url: "https://jackett.demo.invalid/manifest.json", resources: ["stream"])])
            let health = services.addonHealth
            for addon in list.installed {
                guard let url = list.resolvedURL(addon) else { continue }
                switch addon.name {
                case "Torrentio", "OpenSubtitles": health.ok(url, seconds: 0.62)
                case "Jackett": health.ok(url, seconds: 4.2)
                case "ThePirateBay+":
                    let saturday = Calendar.current.nextDate(after: Date(), matching: DateComponents(weekday: 7), matchingPolicy: .nextTime, direction: .backward) ?? Date()
                    health.fail(url, at: saturday); health.fail(url, at: saturday)
                default: break
                }
            }
        }
        if addons == "two-torrentio" {
            list.setOptions("torrentio", AddonOptions(languages: ["latino"]))
            list.importOnce([.init(name: "Torrentio RD", url: "https://torrentio.strem.fun/sort=seeders|language=latino|qualityfilter=brremux,cam,scr|realdebrid=\(String(repeating: "OLD0", count: 13))/manifest.json",
                                   resources: ["stream"])])
        }
        if torrentio == "empty" {
            var options = AddonOptions()
            options.excludedQualities = ["4k", "1080p", "720p", "cam"]
            options.debridOptions = ["nodownloadlinks"]
            list.setOptions("torrentio", options)
        }
    }

    /// Torrentio de mentira: unas versiones de The Office que respetan las calidades que escondes, «solo lo que ya está» y
    /// el límite por calidad, como el de verdad.
    static func torrentioDemo(_ url: URL) -> HTTPResponse? {
        guard url.host == "torrentio.strem.fun", rdRequest == nil else { return nil }
        if url.path.hasSuffix("manifest.json") {
            let manifest: JSON = ["id": "com.stremio.torrentio.addon", "name": "Torrentio", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
            return HTTPResponse(status: 200, data: manifest.serialized())
        }
        guard let range = url.path.range(of: "/stream/") else { return HTTPResponse(status: 404, data: Data()) }
        var options: [String: String] = [:]
        for part in url.path[..<range.lowerBound].split(separator: "|") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { options[pair[0].trimmingCharacters(in: CharacterSet(charactersIn: "/"))] = pair[1] }
        }
        let hidden = Set((options["qualityfilter"] ?? "").split(separator: ",").map(String.init))
        let onlyInstant = (options["debridoptions"] ?? "").contains("nodownloadlinks")
        let keyed = options["realdebrid"] != nil
        let rows: [(String, Bool, String, String)] = [
            ("1080p", true, "The.Office.US.S01E01.1080p.WEB-DL.LATINO", "1.1 GB"), ("720p", false, "The.Office.US.S01E01.720p.WEB-DL.LATINO", "620 MB"),
            ("4k", false, "The.Office.US.S01E01.2160p.WEB-DL.DV.HDR.ENG", "4.2 GB"), ("1080p", false, "The.Office.US.S01E01.1080p.BluRay.ENG", "1.9 GB"),
            ("720p", false, "The.Office.US.S01E01.720p.HDTV.ESP", "540 MB"),
        ]
        var perQuality: [String: Int] = [:]
        let limit = options["limit"].flatMap(Int.init)
        let streams: [JSON] = rows.compactMap { quality, cached, release, size in
            guard !hidden.contains(quality), !(onlyInstant && !cached) else { return nil }
            perQuality[quality, default: 0] += 1
            if let limit, perQuality[quality, default: 0] > limit { return nil }
            let mark = keyed ? (cached ? "[RD+] " : "[RD download] ") : ""
            return ["name": .string("\(mark)Torrentio\n\(quality)"), "title": .string("\(release)\n👤 20 💾 \(size)"),
                    "url": .string("https://demo.orbital.invalid/\(release).mkv")]
        }
        return HTTPResponse(status: 200, data: JSON.object(["streams": .array(streams)]).serialized())
    }
}
#endif

#if DEBUG
import SwiftUI

/// La página de Ajustes que abre `-demo-settings-page` (Fase 3).
struct DemoSettingsPage: View {
    let name: String
    let debrid: DebridModel

    var body: some View {
        switch name {
        case "torrentio": TorrentioSettings()
        case "realdebrid": DebridAccountView(debrid: debrid)
        default: AddonsSettings()
        }
    }
}
#endif
