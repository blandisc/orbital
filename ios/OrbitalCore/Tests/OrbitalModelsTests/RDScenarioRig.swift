import Foundation
import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
@testable import OrbitalAddons

/// Un escenario común con la TV (`tests/fixtures/rd-scenarios/escenarios/*.json`): lo que entra (la ficha, lo que contestó
/// Torrentio sin Real-Debrid, lo que tiene tu Real-Debrid, la libreta de pedidos y tus idiomas) armado sobre la red falsa,
/// y lo que la app decide con el código de verdad, en la forma de `esperado`. Fernando, 3 nov: «análisis de fondo… para que
/// no encuentre yo más errores».
@MainActor
final class RDScenarioRig {
    static let folder = "rd-scenarios"
    static let key = String(repeating: "K", count: 52)
    static let torrentio = "https://a.example"
    static let kitsu = "https://k.example"

    let file: String
    let scenario: JSON
    let rig: ServicesRig
    var services: Services { rig.services }
    var http: FakeHTTP { rig.http }
    var kind: String { scenario["titulo"]?["tipo"]?.string ?? "movie" }
    var metaID: String { scenario["titulo"]?["meta_id"]?.string ?? "" }
    var videoID: String { scenario["titulo"]?["video_id"]?.string ?? metaID }

    static func all() throws -> [String] {
        let dir = Fixtures.root.appendingPathComponent("\(folder)/escenarios")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.sorted()
    }

    init(_ file: String) async throws {
        self.file = file
        scenario = try Fixtures.json("\(Self.folder)/escenarios/\(file)")
        let tmdb = scenario["titulo"]?["tmdb"]
        rig = try ServicesRig(tmdbKey: tmdb?.object != nil ? "K" : "")
        try await arm()
    }

    private func path(_ id: String) -> String { id.replacingOccurrences(of: ":", with: "%3A") }

    // MARK: lo que entra
    private func arm() async throws {
        let prefs = scenario["preferencias"]
        services.settings.update {
            $0.uiLanguage = "es"
            $0.audio = prefs?["audio"]?.string ?? "es"
            $0.quality = prefs?["calidad"]?.string ?? "1080p"
            $0.latinSpanish = prefs?["espanol"]?.string == "es-419"
            $0.castilianSpanish = prefs?["espanol"]?.string == "es-ES"
        }
        let debrid = scenario["real_debrid"]
        let account = debrid?["cuenta"]?["id"]?.string
        if debrid?["clave"]?.bool == true {
            rig.secrets.set(AddonKeys.realDebridToken, Self.key)
            http.json["https://api.real-debrid.com/rest/1.0/user"] = Self.user(debrid?["cuenta"])
            if let status = try? RealDebrid.parse(Self.user(debrid?["cuenta"]).serialized(), checkedAt: Date()) { services.debrid.rememberForDemo(status) }
        }
        // La ficha: Cinemeta (o el complemento de Kitsu) y TMDB.
        let meta = try Fixtures.json("\(Self.folder)/\(scenario["titulo"]?["cinemeta"]?.string ?? "")")
        var own = ["\(Self.torrentio)/manifest.json"]
        http.json["\(Self.torrentio)/manifest.json"] = ["name": "Torrentio", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt", "kitsu"]]
        if metaID.hasPrefix("kitsu:") {
            own.append("\(Self.kitsu)/manifest.json")
            http.json["\(Self.kitsu)/manifest.json"] = ["name": "Anime Kitsu", "resources": ["meta"], "types": ["series"], "idPrefixes": ["kitsu"]]
            http.json["\(Self.kitsu)/meta/series/\(metaID).json"] = ["meta": meta]
            if let imdb = meta["imdb_id"]?.string {
                http.json["https://v3-cinemeta.strem.io/meta/series/\(imdb).json"] = ["meta": try Fixtures.json("\(Self.folder)/cinemeta/\(imdb).json")]
            }
        } else {
            http.json["https://v3-cinemeta.strem.io/meta/\(kind)/\(metaID).json"] = ["meta": meta]
        }
        rig.secrets.set(SecretKey.ownAddons, own.joined(separator: "\n"))
        if let tmdb = scenario["titulo"]?["tmdb"], tmdb.object != nil { armTMDB(tmdb) }
        // Torrentio: con Real-Debrid (lo que ve la lista) y sin él (lo que existe, para pedir).
        let raw = try scenario["torrentio"]?["archivo"]?.string.map { try Fixtures.json("\(Self.folder)/\($0)") } ?? ["streams": []]
        let withDebrid = "\(Self.torrentio)/stream/\(kind)/\(path(videoID)).json"
        switch scenario["torrentio_estado"]?.string {
        case "sin_respuesta": http.statuses[withDebrid] = 503; http.json[withDebrid] = ["streams": []]
        case "rd_error": http.json[withDebrid] = ["streams": [["name": "[RD error] Torrentio", "title": "Invalid Real-Debrid API key or expired premium",
                                                                "url": "https://torrentio.strem.fun/videos/failed_access_v2.mp4"]]]
        default: http.json[withDebrid] = debrid?["clave"]?.bool == true ? Self.asWithDebrid(raw, scenario) : raw
        }
        if let base = services.debridRequests.keylessBase {
            http.json["\(base)/stream/\(kind)/\(path(videoID)).json"] = raw
        }
        // Tu cuenta de Real-Debrid: sus torrents (para ver lo pedido aunque Torrentio no lo liste).
        for torrent in debrid?["torrents"]?.array ?? [] {
            guard let id = torrent["id"]?.string else { continue }
            http.json["https://api.real-debrid.com/rest/1.0/torrents/info/\(id)"] = torrent
        }
        if let first = debrid?["torrents"]?.array?.first?["unrestrict"]?.object?.first?.value {
            http.json["https://api.real-debrid.com/rest/1.0/unrestrict/link"] = ["download": first]
        }
        // La libreta de pedidos (como la junta la TV: el formato del contrato).
        let book = services.debridRequests.requester.book
        if let rows = scenario["libreta"]?.array, !rows.isEmpty {
            for entry in DebridRequestBook.decodeEach(JSON.array(rows).serialized()) {
                var e = entry
                e.pending = false; e.notified = true; e.nudged = true
                e.updatedAt = rig.clock.now; e.progressAt = rig.clock.now; e.createdAt = rig.clock.now.addingTimeInterval(-3600)
                book.put(e)
            }
        }
        _ = await services.debridRequests.requester.refresh()   // sabe cuál es tu cuenta
        services.debridRequests.reload()
        if let account { XCTAssertEqual(services.debridRequests.requester.knownAccount, account, "\(file): la cuenta de este aparato") }
        // Una serie: vas en el episodio del escenario (lo tuyo en Stremio), así la ficha y «Versión» son de ese video.
        if kind == "series" {
            let video = videoID
            _ = services.library.update(metaID, make: { LibraryEntry(metaID: metaID, kind: "series", name: meta["name"]?.string ?? "") }) { $0.videoID = video }
        }
        // Tu plan B de idiomas (T2): los «Idiomas primero» de Torrentio. `Services` lo lee de tu Torrentio instalado; aquí se pone a mano.
        let fallback = TorrentioConfig.fallbackCodes(AddonOptions(languages: (scenario["torrentio_opciones"]?["idiomas_primero"]?.array ?? []).compactMap(\.string)))
        if !fallback.isEmpty {
            let tmdbKey = tmdb?.object != nil ? "K" : ""
            let origins = OriginBook(tmdb: { [http] in Tmdb(http: http, key: tmdbKey) }, cinemeta: services.cinemeta)
            await services.finder.configure(origin: { kind, metaID in await origins.origin(kind: kind, metaID: metaID) }, checked: { _ in nil }, fallback: { fallback })
        }
        try await Task.sleep(nanoseconds: 50_000_000)   // `Services` configura la búsqueda en una tarea
    }

    private var tmdb: JSON? { scenario["titulo"]?["tmdb"] }

    /// TMDB por la red falsa: `find` (el idioma original y sus nombres), la ficha en es-MX y sus traducciones.
    private func armTMDB(_ t: JSON) {
        let id = 9000 + abs(metaID.hashValue % 999)
        let api = Tmdb.api
        let section = kind == "movie" ? "movie" : "tv"
        let titleKey = kind == "movie" ? "title" : "name", originalKey = kind == "movie" ? "original_title" : "original_name"
        http.prefix["\(api)/find/\(metaID)?"] = ["\(section)_results": [["id": .int(id), titleKey: t["title_es_MX"] ?? "", originalKey: t["original_title"] ?? "",
                                                                         "original_language": t["original_language"] ?? ""]]]
        http.prefix["\(api)/\(section)/\(id)?language=es-MX"] = [titleKey: t["title_es_MX"] ?? "", originalKey: t["original_title"] ?? "",
                                                                 "original_language": t["original_language"] ?? "", "overview": t["overview_es_MX"] ?? ""]
        let translations: [JSON] = (t["translations"]?.array ?? []).map { tr in
            ["iso_639_1": tr["iso_639_1"] ?? "", "iso_3166_1": tr["iso_3166_1"] ?? "", "data": [titleKey: tr["title"] ?? "", "overview": tr["overview"] ?? ""]]
        }
        http.prefix["\(api)/\(section)/\(id)/translations?"] = ["translations": .array(translations)]
    }

    static func user(_ account: JSON?) -> JSON {
        let id = account?["id"]?.string ?? "A"
        switch account?["estado"]?.string {
        case "vencida": return ["id": .string(id), "username": "fer", "type": "free", "premium": 0, "expiration": "2026-10-01T00:00:00.000Z"]
        case "gratis": return ["id": .string(id), "username": "fer", "type": "free", "premium": 0]
        default: return ["id": .string(id), "username": "fer", "type": "premium", "premium": 9_000_000, "expiration": "2027-06-01T00:00:00.000Z"]
        }
    }

    /// Lo que Torrentio da con tu Real-Debrid, a partir de lo capturado sin él: «[RD+]» lo que tu Real-Debrid tiene
    /// (`al_instante`), «[RD download]» lo demás, con su dirección `/resolve/realdebrid/<clave>/<huella>/null/<archivo>/<nombre>`.
    /// Con «solo lo que ya está» (`solo_al_instante`), solo las «[RD+]». La misma regla en la TV (README).
    static func asWithDebrid(_ raw: JSON, _ scenario: JSON) -> JSON {
        let cached = Set((scenario["real_debrid"]?["al_instante"]?.array ?? []).compactMap(\.string))
        let onlyCached = scenario["torrentio_opciones"]?["solo_al_instante"]?.bool == true
        let streams: [JSON] = (raw["streams"]?.array ?? []).compactMap { s in
            guard var o = s.object, let hash = s["infoHash"]?.string else { return nil }
            if onlyCached && !cached.contains(hash) { return nil }
            let quality = (s["name"]?.string ?? "").components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            o["name"] = .string("\(cached.contains(hash) ? "[RD+]" : "[RD download]") Torrentio" + (quality.isEmpty ? "" : "\n\(quality)"))
            let file = s["behaviorHints"]?["filename"]?.string ?? "video.mkv"
            let idx = s["fileIdx"]?.intValue.map(String.init) ?? "undefined"
            o["url"] = .string("https://torrentio.strem.fun/resolve/realdebrid/\(key)/\(hash)/null/\(idx)/\(file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "x.mkv")")
            o["infoHash"] = nil; o["fileIdx"] = nil
            return .object(o)
        }
        return ["streams": .array(streams)]
    }

    // MARK: lo que sale
    struct Observed {
        var title: TitleModel
        var list: SourcesModel
        var json: JSON
    }

    /// Lo que decide la app, en la forma de `esperado`.
    func observe() async -> Observed {
        let title = TitleModel(services, kind: kind, metaID: metaID)
        await title.load()
        await title.loadBestSource()
        let video = title.continueVideoID ?? videoID
        let list = SourcesModel(services, kind: kind, metaID: metaID, videoID: video)
        await list.load()
        let prefs = list.prefs
        func id(_ s: Source?) -> JSON {
            guard let s else { return .null }
            return ["hash": s.torrent.map { .string($0.hash) } ?? .null, "archivo": s.torrent?.fileIdx.map { .int($0) } ?? .null]
        }
        func hash(_ index: Int) -> JSON { list.source(index)?.torrent.map { .string($0.hash) } ?? .string("#\(index)") }
        func speed(_ o: VersionOption) -> String {
            o.requested ? "al_instante_la_pediste" : o.speed == .inRealDebrid ? "al_instante" : o.speed == .realDebridMustDownload ? "por_pedir" : "directa"
        }
        var out: [String: JSON] = [:]
        out["titulo"] = .string(title.title)
        out["logo"] = .bool(title.logo != nil)
        out["video"] = .string(video)
        let primary = title.primary()
        out["boton"] = .string(Self.name(primary))
        if primary == .watch, let s = title.recommendedSource {
            out["boton_version"] = .string(([title.recommendedLanguage ?? ""] + s.qualitySummary).filter { !$0.isEmpty }.joined(separator: " · "))
        }
        if case .request = primary { out["boton_version"] = .string(title.otherAccountRequest != nil ? "La TV lo está pidiendo con otra cuenta" : "Real-Debrid todavía no lo tiene") }
        out["pedir"] = title.debridOffer.map { ["hash": .string($0.torrent.hash), "idioma": $0.language.map(JSON.string) ?? .null] } ?? .null
        out["causa"] = title.unavailableCause.map { .string(Self.name($0)) } ?? .null
        out["al_instante_aparte"] = title.debridOffer?.instantSource.map { s in
            ["hash": s.torrent.map { .string($0.hash) } ?? .null, "idioma": title.debridOffer?.instantLanguage.map(JSON.string) ?? .null]
        } ?? .null
        out["recomendada"] = id(title.recommendedSource)
        out["recomendada_idioma"] = title.recommendedLanguage.map(JSON.string) ?? .null
        out["filas"] = .array(list.languageRows.map { row in
            ["idioma": .string(row.code), "opciones": .array(row.options.map { o in
                ["calidad": .string(o.quality), "hash": hash(o.id), "velocidad": .string(speed(o)), "recomendada": .bool(o.recommended), "otro_titulo": .bool(o.otherTitle)]
            })]
        })
        out["mas_idiomas"] = .array(list.moreLanguages.map { .string($0.code) })
        out["hay_que_pedirlas"] = .array(list.toRequest.map { ["idioma": .string($0.code), "calidad": .string($0.option.quality), "hash": hash($0.id)] })
        out["escondidas"] = .int(list.hiddenCount)
        // «Ver ahora» del aviso de listo: el reproductor sin versión elegida.
        let found = list.ranked
        let resume = services.titlePrefs.resumeChoice(metaID: metaID, videoID: video)?.source
        let family = services.titlePrefs.lastChoice(metaID: metaID)?.binge
        out["ver_ahora"] = id(SourcesModel.toPlay(found, resume: resume, family: family))
        _ = prefs
        return Observed(title: title, list: list, json: .object(out))
    }

    static func name(_ p: TitlePrimary?) -> String {
        switch p {
        case .watch?: "ver"
        case .request?: "pedirlo_y_avisarme"
        case .requested?: "pedido_en_camino"
        case .otherVersion?: "probar_otra_version"
        case .notifyWhenAppears?: "avisarme_cuando_aparezca"
        case .airs?: "sale_el"
        case .unavailable?: "sin_version"
        case nil: "cargando"
        }
    }

    static func name(_ c: UnavailableCause) -> String {
        switch c {
        case .downloading: "bajando"
        case .unreleased: "aun_no_se_estrena"
        case .cannotSearch: "no_puedo_buscar"
        case .debridExpired: "real_debrid_vencio"
        case .noPremium: "sin_premium"
        case .reconnectDebrid: "vuelve_a_conectar"
        case .debridRefused: "real_debrid_no_lo_dejo"
        case .addonsOffline: "complementos_no_contestan"
        case .noAddonsOn: "sin_complementos"
        case .notInDebrid: "real_debrid_no_lo_tiene"
        case .nobodyHasIt: "nadie_lo_tiene"
        }
    }
}
