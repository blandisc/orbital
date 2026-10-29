import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

@MainActor
final class ScreenModelsTests: XCTestCase {
    // MARK: sesión
    func testSignInStoresOnlyTheSessionKey() async throws {
        let rig = try ServicesRig(signedIn: false)
        rig.http.json["https://api.strem.io/api/login"] = ["result": ["authKey": "NEWKEY", "user": ["email": "a@b.c"]]]
        let session = SessionModel(rig.services)
        XCTAssertEqual(session.state, .signedOut)
        await session.signIn(email: " a@b.c ", password: "secreta")
        XCTAssertEqual(session.state, .signedIn)
        XCTAssertEqual(rig.secrets.get(SecretKey.stremioAuth), "NEWKEY")
        let sent = String(data: rig.http.bodies("https://api.strem.io/api/login").first ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(sent.contains("secreta"))
        XCTAssertNil(rig.kv.data("password"), "la contraseña no se guarda")
    }

    func testSignInFailureShowsStremioMessage() async throws {
        let rig = try ServicesRig(signedIn: false)
        rig.http.json["https://api.strem.io/api/login"] = ["error": ["message": "User not found"]]
        let session = SessionModel(rig.services)
        await session.signIn(email: "a@b.c", password: "x")
        XCTAssertEqual(session.state, .failed("User not found"))
        XCTAssertNil(rig.secrets.get(SecretKey.stremioAuth))
        await session.signIn(email: "", password: "")
        if case .failed(let message) = session.state { XCTAssertTrue(message.contains("correo")) } else { XCTFail() }
    }

    func testAddingAnAddonValidatesItsManifestAndSavesItEncrypted() async throws {
        let rig = try ServicesRig()
        rig.secrets.set(SecretKey.ownAddons, nil)
        rig.http.json["https://nuevo.example/KEY/manifest.json"] = ["name": "Nuevo", "resources": ["stream"], "types": ["movie"]]
        let session = SessionModel(rig.services)
        await session.addAddon("stremio://nuevo.example/KEY")
        XCTAssertEqual(session.ownAddonURLs, ["https://nuevo.example/KEY/manifest.json"])
        XCTAssertEqual(session.addons.map(\.name), ["Nuevo"])
        await session.addAddon("https://roto.example")
        XCTAssertNotNil(session.addonError)
        XCTAssertEqual(session.ownAddonURLs.count, 1, "uno que no responde no se guarda")
        await session.removeAddon(url: "https://nuevo.example/KEY/manifest.json")
        XCTAssertTrue(session.ownAddonURLs.isEmpty)
    }

    // MARK: inicio
    /// «Seguir viendo» y Mi lista salen del teléfono (sin cuenta de Stremio) y abren al instante con la copia de la última vez.
    func testHomeShowsContinueWatchingAndMyListFromThePhone() async throws {
        let rig = try ServicesRig(signedIn: false)
        let lib = rig.services.library
        lib.update("tt0386676", make: { LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office") }) {
            $0.videoID = "tt0386676:2:5"; $0.position = 600; $0.duration = 1320; $0.updatedAt = 1_735_776_000
        }
        lib.update("tt1160419", make: { LibraryEntry(metaID: "tt1160419", kind: "movie", name: "Dune") }) { $0.inList = true; $0.listedAt = 1 }
        lib.update("tt9", make: { LibraryEntry(metaID: "tt9", kind: "movie", name: "Abierta un momento") }) {
            $0.videoID = "tt9"; $0.position = 1; $0.duration = 6000; $0.updatedAt = 2
        }
        let home = HomeModel(rig.services)
        await home.refresh()
        XCTAssertEqual(home.continueWatching.map(\.metaID), ["tt0386676"])
        XCTAssertEqual(home.continueWatching.first?.season, 2); XCTAssertEqual(home.continueWatching.first?.episode, 5)
        XCTAssertEqual(home.continueWatching.first?.timeLeft, "quedan 12 min")
        XCTAssertEqual(home.continueWatching.first?.progress ?? 0, 600.0 / 1320.0, accuracy: 0.001)
        XCTAssertEqual(home.myList.map(\.metaID), ["tt1160419"])
        XCTAssertEqual(home.traktPending.map(\.imdb), ["tt1160419"], "Mi lista se pinta en el renglón de la watchlist")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("api.strem.io") }, "sin Stremio conectado no se le pregunta nada")
        let again = HomeModel(rig.services)
        XCTAssertEqual(again.continueWatching.map(\.metaID), ["tt0386676"], "la copia guardada se ve al instante")
    }

    /// «Quitar de Mi lista» desde el menú: sale al instante y «Deshacer» la regresa a su mismo lugar (sin duplicarla).
    func testRemovingFromMyListHidesAndUndoRestoresInPlace() async throws {
        let rig = try ServicesRig(signedIn: false)
        for (i, id) in ["tt1", "tt2", "tt3"].enumerated() {
            rig.services.library.update(id, make: { LibraryEntry(metaID: id, kind: "movie", name: id) }) { $0.inList = true; $0.listedAt = Double(10 - i) }
        }
        let home = HomeModel(rig.services)
        await home.refresh()
        let before = home.traktPending.map(\.imdb)
        XCTAssertEqual(before, ["tt1", "tt2", "tt3"])
        home.setShown(before[1], shown: false)
        XCTAssertEqual(home.traktPending.map(\.imdb), [before[0], before[2]])
        home.setShown(before[1], shown: true)
        home.setShown(before[1], shown: true)
        XCTAssertEqual(home.traktPending.map(\.imdb), before, "regresa en su lugar, una sola vez")
    }

    func testSpotlightInterleavesListsWithoutRepeatsOrWhatYouAreWatching() {
        func s(_ id: String, _ kind: String) -> Suggestion { Suggestion(kind: kind, imdb: id, title: id, poster: "", wide: "", reason: .trending) }
        let trend = [s("tt1", "movie"), s("tt2", "movie")], series = [s("tt3", "series"), s("tt1", "movie")], popular = [s("tt4", "movie"), s("tt5", "movie")]
        let mixed = HomeModel.mixSpotlight([trend, series, popular], excluding: ["tt4"], limit: 4)
        XCTAssertEqual(mixed.map(\.imdb), ["tt1", "tt3", "tt2", "tt5"])   // una de cada lista por vuelta; tt1 no se repite; tt4 ya la ves
    }

    func testHomeTitlesAreLocalizedButOriginalsKept() async throws {
        let rig = try ServicesRig(tmdbKey: "K")
        rig.services.settings.update { $0.uiLanguage = "es" }
        rig.services.reconfigure()
        rig.services.library.update("tt0386676", make: { LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office") }) {
            $0.videoID = "tt0386676:1:1"; $0.position = 500; $0.duration = 1320; $0.updatedAt = 1
        }
        rig.http.json["https://api.themoviedb.org/3/find/tt0386676?external_source=imdb_id&api_key=K&language=es-MX"] = ["tv_results": [["id": 2316]]]
        rig.http.json["https://api.themoviedb.org/3/tv/2316?language=es-MX&api_key=K"] = ["name": "La Oficina", "overview": "x", "genres": [], "seasons": []]
        let home = HomeModel(rig.services)
        await home.refresh()
        XCTAssertEqual(home.continueWatching.first?.title, "La Oficina")
        XCTAssertEqual(home.continueWatching.first?.originalTitle, "The Office")
    }

    // MARK: búsqueda
    func testSearchKeepsOnlyTheLatestQueryAndRemembersWhatYouOpen() async throws {
        let rig = try ServicesRig()
        let movies = try Fixtures.json("cinemeta/search_movie_dune.json"), series = try Fixtures.json("cinemeta/search_series_dune.json")
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=dune.json"] = ["metas": movies]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=dune.json"] = ["metas": series]
        let search = SearchModel(rig.services)
        await search.search("d")
        XCTAssertTrue(search.results.isEmpty, "con una letra no se busca")
        await search.search("dune")
        XCTAssertTrue(search.results.contains { $0.kind == "movie" } && search.results.contains { $0.kind == "series" })
        XCTAssertEqual(search.searchedQuery, "dune", "la pantalla sabe a qué búsqueda pertenecen los resultados")
        await search.search("d")
        XCTAssertNil(search.searchedQuery, "con una letra no hay búsqueda contestada")
        await search.search("dune")
        search.remember("dune"); search.remember("Severance"); search.remember("DUNE")
        XCTAssertEqual(search.recent, ["DUNE", "Severance"])
        XCTAssertEqual(SearchModel(rig.services).recent, ["DUNE", "Severance"], "se guarda")
    }

    func testSearchCountsAreTheRealOnesNotNineAndNine() async throws {
        let rig = try ServicesRig()
        func metas(_ prefix: String, _ n: Int) -> JSON {
            .array((0..<n).map { .object(["id": .string("tt\(prefix)\($0)"), "name": .string("Star \($0)"), "poster": .string("https://images.metahub.space/poster/medium/tt\(prefix)\($0)/img")]) })
        }
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top/search=star.json"] = ["metas": metas("1", 15)]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/series/top/search=star.json"] = ["metas": metas("2", 12)]
        let search = SearchModel(rig.services)
        await search.search("star")
        XCTAssertEqual(search.results.filter { $0.kind == "movie" }.count, 15, "antes salían 15 películas como 9 (18 en total, alternando)")
        XCTAssertEqual(search.results.filter { $0.kind == "series" }.count, 12)
    }

    func testSearchShowsEachKindAsItArrivesAndKeepsOneWhenTheOtherFails() async throws {
        let rig = try ServicesRig()
        let movies = try Fixtures.json("cinemeta/search_movie_dune.json"), series = try Fixtures.json("cinemeta/search_series_dune.json")
        let movieURL = "https://v3-cinemeta.strem.io/catalog/movie/top/search=dune.json", seriesURL = "https://v3-cinemeta.strem.io/catalog/series/top/search=dune.json"
        rig.http.json[movieURL] = ["metas": movies]
        rig.http.json[seriesURL] = ["metas": series]
        rig.http.delays = [seriesURL: 400]
        let search = SearchModel(rig.services)
        let running = Task { await search.search("dune") }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(!search.results.isEmpty && search.results.allSatisfy { $0.kind == "movie" }, "las películas no esperan a las series")
        await running.value
        XCTAssertTrue(search.results.contains { $0.kind == "series" }, "las series se suman al llegar")

        // Series falla (las dos veces): las películas se quedan y no hay error.
        rig.http.json[seriesURL.replacingOccurrences(of: "dune", with: "duna")] = nil
        rig.http.json[movieURL.replacingOccurrences(of: "dune", with: "duna")] = ["metas": movies]
        rig.http.delays = [:]
        await search.search("duna")
        XCTAssertNil(search.error)
        XCTAssertTrue(!search.results.isEmpty && search.results.allSatisfy { $0.kind == "movie" })
    }

    // MARK: ficha
    func titleRig() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": [["_id": "tt0386676", "name": "The Office", "type": "series", "removed": false, "temp": false,
            "state": ["video_id": "tt0386676:1:3", "timeOffset": 660_000, "duration": 1_320_000,
                      "watched": .string(StremioLibrary.encodeWatched(["tt0386676:1:1", "tt0386676:1:2"], videoIDs: CinemetaParsing.seasonVideoIDs(try Fixtures.json("cinemeta/meta_series_tt0386676.json"))) ?? "")]]]]
        rig.http.json[stremioPut] = ["result": ["success": true]]
        // Lo mismo en el teléfono (la ficha lee de aquí; Stremio solo recibe copia).
        rig.services.library.update("tt0386676", make: { LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office") }) {
            $0.videoID = "tt0386676:1:3"; $0.position = 660; $0.duration = 1320; $0.updatedAt = 1_759_000_000
            $0.seen = ["tt0386676:1:1", "tt0386676:1:2"]; $0.inList = true; $0.listedAt = 1
        }
        return rig
    }

    func testTitleShowsEpisodeStatesAndTheContinueButton() async throws {
        let rig = try titleRig()
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        XCTAssertEqual(title.originalTitle, "The Office")
        XCTAssertEqual(title.selectedSeason, 1, "abre en la temporada donde vas")
        XCTAssertEqual(title.rows.prefix(3).map(\.watched), [true, true, false])
        XCTAssertEqual(title.rows[2].progress ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(title.rows[2].timeLeft, "quedan 11 min")
        XCTAssertTrue(title.inLibrary)
        XCTAssertEqual(title.continueVideoID, "tt0386676:1:3")
        let label = title.continueLabel
        XCTAssertTrue(label.isResume); XCTAssertEqual(label.season, 1); XCTAssertEqual(label.episode, 3)
        let request = try XCTUnwrap(title.playRequest())
        XCTAssertEqual(request.videoID, "tt0386676:1:3")
        XCTAssertEqual(request.originalTitle, "The Office")
        XCTAssertTrue(request.episodeLabel.hasPrefix("T1 · E3"))
    }

    /// CEN-37: sin clave de TMDB en el iPhone, con la consola conectada la ficha toma su sinopsis (en español); sin consola, lo
    /// de Cinemeta. Con clave, el iPhone es independiente: no le pregunta a la consola.
    func testTitleTakesTheConsolesOverviewOnlyWithoutItsOwnTmdbKey() async throws {
        let rig = try titleRig()
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        let cinemeta = title.info.description
        await title.loadConsoleDetails()
        XCTAssertNil(title.consoleOverview, "sin consola no cambia nada")
        XCTAssertEqual(title.overview, cinemeta)

        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        rig.http.json["https://tv.example/api/foryou/details?key=video:tt0386676&kind=series"] = ["overview": " Un falso documental. ", "logo_dark": true]
        await title.loadConsoleDetails()
        XCTAssertEqual(title.overview, "Un falso documental.")

        rig.http.json["https://tv.example/api/foryou/details?key=video:tt0386676&kind=series"] = ["overview": ""]
        let other = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await other.load(); await other.loadConsoleDetails()
        XCTAssertEqual(other.overview, other.info.description, "una sinopsis vacía no tapa la de Cinemeta")

        rig.http.json["https://tv.example/api/foryou/details?key=video:tt0386676&kind=series"] = ["overview": "De la consola"]
        rig.secrets.set(SecretKey.tmdbKey, "clave")
        rig.services.reconfigure()
        let own = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await own.load(); await own.loadConsoleDetails()
        XCTAssertNil(own.consoleOverview, "con su propia clave de TMDB no depende de la consola")
        XCTAssertEqual(own.overview, own.info.description)
    }

    func testTitleWithoutHistoryStartsAtTheFirstEpisode() async throws {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": []]
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        XCTAssertEqual(title.continueVideoID, "tt0386676:1:1")
        XCTAssertFalse(title.continueLabel.isResume)
        XCTAssertFalse(title.inLibrary)
    }

    /// «¿Qué vemos?» › Ver: la misma cuenta que «Continuar» de la ficha, sin abrirla — el capítulo en que vas o el primero de
    /// verdad (los especiales no cuentan como primero).
    func testContinueVideoWithoutOpeningTheTitle() throws {
        let seasons = CinemetaParsing.seasons(try Fixtures.json("cinemeta/meta_series_tt0386676.json"))
        var going = LibraryEntry(metaID: "tt0386676", kind: "series", name: "The Office")
        going.videoID = "tt0386676:2:5"; going.nextUp = true
        XCTAssertEqual(TitleModel.continueVideoID(kind: "series", metaID: "tt0386676", entry: going, seasons: seasons), "tt0386676:2:5")
        XCTAssertEqual(TitleModel.continueVideoID(kind: "series", metaID: "tt0386676", entry: nil, seasons: seasons), "tt0386676:1:1")
        XCTAssertEqual(TitleModel.continueVideoID(kind: "movie", metaID: "tt0816692", entry: nil, seasons: []), "tt0816692")
    }

    /// Mi lista: cambia en el teléfono al instante, viaja a tu watchlist de Trakt y a Stremio solo como copia (sin tocar el avance).
    func testMyListToggleIsLocalTravelsToTraktAndCopiesToStremio() async throws {
        let rig = try titleRig()
        rig.secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(1_760_000_000 + 86400)}"#)
        rig.services.settings.update { $0.traktClientID = "CID" }
        rig.services.reconfigure()
        rig.http.json["https://api.trakt.tv/sync/watchlist"] = [:]
        rig.http.json["https://api.trakt.tv/sync/watchlist/remove"] = [:]
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        XCTAssertTrue(title.inLibrary)
        await title.toggleLibrary()
        XCTAssertFalse(title.inLibrary)
        XCTAssertEqual(rig.services.library.entry("tt0386676")?.inList, false)
        let sent = try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/sync/watchlist/remove").first.flatMap(JSON.parse))
        XCTAssertEqual(sent["shows"]?.array?.first?["ids"]?["imdb"]?.string, "tt0386676")
        let copy = try XCTUnwrap(rig.http.bodies(stremioPut).last.flatMap(JSON.parse)?["changes"]?.array?.first)
        XCTAssertEqual(copy["removed"]?.bool, true)
        XCTAssertEqual(copy["state"]?["video_id"]?.string, "tt0386676:1:3", "el avance de Stremio no se toca")
        // Stremio falla: Mi lista cambia igual (la copia no manda) y no hay error en pantalla.
        rig.http.statuses[stremioPut] = 500
        await title.toggleLibrary()
        XCTAssertTrue(title.inLibrary)
        XCTAssertNil(title.message)
    }

    /// Marcar visto: ✓ en el teléfono, a Trakt (`/sync/history`) y copia en Stremio (el bitfield), con el título original.
    func testMarkingWatchedIsLocalAndCopiesTheBitfieldToStremio() async throws {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": []]
        rig.http.json[stremioPut] = ["result": ["success": true]]
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        await title.markWatched("tt0386676:1:1")
        XCTAssertTrue(title.rows.first { $0.id == "tt0386676:1:1" }?.watched == true)
        XCTAssertEqual(rig.services.library.entry("tt0386676")?.videoID, "tt0386676:1:2", "pasa al siguiente")
        let item = try XCTUnwrap(rig.http.bodies(stremioPut).last.flatMap(JSON.parse)?["changes"]?.array?.first)
        let ids = CinemetaParsing.seasonVideoIDs(try Fixtures.json("cinemeta/meta_series_tt0386676.json"))
        XCTAssertEqual(StremioLibrary.parseWatched(item["state"]?["watched"]?.string, videoIDs: ids), ["tt0386676:1:1"])
        XCTAssertEqual(item["name"]?.string, "The Office", "con el título original")
        await title.unmarkWatched("tt0386676:1:1")
        XCTAssertFalse(title.rows.first { $0.id == "tt0386676:1:1" }?.watched == true)
    }

    func testDownloadingPicksAModerateSourceAndKeepsTheLinkOutOfTheQueue() async throws {
        let rig = try titleRig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A3.json"] = ["streams": [
            ["name": "T\n2160p [RD+]", "title": "Show S01E03 2160p REMUX\n👤 100 💾 40 GB", "url": "https://rd.example/SECRET/big.mkv"],
            ["name": "T\n1080p [RD+]", "title": "Show S01E03 1080p WEB-DL x265\n👤 100 💾 0.5 GB", "url": "https://rd.example/SECRET/small.mkv"]]]
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        let outcome = await title.download(["tt0386676:1:3"])
        XCTAssertEqual(outcome, .queued(1))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(rig.transport.starts, ["https://rd.example/SECRET/small.mkv"], "para guardar: 1080p moderado, no el REMUX 4K")
        let json = String(data: try JSONEncoder().encode(await rig.services.downloads.all), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("SECRET"))
        XCTAssertEqual(title.rows.first { $0.id == "tt0386676:1:3" }?.download, .downloading)
    }

    /// «Bajar también esta»: dos versiones del mismo episodio. La ficha que las sigue no se cierra (antes armaba un
    /// diccionario con claves únicas por video y la app tronaba).
    func testTwoVersionsOfTheSameVideoDoNotCrashTheTitle() async throws {
        let rig = try titleRig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A3.json"] = ["streams": [
            ["name": "T\n1080p [RD+]", "title": "Show S01E03 1080p WEB-DL\n💾 0.5 GB", "url": "https://rd.example/one.mkv"]]]
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        let following = Task { await title.followDownloads() }
        defer { following.cancel() }
        let first = await title.download(["tt0386676:1:3"])
        XCTAssertEqual(first, .queued(1))
        let second = await title.download(["tt0386676:1:3"], keepBoth: true)
        XCTAssertEqual(second, .queued(1))
        try await Task.sleep(nanoseconds: 100_000_000)
        let all = await rig.services.downloads.all
        XCTAssertEqual(all.filter { $0.videoID == "tt0386676:1:3" }.count, 2)
        XCTAssertNotNil(title.downloadState("tt0386676:1:3"))
    }

    func testDownloadWithoutSourcesOrWithoutSpace() async throws {
        let rig = try titleRig()
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        let none = await title.download(["tt0386676:1:9"])
        XCTAssertEqual(none, .noSources)
        let small = try ServicesRig()
        let tiny = Services(http: small.http, secrets: small.secrets, kv: small.kv, pending: small.pending, downloadTransport: small.transport, downloadsRoot: small.root, freeSpace: { 100_000_000 })
        small.http.json[stremioGet] = ["result": []]
        small.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [["name": "T\n1080p [RD+]", "title": "x 1080p\n💾 2 GB", "url": "https://rd.example/a.mkv"]]]
        let model = TitleModel(tiny, kind: "series", metaID: "tt0386676")
        await model.load()
        let result = await model.download(["tt0386676:1:1"])
        if case .notEnoughSpace = result {} else { XCTFail("\(result)") }
    }

    // MARK: Para ti
    func testParaTiLoadsMosaicAndRailsWithoutGames() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let api = "https://api.trakt.tv"
        rig.http.json["\(api)/sync/watchlist?extended=full&sort_by=added&sort_how=desc"] = [["type": "show", "listed_at": "2025-06-01T00:00:00.000Z", "show": ["title": "Severance", "ids": ["imdb": "tt11280740"]]]]
        rig.http.json["\(api)/recommendations/shows?limit=30&ignore_collected=true&ignore_watchlisted=true&extended=full"] = [["title": "Shōgun", "ids": ["imdb": "tt2788316"]]]
        rig.http.json["\(api)/recommendations/movies?limit=30&ignore_collected=true&ignore_watchlisted=true&extended=full"] = [["title": "Past Lives", "ids": ["imdb": "tt13238346"]]]
        rig.http.json["\(api)/users/me/lists"] = []
        rig.http.json["\(api)/sync/history/episodes?limit=100"] = []
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertTrue(model.traktLinked)
        XCTAssertEqual(Set(model.mosaic.map(\.imdb)), ["tt11280740", "tt2788316", "tt13238346"])
        XCTAssertEqual(model.watchlistKeys, ["tt11280740"])
        XCTAssertEqual(model.visibleShelves.map(\.id), ["recs", "watchlist"], "el orden de la TV: Recomendadas y luego Tu watchlist; lo vacío no se pinta")
        let recs = try XCTUnwrap(model.visibleShelves.first)
        XCTAssertEqual(model.items(for: recs).map(\.imdb), ["tt2788316", "tt13238346"], "«Todo»: la serie y la película, alternadas")
        await model.setKind("series")
        XCTAssertEqual(model.items(for: recs).map(\.imdb), ["tt2788316"])
        let watchlist = try XCTUnwrap(model.visibleShelves.last)
        XCTAssertEqual(model.items(for: watchlist).map(\.imdb), ["tt11280740"])
        await model.setKind("movie")
        XCTAssertEqual(model.items(for: recs).map(\.imdb), ["tt13238346"])
        XCTAssertEqual(model.items(for: watchlist).map(\.imdb), ["tt11280740"], "Tu watchlist no tiene split: Series · Películas no la toca")
        await model.dismiss(model.mosaic[0])
        XCTAssertEqual(model.mosaic.count, 2)
    }

    func testParaTiExplainsWhatToConfigureWhenThereIsNothing() async throws {
        let rig = try ServicesRig()
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertTrue(model.mosaic.isEmpty)
        XCTAssertNotNil(model.error)
    }

    /// Trakt conectado pero sin nada tuyo todavía (ni recomendadas ni watchlist): el mosaico es lo que está en tendencia.
    func testParaTiWithNothingOfYoursShowsWhatIsTrendingOnTrakt() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "cid")
        TraktPublicListsTests.trending(rig, series: [("tt0386676", "The Office", 2005), ("kitsu:1", "Sin IMDb", 2020)], movies: [("tt1160419", "Dune", 2021)])
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertTrue(model.isGeneric)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.mosaic.map(\.imdb), ["tt0386676", "tt1160419"], "series y películas alternadas; sin IMDb no se puede ver")
        XCTAssertEqual(model.mosaic.first?.poster, String(format: ForYou.metahubPoster, "tt0386676"))
        XCTAssertEqual(model.mosaic.first?.wide, String(format: ForYou.metahubBackground, "tt0386676"))
        XCTAssertEqual(model.mosaic.last?.year, 2021); XCTAssertEqual(model.mosaic.last?.runtime, 155)
        XCTAssertEqual(model.mosaic.allSatisfy { $0.reason == .trending }, true)
        XCTAssertFalse(rig.http.calls.contains { $0.contains("cinemeta") && $0.contains("/top.json") }, "lo popular ya no sale de Cinemeta")
        await model.dismiss(model.mosaic[0])
        await model.refresh()
        XCTAssertEqual(model.mosaic.map(\.imdb), ["tt1160419"], "«No me interesa» también vale aquí")
    }

    /// CEN-18: con tu Orbital conectada, «Para ti» viene de allá (misma curaduría, con el puesto de un chart si lo trae).
    func testParaTiUsesTheConsolesForYouWhenConnected() async throws {
        let rig = try ServicesRig()
        rig.services.forYouFromConsole = true   // la ruta de la consola (la app, por omisión, calcula Para ti en el iPhone)
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        rig.http.json["https://tv.example/api/foryou"] = [
            "lists": [["id": "netflix", "title": "Netflix", "icon": "trailer", "source": "TMDB", "meta": "x", "split": true,
                       "brand": "netflix", "logo": "https://logo/netflix.png"]],
            "mosaic": [["key": "video:tt1160419", "kind": "movie", "meta_id": "tt1160419", "title": "Dune", "year": 2021,
                        "why": "En Netflix", "rank": 1, "image": "https://p.jpg", "hero": "https://h.jpg", "overview": "", "video_id": "tt1160419"]],
        ]
        rig.http.json["https://tv.example/api/foryou/list?id=netflix&kind=series"] = ["items": [
            ["key": "video:tt1160419", "kind": "movie", "meta_id": "tt1160419", "title": "Dune", "year": 2021,
             "why": "En Netflix", "rank": 1, "image": "https://p.jpg", "hero": "https://h.jpg", "overview": "", "video_id": "tt1160419"],
        ]]
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertEqual(model.source, .console)
        XCTAssertEqual(model.mosaic.map(\.imdb), ["tt1160419"])
        XCTAssertEqual(model.mosaic.first?.rank, 1)
        XCTAssertEqual(model.platformLists.map(\.id), ["netflix"])
        XCTAssertEqual(model.shelves.map(\.id), ["netflix"], "sin chart ni jw, el respaldo de TMDB sí se pinta")
    }

    /// Si tu Orbital está conectada pero no contesta «Para ti» (versión anterior, o no responde), se cae a la lógica
    /// local de siempre, sin aviso de error visible.
    func testParaTiFallsBackToLocalWhenTheConsoleDoesNotAnswerForYou() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        // /api/foryou no se registra: la consola de mentira contesta 404, como una versión anterior sin esta ruta.
        TraktPublicListsTests.trending(rig, series: [("tt0386676", "The Office", 2005)], movies: [("tt1160419", "Dune", 2021)])
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertEqual(model.source, .phone)
        XCTAssertEqual(model.mosaic.map(\.imdb), ["tt0386676", "tt1160419"], "sin tu sesión de Trakt, su tendencia")
        XCTAssertNil(model.error)
    }

    /// El iPhone calcula Para ti él mismo aunque tu Orbital esté conectada (no depende de que conteste): trae sus propias listas
    /// con puesto (Top 10 de Netflix, tendencias de JustWatch) y solo le avisa a la consola lo que marcas «No me interesa».
    func testParaTiIsComputedOnThePhoneEvenWithYourOrbitalConnected() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        rig.http.json["https://tv.example/api/foryou/dismiss"] = ["ok": true]
        TraktPublicListsTests.trending(rig, series: nil, movies: [("tt1160419", "Dune", 2021)])
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertEqual(model.source, .phone)
        XCTAssertFalse(rig.http.calls.contains("https://tv.example/api/foryou"), "no le pide Para ti a la consola")
        XCTAssertTrue(model.lists.contains { $0.id == "chart:netflix" }, "el Top 10 de Netflix lo calcula el iPhone")
        XCTAssertTrue(model.lists.contains { $0.id == "jw:disney" }, "y las tendencias de Disney+")
        await model.dismiss(model.mosaic[0])
        XCTAssertTrue(rig.http.calls.contains("https://tv.example/api/foryou/dismiss"), "«No me interesa» también se le avisa a la TV")
    }

    /// Cambiar un ajuste avisa a quien escucha a los servicios (la app entera se vuelve a pintar): antes el modo oscuro o el
    /// avatar no cambiaban hasta reabrir la app.
    @MainActor func testChangingASettingTellsTheApp() throws {
        let rig = try ServicesRig()
        let model = SettingsModel(rig.services)
        var told = 0
        let subscription = rig.services.onChange { told += 1 }
        model.update { $0.appearance = "light" }
        model.update { $0.avatar = "comet" }
        XCTAssertEqual(told, 2)
        XCTAssertEqual(rig.services.appSettings.avatar, "comet")
        subscription.cancel()
    }

    func testConnectingYourOrbitalKeepsTheTokenInTheKeychainAndChecksIt() async throws {
        let rig = try ServicesRig()
        let model = SettingsModel(rig.services)
        model.update { $0.orbitalAddress = "tv.example" }
        model.setOrbitalToken("  secreto ")
        XCTAssertEqual(rig.secrets.get(SecretKey.orbitalToken), "secreto")
        XCTAssertTrue(model.hasOrbitalToken)
        rig.http.json["https://tv.example/api/ping"] = ["ok": true]
        await model.checkOrbital()
        XCTAssertEqual(model.orbitalCheck, "")
        rig.http.statuses["https://tv.example/api/ping"] = 401
        await model.checkOrbital()
        XCTAssertEqual(model.orbitalCheck, OrbitalRemote.Failure.badToken.description)
    }

    func testTheNextEpisodeDownloadedOnItsOwnSaysWhichEpisodeItIs() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A2.json"] = ["streams": [["name": "T\n1080p [RD+]", "title": "Ep 1080p\n💾 900 MB 🇲🇽", "url": "https://rd.example/e2.mkv"]]]
        let watched = DownloadItem(id: DownloadItem.makeID(metaID: "tt0386676", videoID: "tt0386676:1:1"), kind: "series", metaID: "tt0386676", videoID: "tt0386676:1:1",
                                   title: "La Oficina", originalTitle: "The Office", subtitle: "T1 · E1 · Pilot", poster: nil, addon: "Torrentio", sourceIndex: 1,
                                   expectedBytes: nil, relativePath: "a/b.mkv", createdAt: 0)
        try await rig.services.downloads.enqueue(watched, url: URL(string: "https://rd.example/e1.mkv")!)
        await DownloadsModel(rig.services, freeSpace: { 50_000_000_000 }).afterWatching(watched)
        let next = await rig.services.downloads.all.first { $0.videoID == "tt0386676:1:2" }
        XCTAssertEqual(next?.subtitle, "T1 · E2 · Diversity Day")
    }

    func testYourOrbitalFillsInTMDBAndTraktWithoutOverwritingWhatYouTyped() async throws {
        let rig = try ServicesRig()
        let model = SettingsModel(rig.services)
        model.update { $0.orbitalAddress = "tv.example" }
        model.setOrbitalToken("secreto")
        rig.http.json["https://tv.example/api/ping"] = ["ok": true]
        rig.http.json["https://tv.example/api/companion"] = ["tmdb_key": "tmdb123", "trakt_client_id": "cid456", "region": "US"]
        await model.checkOrbital()
        XCTAssertEqual(rig.secrets.get(SecretKey.tmdbKey), "tmdb123", "la clave va al Keychain")
        XCTAssertEqual(model.settings.traktClientID, "cid456")
        XCTAssertEqual(model.settings.region, "US")
        XCTAssertEqual(model.importedFromOrbital, ["TMDB", "Trakt"])
        XCTAssertEqual(model.trakt, .unlinked, "ya se puede conectar Trakt con un toque")
        rig.http.json["https://tv.example/api/companion"] = ["tmdb_key": "otra", "trakt_client_id": "otro", "region": "US"]
        await model.checkOrbital()
        XCTAssertEqual(rig.secrets.get(SecretKey.tmdbKey), "tmdb123", "lo que ya tenías no se pisa")
        XCTAssertEqual(model.importedFromOrbital, [])
    }

    /// La sesión que antes prestaba la consola (sin refresh token) se olvida aquí SIN revocarla (revocarla desconectaría la
    /// consola): el iPhone queda «por conectar» con su propia sesión, y la app de Trakt sí se trae.
    func testConnectingTheTVNoLongerAdoptsItsSessionAndForgetsTheBorrowedOneWithoutRevoking() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://legion.example/api/ping"] = ["ok": true]
        rig.http.json["https://legion.example/api/companion"] = ["tmdb_key": "k", "trakt_client_id": "cid", "region": "MX"]
        rig.secrets.set(SecretKey.traktTokens, #"{"access_token":"PRESTADA","expires_at":1760100000}"#)   // la de antes
        let got = try await rig.services.connectOrbital(address: "https://legion.example", token: "secreto")
        XCTAssertEqual(got, ["TMDB", "Trakt"])
        XCTAssertEqual(rig.services.trakt?.linked, false, "nada de la sesión de la consola: se conecta la del iPhone")
        XCTAssertNil(rig.secrets.get(SecretKey.traktTokens))
        XCTAssertFalse(rig.http.calls.contains { $0.contains("/oauth/revoke") }, "revocarla desconectaría la consola")
        XCTAssertEqual(rig.secrets.get(SecretKey.traktClientID), "cid", "la app de Trakt también al Keychain (reinstalar)")
        XCTAssertEqual(SettingsModel(rig.services).trakt, .unlinked, "Ajustes ofrece «Conectar Trakt»")
    }

    /// Al abrir la app con la sesión prestada de antes (aunque la consola no conteste): se olvida sin revocar.
    func testABorrowedSessionIsForgottenAtLaunchWithoutRevoking() async throws {
        let first = try ServicesRig(traktClientID: "cid")
        first.secrets.set(SecretKey.traktTokens, #"{"access_token":"PRESTADA","expires_at":1760100000}"#)
        first.services.reconfigure()
        XCTAssertEqual(first.services.trakt?.linked, false)
        XCTAssertNil(first.secrets.get(SecretKey.traktTokens))
        XCTAssertFalse(first.http.calls.contains { $0.contains("api.trakt.tv") }, "sin llamar a Trakt (ni a /oauth/revoke)")
    }

    /// El Client ID: el de Ajustes, luego el que trae la consola, luego el incluido en la app.
    func testTraktClientIDPriorityIsSettingsThenConsoleThenBuiltIn() async throws {
        let builtIn = try ServicesRig(builtInTraktClientID: "INCLUIDO")
        XCTAssertNotNil(builtIn.services.trakt, "sin Ajustes ni consola: el incluido en la app")
        XCTAssertEqual(Services.traktClientID(settings: AppSettings(), secrets: InMemorySecrets(), builtIn: "INCLUIDO"), "INCLUIDO")
        // Llega la consola: su Client ID gana al incluido.
        builtIn.http.json["https://legion.example/api/ping"] = ["ok": true]
        builtIn.http.json["https://legion.example/api/companion"] = ["tmdb_key": "", "trakt_client_id": "CONSOLA", "region": "MX"]
        _ = try await builtIn.services.connectOrbital(address: "https://legion.example", token: "t")
        XCTAssertEqual(Services.traktClientID(settings: builtIn.services.appSettings, secrets: builtIn.secrets, builtIn: "INCLUIDO"), "CONSOLA")
        // El escrito en Ajustes › Avanzado gana a los dos, y la consola no lo pisa.
        let model = SettingsModel(builtIn.services)
        model.update { $0.traktClientID = "MIO" }
        XCTAssertEqual(builtIn.secrets.get(SecretKey.traktClientID), "MIO", "pegado a mano también va al Keychain")
        _ = try await builtIn.services.connectOrbital()
        XCTAssertEqual(Services.traktClientID(settings: builtIn.services.appSettings, secrets: builtIn.secrets, builtIn: "INCLUIDO"), "MIO")
        XCTAssertEqual(builtIn.services.appSettings.traktClientID, "MIO")
    }

    /// Sin consola y sin secreto: con el Client ID incluido en la app, «Conectar Trakt» da el código y conecta la sesión del
    /// iPhone. Trakt (PKCE) no pide secreto: no se manda `client_secret`.
    func testStandaloneLinkWithTheBuiltInClientIDAndNoSecret() async throws {
        let rig = try ServicesRig(builtInTraktClientID: "INCLUIDO")
        XCTAssertTrue(rig.services.appSettings.orbitalAddress.isEmpty, "sin tu Orbital")
        rig.http.json["https://api.trakt.tv/oauth/device/code"] = ["device_code": "DC", "user_code": "ABCD1234", "verification_url": "https://trakt.tv/activate", "interval": 1, "expires_in": 60]
        rig.http.json["https://api.trakt.tv/oauth/device/token"] = ["access_token": "AT", "refresh_token": "RT", "created_at": .double(rig.clock.now.timeIntervalSince1970), "expires_in": 604800]
        rig.http.json["https://api.trakt.tv/users/settings"] = ["user": ["username": "fer"]]
        let model = SettingsModel(rig.services)
        XCTAssertEqual(model.trakt, .unlinked)
        XCTAssertFalse(model.traktLinked)
        await model.linkTrakt()
        XCTAssertEqual(model.trakt, .linked("fer"))
        // Los avisos de estrenos se pueden prender: cuenta tu sesión, aunque el Client ID de Ajustes siga vacío (antes no).
        XCTAssertTrue(model.traktLinked)
        XCTAssertTrue(rig.services.appSettings.traktClientID.isEmpty)
        let body = try XCTUnwrap(JSON.parse(try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/oauth/device/token").first)))
        XCTAssertEqual(body["client_id"]?.string, "INCLUIDO")
        XCTAssertNil(body["client_secret"], "las apps nuevas de Trakt no tienen secreto")
        XCTAssertFalse(rig.http.calls.contains { $0.contains("legion") || $0.contains("/api/companion") }, "nada de la consola")
    }

    // MARK: ajustes y Trakt
    func testSettingsPersistAndTMDBKeyGoesToTheKeychain() async throws {
        let rig = try ServicesRig()
        let model = SettingsModel(rig.services)
        model.update { $0.uiLanguage = "en"; $0.audio = "en"; $0.subtitles = "es" }
        XCTAssertEqual(SettingsStore(rig.kv).value.uiLanguage, "en")
        model.setTMDBKey("  abc123 ")
        XCTAssertEqual(rig.secrets.get(SecretKey.tmdbKey), "abc123")
        XCTAssertTrue(model.hasTMDBKey)
        XCTAssertNil(rig.kv.data("tmdb_key"), "la clave no va en los ajustes normales")
    }

    func testTraktDeviceLinkFlow() async throws {
        let rig = try ServicesRig(traktClientID: "CID")
        XCTAssertEqual(SettingsModel(rig.services).trakt, .unlinked)
        rig.http.json["https://api.trakt.tv/oauth/device/code"] = ["device_code": "DC", "user_code": "ABCD1234", "verification_url": "https://trakt.tv/activate", "interval": 1, "expires_in": 60]
        rig.http.json["https://api.trakt.tv/oauth/device/token"] = ["access_token": "AT", "refresh_token": "RT", "created_at": .double(rig.clock.now.timeIntervalSince1970), "expires_in": 604800]
        rig.http.json["https://api.trakt.tv/users/settings"] = ["user": ["username": "fer"]]
        let model = SettingsModel(rig.services)
        var seenCode = false
        let sub = model.onChange { if case .linking(let code, _) = model.trakt, code == "ABCD1234" { seenCode = true } }
        await model.linkTrakt()
        _ = sub
        XCTAssertTrue(seenCode, "se enseñó el código para escribir en trakt.tv/activate")
        XCTAssertEqual(model.trakt, .linked("fer"))
        await model.unlinkTrakt()
        XCTAssertEqual(model.trakt, .unlinked)
    }

    func testWithoutATraktAppTheTraktSectionIsOff() async throws {
        let model = SettingsModel(try ServicesRig().services)
        XCTAssertEqual(model.trakt, .off)
    }

    // MARK: descargas
    func testDownloadsModelListsAndBuildsAnOfflinePlayRequest() async throws {
        let rig = try ServicesRig()
        let item = DownloadItem(id: "tt0386676|tt0386676:1:1", kind: "series", metaID: "tt0386676", videoID: "tt0386676:1:1", title: "La Oficina", originalTitle: "The Office",
                                subtitle: "T1 · E1", poster: nil, addon: "Torrentio", sourceIndex: 1, expectedBytes: 1000, relativePath: "tt0386676/tt0386676_1_1/video.mkv", createdAt: 1)
        var done = item; done.state = .done; done.writtenBytes = 1000; done.subtitleFiles = ["subs/es.srt"]
        let model = DownloadsModel(rig.services, freeSpace: { 12_345 })
        let run = Task { await model.run() }
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(model.freeBytes, 12_345)
        run.cancel()
        let request = await model.playRequest(done)
        XCTAssertEqual(request.originalTitle, "The Office")
        XCTAssertTrue(request.localFile?.path.hasSuffix("tt0386676/tt0386676_1_1/video.mkv") == true)
        XCTAssertEqual(request.localSubtitles.map(\.lastPathComponent), ["es.srt"])
        XCTAssertNotNil(request.meta)
    }

    /// Borrar desde la lista quita el renglón en el acto y no regresa con el siguiente aviso de la cola (la lista truena si
    /// el renglón que el deslizar ya quitó vuelve a aparecer).
    func testDeleteHidesTheRowRightAwayAndForGood() async throws {
        let rig = try ServicesRig()
        func movie(_ version: String) -> DownloadItem {
            DownloadItem(id: "tt1|tt1|\(version)", kind: "movie", metaID: "tt1", videoID: "tt1", title: "Peli", originalTitle: "Peli", subtitle: "",
                         poster: nil, addon: "Torrentio", sourceIndex: 1, expectedBytes: 1000, relativePath: "tt1/\(version)/video.mkv", createdAt: 1)
        }
        try await rig.services.downloads.enqueue(movie("a"), url: URL(string: "https://rd.example/a")!)
        try await rig.services.downloads.enqueue(movie("b"), url: URL(string: "https://rd.example/b")!)
        let model = DownloadsModel(rig.services, freeSpace: { 50_000_000_000 })
        let run = Task { await model.run() }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.items.count, 2)
        model.delete(["tt1|tt1|a"])
        XCTAssertEqual(model.items.map(\.id), ["tt1|tt1|b"], "se quita sin esperar al archivo")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(model.items.map(\.id), ["tt1|tt1|b"])
        let left = await rig.services.downloads.item("tt1|tt1|a")
        XCTAssertNil(left)
        run.cancel()
    }
}

@MainActor
final class CatalogAndSourcesTests: XCTestCase {
    func testCatalogShowsMoviesAndSeriesAndHandlesAFailedHalf() async throws {
        let rig = try ServicesRig(traktClientID: "cid")
        TraktPublicListsTests.trending(rig, series: nil, movies: [("tt1160419", "Dune", 2021), ("tt15239678", "Dune: Part Two", 2024)], limit: 50)
        let model = CatalogModel(rig.services)
        await model.load()
        XCTAssertFalse(model.movies.isEmpty)
        XCTAssertTrue(model.series.isEmpty)
        XCTAssertNil(model.error, "una mitad que falla no tumba la otra")
        XCTAssertTrue(model.movies.allSatisfy { $0.kind == "movie" && !$0.title.isEmpty })
        let none = CatalogModel(try ServicesRig().services)
        await none.load()
        XCTAssertNotNil(none.error)
    }

    /// Una sola lista (ordenada para ver) y en ella se marca la que más conviene guardar.
    func testOneSourceListMarksTheBestToSave() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://a.example/stream/movie/tt1.json"] = ["streams": [
            ["name": "T\n2160p [RD+]", "title": "Peli 2160p REMUX HDR\n👤 200 💾 40 GB 🇬🇧", "url": "https://rd.example/big"],
            ["name": "T\n1080p [RD+]", "title": "Peli 1080p WEB-DL x265\n👤 100 💾 2 GB 🇬🇧", "url": "https://rd.example/small"],
            ["name": "T\n1080p [RD+]", "title": "Peli 1080p HLS\n👤 100 💾 2 GB 🇬🇧", "url": "https://rd.example/list.m3u8"]]]
        rig.services.settings.update { $0.audio = "en"; $0.quality = "4K" }
        let model = SourcesModel(rig.services, kind: "movie", metaID: "tt1", videoID: "tt1")
        await model.load()
        XCTAssertTrue(model.rows[0].recommended)
        XCTAssertEqual(model.source(model.rows[0].id)?.playbackURL?.absoluteString, "https://rd.example/big", "para ver: la recomendada")
        let save = try XCTUnwrap(model.rows.first(where: \.bestToSave))
        XCTAssertEqual(model.source(save.id)?.playbackURL?.absoluteString, "https://rd.example/small", "para guardar: 1080p moderado")
        XCTAssertEqual(model.rows.filter(\.bestToSave).count, 1)
        XCTAssertFalse(model.rows.first { model.source($0.id)?.playbackURL?.pathExtension == "m3u8" }?.downloadable ?? true, "una lista HLS no se baja")
        XCTAssertTrue(model.rows.first { $0.sizeGB == 40 }?.heavy == true, "más de 5 GB: aviso con datos móviles")
        XCTAssertFalse(model.rows.contains { $0.headline.isEmpty })
    }

    func testChoosingASourceFromTheListPlaysThatOne() async throws {
        let rig = try Rig()
        rig.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [rig.stream("best"), rig.stream("other", size: "💾 3 GB", name: "T\n1080p")]]
        await rig.model.begin(rig.request())   // la recomendada: de ahí salen los números de fuente
        XCTAssertEqual(rig.engine.loads.first?.url.absoluteString, "https://rd.example/best.mkv")
        let other = try XCTUnwrap(rig.model.sourceChoices.first { $0.playbackURL?.absoluteString.contains("other") == true })
        let second = try Rig()
        second.http.json = rig.http.json
        var chosen = second.request(); chosen.sourceIndex = other.index
        await second.model.begin(chosen)
        XCTAssertEqual(second.engine.loads.first?.url.absoluteString, "https://rd.example/other.mkv")
    }

    func testUnairedEpisodesKnowTheirDate() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertNotNil(TitleModel.airDate("2030-01-01T02:00:00.000Z", now: now), "todavía no sale")
        XCTAssertNil(TitleModel.airDate("2020-01-01T02:00:00.000Z", now: now), "ya salió")
        XCTAssertNotNil(TitleModel.airDate("2030-01-01T02:00:00Z", now: now), "sin milisegundos también")
        XCTAssertNil(TitleModel.airDate(nil, now: now))
    }

    func testDownloadSpeedAndTimeLeft() throws {
        let rig = try ServicesRig()
        let model = DownloadsModel(rig.services, freeSpace: { 0 })
        var d = DownloadItem(id: "tt1|tt1", kind: "movie", metaID: "tt1", videoID: "tt1", title: "A", originalTitle: "A", subtitle: "", poster: nil,
                             addon: "", sourceIndex: 0, expectedBytes: 100_000_000, relativePath: "", createdAt: 0)
        d.state = .downloading
        let t0 = Date(timeIntervalSince1970: 1000)
        d.writtenBytes = 10_000_000; model.measure([d], at: t0)
        XCTAssertNil(model.speeds[d.id], "con una sola muestra todavía no hay velocidad")
        d.writtenBytes = 30_000_000; model.measure([d], at: t0.addingTimeInterval(2))
        XCTAssertEqual(model.speeds[d.id] ?? 0, 10_000_000, accuracy: 1, "20 MB en 2 s")
        XCTAssertEqual(model.secondsLeft(d) ?? 0, 7, accuracy: 0.01, "70 MB a 10 MB/s")
        d.state = .paused; model.measure([d], at: t0.addingTimeInterval(3))
        XCTAssertNil(model.speeds[d.id], "en pausa no hay velocidad")
    }

    func testReadyDownloadsAreGroupedByTitleInArrivalOrder() {
        func item(_ meta: String, _ video: String, bytes: Int64) -> DownloadItem {
            var d = DownloadItem(id: "\(meta)|\(video)", kind: "series", metaID: meta, videoID: video, title: meta, originalTitle: meta, subtitle: "", poster: nil,
                                 addon: "", sourceIndex: 0, expectedBytes: nil, relativePath: "", createdAt: 0)
            d.writtenBytes = bytes
            return d
        }
        let groups = DownloadGroup.group([item("tt2", "a", bytes: 1), item("tt1", "b", bytes: 2), item("tt2", "c", bytes: 3)])
        XCTAssertEqual(groups.map(\.metaID), ["tt2", "tt1"])
        XCTAssertEqual(groups.first?.items.map(\.videoID), ["a", "c"])
        let episodes = DownloadGroup.group([item("tt9", "tt9:2:1", bytes: 1), item("tt9", "tt9:1:3", bytes: 1), item("tt9", "tt9:1:1", bytes: 1)])
        XCTAssertEqual(episodes.first?.items.map(\.videoID), ["tt9:1:1", "tt9:1:3", "tt9:2:1"], "en orden de temporada y episodio")
        XCTAssertEqual(groups.first?.bytes, 4)
        let seasons = try! XCTUnwrap(episodes.first).seasons
        XCTAssertEqual(seasons.map(\.number), [1, 2], "por temporada, no archivo por archivo")
        XCTAssertEqual(seasons.map { $0.items.count }, [2, 1])
        XCTAssertEqual(seasons.first?.bytes, 2)
    }
}
