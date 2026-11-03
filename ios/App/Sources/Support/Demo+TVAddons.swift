#if DEBUG
import Foundation
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// Tu lista y la de tu TV de mentira (Fase 4, S6), con la Orbital de la demostración (`tv.demo.invalid`):
///
/// - `-demo-tv-addons sync`: la misma lista que la TV, con «Archivos de la TV · Solo en la TV».
/// - `-demo-tv-addons unreachable`: la TV no contesta.
/// - `-demo-tv-addons conflict`: Torrentio cambió en los dos (gana la TV y avisa con «Usar la de este iPhone»), y el primer
///   envío llega tarde (409): se junta y se reintenta.
/// - `-demo-tv-addons keys`: uno traído de Stremio con clave se queda en este iPhone, y la TV contesta 422 «Espera las llaves
///   por aparato».
///
/// Abre Complementos con `-demo-settings-page addons`. Nada sale a una TV de verdad.
extension Demo {
    static var tvAddons: String? { value(after: "-demo-tv-addons") }

    @MainActor static func seedTVAddons(_ services: Services) {
        guard let mode = tvAddons else { return }
        let list = services.addonList
        list.startWithRecommended()
        if mode == "conflict" { var o = TorrentioConfig.recommended; o.sort = "size"; list.setOptions("torrentio", o) }
        if mode == "keys" {
            list.importOnce([.init(name: "ThePirateBay+", url: "https://thepiratebay-plus.demo.invalid/realdebrid=\(String(repeating: "DEMO", count: 13))/manifest.json",
                                   resources: ["stream"])])
        }
    }
}

/// La TV de mentira: revisión que solo sube, 409 si partiste de otra, 422 en `keys`.
final class DemoTVAddons: @unchecked Sendable {
    static let shared = DemoTVAddons()
    private let lock = NSLock()
    private var list: SharedAddonList
    private var conflictOnce = Demo.tvAddons == "conflict"

    private init() {
        var torrentio = TorrentioConfig.recommended
        if Demo.tvAddons == "conflict" { torrentio.sort = "seeders" }
        list = SharedAddonList(revision: 12, changedAt: Date().addingTimeInterval(-20 * 60), changedBy: "tv", addons: [
            SharedAddon(id: "torrentio", origin: "orbital", template: "torrentio", name: "Torrentio", enabled: ["tv": true], order: 0,
                        options: AddonShare.wire(torrentio)),
            SharedAddon(id: "opensubtitles", origin: "orbital", template: "opensubtitles", name: "OpenSubtitles", enabled: ["tv": true], order: 1),
            SharedAddon(id: "demo-local", origin: "stremio", url: "http://127.0.0.1:11470/local-addon/manifest.json", name: "Local Files",
                        enabled: ["tv": true], order: 2, onlyOn: "tv"),
        ])
    }

    func respond(_ request: HTTPRequest) async throws -> HTTPResponse? {
        guard request.url.host == "tv.demo.invalid", request.url.path == "/api/addons", let mode = Demo.tvAddons else { return nil }
        if mode == "unreachable" { throw URLError(.timedOut) }
        return try lock.withLock {
            if request.method == "GET" { return HTTPResponse(status: 200, data: try JSONEncoder().encode(list)) }
            if mode == "keys" {
                return HTTPResponse(status: 422, data: Data(#"{"detail": "Espera las llaves por aparato: esa dirección lleva una clave"}"#.utf8))
            }
            if conflictOnce { conflictOnce = false; list.revision += 1; return HTTPResponse(status: 409, data: try JSONEncoder().encode(list)) }
            guard case .object(let o) = try JSONDecoder().decode(StoredJSON.self, from: request.body ?? Data()), case .array(let items)? = o["addons"] else {
                return HTTPResponse(status: 422, data: Data())
            }
            for item in items {
                guard let data = try? JSONEncoder().encode(item), let got = SharedAddonList.parse(Data(#"{"revision":0,"addons":["#.utf8) + data + Data("]}".utf8))?.addons.first,
                      let i = list.addons.firstIndex(where: { $0.id == got.id }) else { continue }
                list.addons[i].enabled.merge(got.enabled.filter { $0.key != "tv" }) { _, new in new }
                if let options = got.options { list.addons[i].options = options }
            }
            list.revision += 1; list.changedAt = Date(); list.changedBy = "iPhone"
            return HTTPResponse(status: 200, data: try JSONEncoder().encode(list))
        }
    }
}
#endif
