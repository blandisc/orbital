import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// Fernando, 3 nov, probando la 1729 con «El viento tiene miedo» (tt0061752): la ficha decía «Real-Debrid aún no la tiene»
/// y «Verlo en … al instante», y en «Versión» no aparecía ninguna que la tuviera; tras «Ya está» seguía igual. La ficha y la
/// lista leen lo mismo: lo que la lista enseña con «Al instante» es lo único que la ficha ofrece.
@MainActor
final class VientoTieneMiedoModelTests: XCTestCase {
    static let id = "tt0061752"
    static let yts1080 = "b3bdbf12d9d59e94fcff16bf1e7f893a37a75d78"
    static let yts720 = "71dba5d524b5c6dda7eeb5bc83e8118ae8fe9ad1"
    static let rutrackerRuso = "568ad8f0058b1faeab84044284d026b08fd75a1c"        // DVDRip con voz rusa
    static let bdremux1977 = "f3fbc8374054e4cad7ac7fa700cac6565868bc0c"          // «[1977 BDRemux]»: «¿Otro título?»
    static let mexico = TitleOrigin(language: "es", country: "Mexico", year: 1968, titles: ["Hasta el viento tiene miedo", "Even the Wind Is Afraid"])
    let latino = Preferences(audio: "es", quality: "1080p", spanish: "es-419")

    /// Torrentio con Real-Debrid para la película (lo real, sin Real-Debrid, con «[RD+]» en `cached`) y, si se pide, un
    /// enlace directo que no pasa por Real-Debrid (en inglés).
    static func streams(cached: Set<String>, direct: Bool = false) throws -> JSON {
        let raw = try Fixtures.json("streams/torrentio_tt0061752_sin_rd_2026-11-03.json")
        var out: [JSON] = (raw["streams"]?.array ?? []).compactMap { s in
            guard var o = s.object, let hash = s["infoHash"]?.string else { return nil }
            let quality = (s["name"]?.string ?? "").components(separatedBy: "\n").last ?? ""
            o["name"] = .string("\(cached.contains(hash) ? "[RD+]" : "[RD download]") Torrentio\n\(quality)")
            o["url"] = .string("https://torrentio.strem.fun/resolve/realdebrid/KEY/\(hash)/null/\(s["fileIdx"]?.intValue ?? 0)/x.mkv")
            o["infoHash"] = nil; o["fileIdx"] = nil
            return .object(o)
        }
        if direct { out.append(["name": "Directo\n1080p", "title": "Even the Wind Is Afraid 1968 1080p ENG\n💾 1.2 GB", "url": "https://direct.example/viento.mp4"]) }
        return ["streams": .array(out)]
    }

    func ranked(cached: Set<String>, direct: Bool = false) throws -> [Source] {
        let sources = (try Self.streams(cached: cached, direct: direct)["streams"]?.array ?? []).enumerated().map { i, s in
            var src = Streams.parse(s, addon: i < 9 ? "Torrentio" : "Directo", transportURL: "", index: i, origin: Self.mexico)
            src.otherTitle = !Streams.mentionsTitle(Self.mexico.titles, "\(src.release) \(s["behaviorHints"]?["filename"]?.string ?? "")")
            return src
        }
        return Streams.rank(sources, prefs: latino)
    }

    // MARK: 2 · «Verlo en … al instante»
    /// Lo que arranca y la lista NO enseña como «Al instante» no se ofrece: la de voz rusa (va a «Más idiomas»), la de otro
    /// título (escondida en «Otras») y un enlace directo (la lista no le dice «Al instante»).
    func testTheInstantAsideOnlyOffersWhatTheVersionListShowsAsInstant() throws {
        let found = try ranked(cached: [Self.rutrackerRuso, Self.bdremux1977], direct: true)
        XCTAssertFalse(found.first?.instant ?? true, "precondición: la recomendada (latino) no está en Real-Debrid")
        XCTAssertTrue(found.contains { $0.instant && $0.torrent?.hash == Self.rutrackerRuso }, "precondición: antes la ficha ofrecía esta")
        XCTAssertNil(TitleModel.shownInstant(found, prefs: latino), "ninguna sale «Al instante» en las tarjetas de «Versión»")
    }

    /// Una que sí está en la lista con «Al instante» (latino 720p): esa es la que se ofrece, y es una tarjeta de la hoja.
    func testTheInstantAsideIsACardOfTheVersionList() throws {
        let found = try ranked(cached: [Self.yts720, Self.rutrackerRuso])
        let offered = try XCTUnwrap(TitleModel.shownInstant(found, prefs: latino))
        XCTAssertEqual(offered.torrent?.hash, Self.yts720)
        let cards = SourcesModel.languageRows(found, prefs: latino, limitGB: 5).main.flatMap(\.options)
        XCTAssertTrue(cards.contains { $0.id == offered.index && $0.speed == .inRealDebrid })
    }

    // MARK: 3, 4 y 5 · «Ya está»
    /// Con el pedido listo en la libreta (Torrentio todavía dice «[RD download]»): la ficha pone «Ver» con esa versión (no
    /// «Pedirlo y avisarme» otra vez) y en «Versión» es la recomendada de latino, «Al instante · la pediste».
    func testAfterYaEstaTheTitleAndTheListAgreeOnTheRequestedVersion() async throws {
        let rig = try ServicesRig()
        rig.secrets.set(AddonKeys.realDebridToken, String(repeating: "K", count: 52))
        rig.services.settings.update { $0.audio = "es"; $0.latinSpanish = true }
        rig.http.json["https://v3-cinemeta.strem.io/meta/movie/\(Self.id).json"] = ["meta": try Fixtures.json("cinemeta/meta_movie_tt0061752.json")]
        rig.http.json["https://a.example/stream/movie/\(Self.id).json"] = try Self.streams(cached: [Self.rutrackerRuso])
        var request = DebridRequest(hash: Self.yts1080, fileIdx: 0, rdID: "R1", title: "Hasta el viento tiene miedo", kind: "movie", metaID: Self.id,
                                    videoIDs: [Self.id], language: "es-419", release: "Even the Wind Is afraid 1968 1080p BluRay", device: "iPhone",
                                    createdAt: Date(timeIntervalSince1970: 1_760_000_000), percent: 100, state: .ready)
        request.pending = false
        rig.services.debridRequests.requester.book.put(request)
        try await Task.sleep(nanoseconds: 50_000_000)   // `Services` configura la búsqueda en una tarea

        let title = TitleModel(rig.services, kind: "movie", metaID: Self.id)
        await title.load()
        await title.loadBestSource()
        let playing = try XCTUnwrap(title.recommendedSource)
        XCTAssertEqual(playing.torrent?.hash, Self.yts1080, "«Ver» pone la que pediste")
        XCTAssertTrue(playing.instant && playing.requested)
        XCTAssertNil(title.debridOffer, "no vuelve a decir «Pedirlo y avisarme»")
        XCTAssertNil(title.unavailableCause)

        let list = SourcesModel(rig.services, kind: "movie", metaID: Self.id, videoID: Self.id)
        await list.load()
        let row = try XCTUnwrap(list.languageRows.first, "la primera fila es la tuya")
        XCTAssertEqual(row.code, "es-419")
        let card = try XCTUnwrap(row.options.first { $0.recommended })
        XCTAssertEqual(card.id, playing.index, "la recomendada de la lista es la misma que «Ver»")
        XCTAssertTrue(card.requested)
        XCTAssertEqual(card.speed, .inRealDebrid, "«Al instante · la pediste»")
    }
}
