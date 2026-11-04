import Foundation
import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
@testable import OrbitalAddons

/// Un escenario común con la TV (`tests/fixtures/rd-scenarios/escenarios/*.json`, forma v2 acordada con la TV el 3 nov):
/// lo que entra (`now`, `app`, `title`, `tmdb`, `cinemeta`, `torrentio`, `addons`, `rd`, `act`) armado sobre la red falsa,
/// y lo que la app decide con el código de verdad, en la forma de `expected`. Fernando, 3 nov: «análisis de fondo… para que
/// no encuentre yo más errores».
@MainActor
final class RDScenarioRig {
    static let folder = "rd-scenarios"
    /// La clave de Real-Debrid de las pruebas (en la dirección de Torrentio con Real-Debrid: `/resolve/realdebrid/KEY/…`).
    static let key = String(repeating: "K", count: 52)
    static let torrentio = "https://a.example"
    static let kitsu = "https://k.example"
    static let opensubtitles = "https://o.example"
    static let api = "https://api.real-debrid.com/rest/1.0"

    let file: String
    let scenario: JSON
    let rig: ServicesRig
    var services: Services { rig.services }
    var http: FakeHTTP { rig.http }
    var kind: String { scenario["title"]?["kind"]?.string ?? "movie" }
    var metaID: String { scenario["title"]?["id"]?.string ?? "" }
    var videoID: String { scenario["title"]?["video_id"]?.string ?? metaID }
    var rd: JSON? { scenario["rd"] }
    var hasKey: Bool { rd?["key"]?.bool == true }
    /// `now` del escenario: el reloj de la app.
    var now: Date { rig.clock.now }

    static func all() throws -> [String] {
        let dir = Fixtures.root.appendingPathComponent("\(folder)/escenarios")
        return try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }.sorted()
    }

    init(_ file: String) async throws {
        self.file = file
        scenario = try Fixtures.json("\(Self.folder)/escenarios/\(file)")
        rig = try ServicesRig(tmdbKey: scenario["tmdb"]?.object != nil ? "K" : "")
        if let text = scenario["now"]?.string, let date = ISO8601DateFormatter().date(from: text) { rig.clock.now = date }
        try await arm()
    }

    /// El video de `torrentio.next` (de su dirección: `…/stream/series/<video>.json`).
    var nextVideoID: String? {
        scenario["torrentio"]?["next"]?["url"]?.string.flatMap { URL(string: $0)?.deletingPathExtension().lastPathComponent }
    }

    private func path(_ id: String) -> String { id.replacingOccurrences(of: ":", with: "%3A") }

    // MARK: lo que entra
    private func arm() async throws {
        let app = scenario["app"]
        services.settings.update {
            $0.uiLanguage = String((app?["language"]?.string ?? "es").prefix(2))
            $0.audio = app?["audio"]?.string ?? "es"
            $0.quality = app?["quality"]?.string ?? "1080p"
            $0.latinSpanish = app?["spanish"]?.string == "es-419"
            $0.castilianSpanish = app?["spanish"]?.string == "es-ES"
        }
        let account = rd?["account"]?["id"]?.string
        if hasKey {
            rig.secrets.set(AddonKeys.realDebridToken, Self.key)
            let (status, user) = Self.user(rd?["account"], now: now)
            http.json["\(Self.api)/user"] = user
            if status != 200 { http.statuses["\(Self.api)/user"] = status }
            if status == 200, let saved = try? RealDebrid.parse(user.serialized(), checkedAt: now) { services.debrid.rememberForDemo(saved) }
        }
        // La ficha: Cinemeta (y el complemento de Kitsu si el id es de Kitsu) y TMDB.
        let addons = Set((scenario["addons"]?.array ?? ["torrentio"]).compactMap(\.string))
        var own: [String] = []
        if addons.contains("torrentio") {
            own.append("\(Self.torrentio)/manifest.json")
            http.json["\(Self.torrentio)/manifest.json"] = ["name": "Torrentio", "resources": ["stream"], "types": ["movie", "series"], "idPrefixes": ["tt", "kitsu"]]
        }
        if addons.contains("opensubtitles") {
            own.append("\(Self.opensubtitles)/manifest.json")
            http.json["\(Self.opensubtitles)/manifest.json"] = ["name": "OpenSubtitles v3", "resources": ["subtitles"], "types": ["movie", "series"], "idPrefixes": ["tt"]]
        }
        let meta = try Fixtures.json("\(Self.folder)/\(scenario["cinemeta"]?.string ?? "")")
        if let kitsuFile = scenario["kitsu"]?.string {
            own.append("\(Self.kitsu)/manifest.json")
            http.json["\(Self.kitsu)/manifest.json"] = ["name": "Anime Kitsu", "resources": ["meta"], "types": ["series"], "idPrefixes": ["kitsu"]]
            http.json["\(Self.kitsu)/meta/series/\(metaID).json"] = ["meta": try Fixtures.json("\(Self.folder)/\(kitsuFile)")]
            if let imdb = meta["imdb_id"]?.string ?? meta["id"]?.string { http.json["https://v3-cinemeta.strem.io/meta/series/\(imdb).json"] = ["meta": meta] }
        } else {
            http.json["https://v3-cinemeta.strem.io/meta/\(kind)/\(metaID).json"] = ["meta": meta]
        }
        rig.secrets.set(SecretKey.ownAddons, own.joined(separator: "\n"))
        // Sin Torrentio: tu lista de Ajustes › Complementos armada solo con lo que hay (OpenSubtitles da subtítulos, no versiones).
        if !addons.contains("torrentio") {
            for url in own { _ = services.addonList.add(url: url, name: url.contains("o.example") ? "OpenSubtitles v3" : "Anime Kitsu",
                                                        resources: url.contains("o.example") ? ["subtitles"] : ["meta"]) }
        }
        if let tmdb = scenario["tmdb"], tmdb.object != nil { armTMDB(tmdb) }
        // Torrentio: con Real-Debrid (lo que ve la lista) y sin él (lo que existe, para pedir).
        let torrentio = scenario["torrentio"]
        let raw = try torrentio?["file"]?.string.map { try Fixtures.json("\(Self.folder)/\($0)") } ?? ["streams": []]
        let withDebrid = "\(Self.torrentio)/stream/\(kind)/\(path(videoID)).json"
        switch torrentio?["status"]?.string {
        case "down": http.statuses[withDebrid] = 503; http.json[withDebrid] = ["streams": []]
        case "rd_error": http.json[withDebrid] = ["streams": [["name": "[RD error] Torrentio", "title": "Invalid Real-Debrid API key or expired premium",
                                                                "url": "https://torrentio.strem.fun/videos/failed_access_v2.mp4"]]]
        default: http.json[withDebrid] = hasKey ? Self.asWithDebrid(raw, scenario) : raw
        }
        if let base = services.debridRequests.keylessBase {
            http.json["\(base)/stream/\(kind)/\(path(videoID)).json"] = raw
        }
        // El siguiente episodio (`torrentio.next`), igual: para saber si un pedido tuyo ya lo trae.
        if let next = torrentio?["next"], let file = next["file"]?.string, let id = nextVideoID {
            let rawNext = try Fixtures.json("\(Self.folder)/\(file)")
            http.json["\(Self.torrentio)/stream/\(kind)/\(path(id)).json"] = hasKey ? Self.asWithDebrid(rawNext, scenario) : rawNext
            if let base = services.debridRequests.keylessBase { http.json["\(base)/stream/\(kind)/\(path(id)).json"] = rawNext }
        }
        // Tu cuenta de Real-Debrid: sus torrents (`GET /torrents` y `/torrents/info/<id>`) y lo que contesta al pedir.
        let torrents = rd?["torrents"]?.array ?? []
        http.json["\(Self.api)/torrents?limit=100"] = .array(torrents.map(Self.rdTorrent))
        for torrent in torrents {
            guard let id = torrent["id"]?.string else { continue }
            http.json["\(Self.api)/torrents/info/\(id)"] = Self.rdTorrent(torrent)
        }
        if let first = torrents.first?["unrestrict"]?.object?.first?.value {
            http.json["\(Self.api)/unrestrict/link"] = ["download": first]
        }
        if let error = rd?["error"], error.object != nil {
            http.json["\(Self.api)/torrents/addMagnet"] = ["error": error["name"] ?? "error", "error_code": error["code"] ?? .null]
            http.statuses["\(Self.api)/torrents/addMagnet"] = error["http"]?.intValue ?? 400
        } else {
            http.json["\(Self.api)/torrents/addMagnet"] = ["id": "RNEW", "uri": "https://api.real-debrid.com/rest/1.0/torrents/info/RNEW"]
        }
        // La libreta de pedidos (como la junta la TV: el formato del contrato, con sus horas).
        let book = services.debridRequests.requester.book
        if let rows = rd?["book"]?.array, !rows.isEmpty {
            for entry in DebridRequestBook.decodeEach(JSON.array(rows).serialized()) {
                var e = entry
                e.pending = false; e.notified = true; e.nudged = true
                book.put(e)
            }
        }
        _ = await services.debridRequests.requester.refresh()   // sabe cuál es tu cuenta (y cuánto lleva lo tuyo)
        services.debridRequests.reload()
        if let account, hasKey, rd?["account"]?["problem"]?.string != "bad_key" {
            XCTAssertEqual(services.debridRequests.requester.knownAccount, account, "\(file): la cuenta de este aparato")
        }
        // Una serie: vas en el episodio del escenario (lo tuyo en Stremio), así la ficha y «Versión» son de ese video.
        if kind == "series" {
            let video = videoID
            _ = services.library.update(metaID, make: { LibraryEntry(metaID: metaID, kind: "series", name: meta["name"]?.string ?? "") }) { $0.videoID = video }
        }
        // Tu plan B de idiomas (T2): los «Idiomas primero» de Torrentio. `Services` lo lee de tu Torrentio instalado; aquí se pone a mano.
        let fallback = TorrentioConfig.fallbackCodes(AddonOptions(languages: (torrentio?["options"]?["languages_first"]?.array ?? []).compactMap(\.string)))
        if !fallback.isEmpty {
            let tmdbKey = scenario["tmdb"]?.object != nil ? "K" : ""
            let origins = OriginBook(tmdb: { [http] in Tmdb(http: http, key: tmdbKey) }, cinemeta: services.cinemeta)
            await services.finder.configure(origin: { kind, metaID in await origins.origin(kind: kind, metaID: metaID) }, checked: { _ in nil }, fallback: { fallback })
        }
        try await Task.sleep(nanoseconds: 50_000_000)   // `Services` configura la búsqueda en una tarea
    }

    /// TMDB por la red falsa, tal cual lo trae el escenario: `find`, `detail` (en es-MX) y `translations`.
    private func armTMDB(_ t: JSON) {
        let section = kind == "movie" ? "movie" : "tv"
        let results = t["find"]?["\(section)_results"]?.array ?? []
        let id = results.first?["id"]?.intValue ?? t["detail"]?["id"]?.intValue ?? 0
        http.prefix["\(Tmdb.api)/find/\(metaID)?"] = t["find"] ?? [:]
        http.prefix["\(Tmdb.api)/\(section)/\(id)?language=es-MX"] = t["detail"] ?? [:]
        http.prefix["\(Tmdb.api)/\(section)/\(id)/translations?"] = ["translations": t["translations"] ?? []]
        if let season = t["season"], season.object != nil, let number = season["season_number"]?.intValue {
            http.prefix["\(Tmdb.api)/tv/\(id)/season/\(number)?"] = season
        }
    }

    /// `GET /user` según `rd.account`: Premium al día, vencida (`expired`), gratis (`no_premium`) o la clave vieja (`bad_key`, 401).
    static func user(_ account: JSON?, now: Date) -> (Int, JSON) {
        let id = account?["id"]?.string ?? "A"
        switch account?["problem"]?.string {
        case "bad_key"?: return (401, ["error": "bad_token", "error_code": 8])
        case "expired"?: return (200, ["id": .string(id), "username": "fer", "type": "free", "premium": 0, "expiration": account?["expires"] ?? "2026-10-01T00:00:00.000Z"])
        case "no_premium"?: return (200, ["id": .string(id), "username": "fer", "type": "free", "premium": 0])
        default:
            let expires = account?["expires"]?.string.flatMap { ISO8601DateFormatter().date(from: $0) } ?? now.addingTimeInterval(200 * 86400)
            return (200, ["id": .string(id), "username": "fer", "type": "premium", "premium": .int(Int(expires.timeIntervalSince(now))),
                          "expiration": account?["expires"] ?? "2027-06-01T00:00:00.000Z"])
        }
    }

    /// Un torrent de `rd.torrents` como lo da Real-Debrid (sin `unrestrict`, que es de las pruebas).
    static func rdTorrent(_ t: JSON) -> JSON {
        var o = t.object ?? [:]
        o["unrestrict"] = nil
        o["filename"] = o["filename"] ?? o["files"]?.array?.first?["path"] ?? "video.mkv"
        o["links"] = o["links"] ?? []
        o["seeders"] = o["seeders"] ?? .int(o["status"]?.string == "downloading" ? 3 : 0)
        return .object(o)
    }

    /// Lo que Torrentio da con tu Real-Debrid, a partir de lo capturado sin él: «[RD+]» lo que tu Real-Debrid tiene
    /// (`rd.instant`), «[RD download]» lo demás, con su dirección `/resolve/realdebrid/<clave>/<huella>/null/<archivo>/<nombre>`.
    /// Con «solo lo que ya está» (`torrentio.options.only_instant`), solo las «[RD+]». La misma regla en la TV (README).
    static func asWithDebrid(_ raw: JSON, _ scenario: JSON) -> JSON {
        let cached = Set((scenario["rd"]?["instant"]?.array ?? []).compactMap(\.string))
        let onlyCached = scenario["torrentio"]?["options"]?["only_instant"]?.bool == true
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

    /// `act: "request"`: tocas el botón principal («Pedirlo y avisarme») una vez antes de mirar.
    func act() async {
        guard scenario["act"]?.string == "request" else { return }
        let title = TitleModel(services, kind: kind, metaID: metaID)
        await title.load()
        await title.loadBestSource()
        XCTAssertEqual(title.primary(now: now), .request, "\(file): «act: request» sin «Pedirlo y avisarme»")
        _ = await title.requestFromDebrid()
    }

    /// Lo que decide la app, en la forma de `expected` (llaves neutras; README).
    func observe() async -> Observed {
        await act()
        let title = TitleModel(services, kind: kind, metaID: metaID)
        await title.load()
        await title.loadBestSource()
        let video = title.continueVideoID ?? videoID
        let list = SourcesModel(services, kind: kind, metaID: metaID, videoID: video)
        await list.load()
        func card(_ id: Int) -> VersionOption? { (list.languageRows + list.moreLanguages).flatMap(\.options).first { $0.id == id } }
        func res(_ s: Source) -> JSON { .string(card(s.index)?.quality ?? SourcesModel.quality(s)) }
        func hash(_ index: Int) -> JSON { list.source(index)?.torrent.map { .string($0.hash) } ?? .string("#\(index)") }
        func state(_ o: VersionOption) -> String {
            o.refused ? "refused" : o.requested ? "requested_ready" : o.speed == .inRealDebrid ? "instant" : o.speed == .realDebridMustDownload ? "to_request" : "direct"
        }
        var out: [String: JSON] = [:]
        out["title"] = .string(title.title)
        out["logo"] = .bool(title.logo != nil)
        out["video_id"] = .string(video)
        let primary = title.primary(now: now)
        out["primary"] = .string(Self.name(primary))
        // La causa que se ve: la del modelo; con «Pedirlo y avisarme», su renglón (causa 10, «Real-Debrid todavía no lo tiene»).
        var cause = title.unavailableCause
        if case .request? = primary { cause = .notInDebrid(language: title.debridOffer?.language ?? "") }
        if case .requested? = primary { cause = nil }
        if case .otherVersion(let request)? = primary { cause = request.state == .refused ? .debridRefused : nil }
        out["cause"] = cause.map { .string(Self.name($0)) } ?? .null
        out["cause_arg"] = cause.flatMap(Self.argument) ?? .null
        out["fix"] = Self.fix(primary, cause: title.unavailableCause).map(JSON.string) ?? .null
        let source = { (hash: String) in list.ranked.first { $0.torrent?.hash == hash } }
        out["offer"] = title.debridOffer.map { o in
            ["hash": .string(o.torrent.hash), "language": o.language.map(JSON.string) ?? .null, "res": source(o.torrent.hash).map(res) ?? .null]
        } ?? .null
        // FQ1-A: «Pedir a la nube en latino» al lado de «Ver».
        out["request_aside"] = title.wantedOffer.map { o in
            ["hash": .string(o.torrent.hash), "language": o.language.map(JSON.string) ?? .null, "res": source(o.torrent.hash).map(res) ?? .null]
        } ?? .null
        out["instant_aside"] = title.debridOffer?.instantSource.map { s in
            ["hash": s.torrent.map { .string($0.hash) } ?? .null, "language": title.debridOffer?.instantLanguage.map(JSON.string) ?? .null, "res": res(s)]
        } ?? .null
        out["recommended"] = title.recommendedSource.map { s in
            ["hash": s.torrent.map { .string($0.hash) } ?? .null, "language": title.recommendedLanguage.map(JSON.string) ?? .null, "res": res(s),
             "file": s.torrent?.fileIdx.map { .int($0) } ?? .null]
        } ?? .null
        out["rows"] = .array(list.languageRows.flatMap { row in
            row.options.map { o -> JSON in
                ["code": .string(row.code), "res": .string(o.quality), "hash": hash(o.id), "state": .string(state(o)), "recommended": .bool(o.recommended),
                 "other": .bool(o.otherTitle)]
            }
        })
        out["more_languages"] = .array(list.moreLanguages.map { .string($0.code) })
        out["to_request"] = .array(list.toRequest.map { ["code": .string($0.code), "res": .string($0.option.quality), "hash": hash($0.id)] })
        out["hidden"] = .int(list.hiddenCount)
        // «Ver ahora» del aviso de listo: el reproductor sin versión elegida.
        let found = list.ranked
        let resume = services.titlePrefs.resumeChoice(metaID: metaID, videoID: video)?.source
        let family = services.titlePrefs.lastChoice(metaID: metaID)?.binge
        out["play_now"] = SourcesModel.toPlay(found, resume: resume, family: family).map { s in
            s.addon == "Real-Debrid" ? "ready_source" : s.torrent.map { .string($0.hash) } ?? .string(s.playbackURL?.absoluteString ?? "?")
        } ?? .null
        // El pedido de este video: el tuyo (estado del contrato y si lleva 24 h sin avanzar) o el de otra cuenta.
        out["request"] = title.debridRequest.map { r in
            ["hash": .string(r.hash), "state": .string(r.state.rawValue), "percent": .int(r.percent), "stuck": .bool(r.isStalled(now: now))]
        } ?? .null
        out["other_account"] = (title.otherAccountRequest ?? title.otherAccountReady).map { ["state": .string($0.state.rawValue)] } ?? .null
        // FQ4-A: «Avisarme cuando aparezca» revisa hasta el estreno más 14 días (o 14 desde hoy).
        if case .notifyWhenAppears? = primary {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            out["notify_until"] = .string(f.string(from: AppearWatch.until(since: now, releases: title.upcomingRelease)))
        }
        // Tu orden de idiomas (`app.languages`): el que quieres y lo que sigue.
        if let languages = scenario["app"]?["languages"]?.array?.compactMap(\.string) {
            XCTAssertEqual([list.prefs.wanted] + list.prefs.order, languages, "\(file): el orden de idiomas")
        }
        // El siguiente episodio (serie): cuál es y si un pedido tuyo ya lo trae (un paquete con todos sus videos).
        if kind == "series" {
            let meta = try? await services.cinemeta.meta(kind: "series", id: metaID)
            let next = meta.flatMap { CinemetaParsing.nextEpisode($0, after: video, now: now.timeIntervalSince1970) }
            var listed: Set<String> = []
            if let next, next == nextVideoID {
                let found = (try? await services.finder.find(kind: kind, videoID: next, prefs: list.prefs, purpose: .watch)) ?? []
                listed = Set(found.compactMap { $0.torrent?.hash })
            }
            out["next_episode"] = next.map { id in
                let covering = services.debridRequests.request(metaID: metaID, videoID: id, listed: listed)
                return ["video_id": .string(id), "request": covering.map { .string($0.hash) } ?? .null,
                        "ready": .bool(covering?.state == .ready)]
            } ?? .null
        }
        return Observed(title: title, list: list, json: .object(out))
    }

    static func name(_ p: TitlePrimary?) -> String {
        switch p {
        case .watch?: "play"
        case .request?: "request"
        case .requested?: "requested"
        case .onTV?: "play_on_tv"
        case .otherVersion?, .notifyWhenAppears?, .airs?, .unavailable?: "fix"
        case nil: "loading"
        }
    }

    /// La salida de cada problema (README › `fix`).
    static func fix(_ p: TitlePrimary?, cause: UnavailableCause?) -> String? {
        switch p {
        case .request?: return "request"
        case .otherVersion?: return "other_version"
        case .notifyWhenAppears?, .airs?: return "notify"
        case .unavailable?:
            switch cause?.action {
            case .renew?: return "renew"
            case .settings?: return "settings"
            case .retry?: return "retry"
            case .otherVersion?: return "other_version"
            case .request?: return "request"
            case nil: return nil
            }
        default: return nil
        }
    }

    /// Lo que cambia en el texto de una causa: el día de «Aún no se estrena · sale …» y el porcentaje de «Bajando … · 42 %».
    static func argument(_ c: UnavailableCause) -> JSON? {
        switch c {
        case .unreleased(let day): .string(day)
        case .downloading(let percent): .string("\(percent) %")
        default: nil
        }
    }

    /// Las llaves de las causas, en el orden de `design/vocabulario.json › causas` (README); la de la TV («Necesita Stremio
    /// abierto», `needs_stremio`) no existe en el iPhone.
    static let causeOrder = ["downloading", "unreleased", "cannot_search", "expired", "no_premium", "bad_key", "refused", "needs_stremio",
                             "addons_offline", "no_addons", "not_in_rd", "nobody_has_it"]

    /// Las llaves de las causas, en el orden de `design/vocabulario.json › causas` (README).
    static func name(_ c: UnavailableCause) -> String {
        switch c {
        case .downloading: "downloading"
        case .unreleased: "unreleased"
        case .cannotSearch: "cannot_search"
        case .debridExpired: "expired"
        case .noPremium: "no_premium"
        case .reconnectDebrid: "bad_key"
        case .debridRefused: "refused"
        case .addonsOffline: "addons_offline"
        case .noAddonsOn: "no_addons"
        case .notInDebrid: "not_in_rd"
        case .nobodyHasIt: "nobody_has_it"
        }
    }
}
