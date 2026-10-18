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
    func testHomeShowsContinueWatchingMyListAndFallsBackToTheLastCopyOffline() async throws {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": [
            ["_id": "tt0386676", "name": "The Office", "type": "series", "removed": true, "temp": true, "state": ["video_id": "tt0386676:2:5", "timeOffset": 600_000, "duration": 1_320_000, "lastWatched": "2025-01-02T00:00:00.000Z"]],
            ["_id": "tt1160419", "name": "Dune", "type": "movie", "removed": false, "temp": false, "state": [:]],
            ["_id": "tt9", "name": "Abierta un momento", "type": "movie", "removed": true, "temp": true, "state": ["video_id": "tt9", "timeOffset": 1000, "duration": 6_000_000]]]]
        let home = HomeModel(rig.services)
        await home.refresh()
        XCTAssertEqual(home.continueWatching.map(\.metaID), ["tt0386676"])
        XCTAssertEqual(home.continueWatching.first?.season, 2); XCTAssertEqual(home.continueWatching.first?.episode, 5)
        XCTAssertEqual(home.continueWatching.first?.timeLeft, "quedan 12 min")
        XCTAssertEqual(home.continueWatching.first?.progress ?? 0, 600.0 / 1320.0, accuracy: 0.001)
        XCTAssertEqual(home.myList.map(\.metaID), ["tt1160419"])
        XCTAssertFalse(home.offline)
        // Sin red: se enseña lo último que se vio, con aviso.
        rig.http.json[stremioGet] = nil
        rig.http.statuses[stremioGet] = 500
        let again = HomeModel(rig.services)
        XCTAssertEqual(again.continueWatching.map(\.metaID), ["tt0386676"], "la copia guardada se ve al instante")
        await again.refresh()
        XCTAssertTrue(again.offline)
        XCTAssertEqual(again.continueWatching.map(\.metaID), ["tt0386676"])
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
        rig.http.json[stremioGet] = ["result": [["_id": "tt0386676", "name": "The Office", "type": "series", "state": ["video_id": "tt0386676:1:1", "timeOffset": 500_000, "duration": 1_320_000]]]]
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

    // MARK: ficha
    func titleRig() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": [["_id": "tt0386676", "name": "The Office", "type": "series", "removed": false, "temp": false,
            "state": ["video_id": "tt0386676:1:3", "timeOffset": 660_000, "duration": 1_320_000,
                      "watched": .string(StremioLibrary.encodeWatched(["tt0386676:1:1", "tt0386676:1:2"], videoIDs: CinemetaParsing.seasonVideoIDs(try Fixtures.json("cinemeta/meta_series_tt0386676.json"))) ?? "")]]]]
        rig.http.json[stremioPut] = ["result": ["success": true]]
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

    /// CEN-37: con la consola conectada la ficha toma su sinopsis (en español) y si el logo es oscuro; sin consola, lo de Cinemeta.
    func testTitleTakesTheConsolesOverviewWhenConnected() async throws {
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
        XCTAssertTrue(title.logoIsDark)

        rig.http.json["https://tv.example/api/foryou/details?key=video:tt0386676&kind=series"] = ["overview": ""]
        let other = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await other.load(); await other.loadConsoleDetails()
        XCTAssertEqual(other.overview, other.info.description, "una sinopsis vacía no tapa la de Cinemeta")
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

    func testMyListToggleWritesOnlyLibraryFlagsToStremioAndRollsBackOnError() async throws {
        let rig = try titleRig()
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        await title.toggleLibrary()
        XCTAssertFalse(title.inLibrary)
        let sent = try XCTUnwrap(rig.http.bodies(stremioPut).last.flatMap(JSON.parse))
        let item = try XCTUnwrap(sent["changes"]?.array?.first)
        XCTAssertEqual(item["removed"]?.bool, true)
        XCTAssertEqual(item["state"]?["video_id"]?.string, "tt0386676:1:3", "el avance no se toca")
        rig.http.statuses[stremioPut] = 500
        await title.toggleLibrary()
        XCTAssertFalse(title.inLibrary, "falló: vuelve a como estaba")
        XCTAssertNotNil(title.message)
    }

    func testTraktWatchlistToggle() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json[stremioGet] = ["result": []]
        rig.http.json["https://api.trakt.tv/sync/watchlist?extended=full&sort_by=added&sort_how=desc"] = []
        rig.http.json["https://api.trakt.tv/sync/watchlist"] = [:]
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        XCTAssertTrue(title.traktAvailable)
        XCTAssertFalse(title.inWatchlist)
        await title.toggleWatchlist()
        XCTAssertTrue(title.inWatchlist)
        let sent = try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/sync/watchlist").first.flatMap(JSON.parse))
        XCTAssertEqual(sent["shows"]?.array?.first?["ids"]?["imdb"]?.string, "tt0386676")
    }

    func testMarkingWatchedUpdatesTheBitfieldAndMovesToNext() async throws {
        let rig = try ServicesRig()
        rig.http.json[stremioGet] = ["result": []]
        rig.http.json[stremioPut] = ["result": ["success": true]]
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676")
        await title.load()
        await title.markWatched("tt0386676:1:1")
        let item = try XCTUnwrap(rig.http.bodies(stremioPut).last.flatMap(JSON.parse)?["changes"]?.array?.first)
        let ids = CinemetaParsing.seasonVideoIDs(try Fixtures.json("cinemeta/meta_series_tt0386676.json"))
        XCTAssertEqual(StremioLibrary.parseWatched(item["state"]?["watched"]?.string, videoIDs: ids), ["tt0386676:1:1"])
        XCTAssertEqual(item["name"]?.string, "The Office", "con el título original")
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

    func testParaTiWithoutTraktOrTMDBShowsWhatIsPopularOnStremio() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://v3-cinemeta.strem.io/catalog/series/top.json"] = ["metas": [
            ["id": "tt0386676", "type": "series", "name": "The Office", "poster": "https://p/poster/small/1.jpg", "background": "https://b/1.jpg", "releaseInfo": "2005–2013"],
            ["id": "kitsu:1", "type": "series", "name": "Sin IMDb", "poster": "https://p/2.jpg"]]]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top.json"] = ["metas": [
            ["id": "tt1160419", "type": "movie", "name": "Dune", "poster": "https://p/3.jpg", "releaseInfo": "2021", "runtime": "155 min"]]]
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertTrue(model.isGeneric)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.mosaic.map(\.imdb), ["tt0386676", "tt1160419"], "series y películas alternadas; sin IMDb no se puede ver")
        XCTAssertEqual(model.mosaic.first?.poster, "https://p/poster/medium/1.jpg")
        XCTAssertEqual(model.mosaic.first?.wide, "https://b/1.jpg")
        XCTAssertEqual(model.mosaic.last?.year, 2021); XCTAssertEqual(model.mosaic.last?.runtime, 155)
        XCTAssertEqual(model.mosaic.allSatisfy { $0.reason == .popular }, true)
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
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        // /api/foryou no se registra: la consola de mentira contesta 404, como una versión anterior sin esta ruta.
        rig.http.json["https://v3-cinemeta.strem.io/catalog/series/top.json"] = ["metas": [
            ["id": "tt0386676", "type": "series", "name": "The Office", "poster": "https://p/poster/small/1.jpg", "background": "https://b/1.jpg", "releaseInfo": "2005–2013"]]]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top.json"] = ["metas": [
            ["id": "tt1160419", "type": "movie", "name": "Dune", "poster": "https://p/3.jpg", "releaseInfo": "2021", "runtime": "155 min"]]]
        let model = ParaTiModel(rig.services)
        await model.load()
        XCTAssertEqual(model.source, .phone)
        XCTAssertTrue(model.isGeneric)
        XCTAssertEqual(model.mosaic.map(\.imdb), ["tt0386676", "tt1160419"])
        XCTAssertNil(model.error)
    }

    /// El iPhone calcula Para ti él mismo aunque tu Orbital esté conectada (no depende de que conteste): trae sus propias listas
    /// con puesto (Top 10 de Netflix, tendencias de JustWatch) y solo le avisa a la consola lo que marcas «No me interesa».
    func testParaTiIsComputedOnThePhoneEvenWithYourOrbitalConnected() async throws {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        rig.http.json["https://tv.example/api/foryou/dismiss"] = ["ok": true]
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top.json"] = ["metas": [
            ["id": "tt1160419", "type": "movie", "name": "Dune", "poster": "https://p/3.jpg", "releaseInfo": "2021"]]]
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
    /// carrusel de Inicio no cambiaban hasta reabrir la app.
    @MainActor func testChangingASettingTellsTheApp() throws {
        let rig = try ServicesRig()
        let model = SettingsModel(rig.services)
        var told = 0
        let subscription = rig.services.onChange { told += 1 }
        model.update { $0.appearance = "light" }
        model.update { $0.homeDeck = "fan" }
        XCTAssertEqual(told, 2)
        XCTAssertEqual(rig.services.appSettings.homeDeck, "fan")
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

    func testConnectingTheTVBringsItsTraktSessionSoThereIsNothingToLink() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://legion.example/api/ping"] = ["ok": true]
        rig.http.json["https://legion.example/api/companion"] = ["tmdb_key": "k", "trakt_client_id": "cid", "region": "MX",
                                                                 "trakt_session": ["access_token": "AT", "expires_at": 1_760_100_000]]
        let got = try await rig.services.connectOrbital(address: "https://legion.example", token: "secreto")
        XCTAssertEqual(got, ["TMDB", "Trakt"])
        XCTAssertEqual(rig.services.trakt?.linked, true, "Trakt queda conectado con la sesión de la consola")
        XCTAssertEqual(rig.services.trakt?.borrowed, true)
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
}

@MainActor
final class CatalogAndSourcesTests: XCTestCase {
    func testCatalogShowsMoviesAndSeriesAndHandlesAFailedHalf() async throws {
        let rig = try ServicesRig()
        let movies = try Fixtures.json("cinemeta/search_movie_dune.json")
        rig.http.json["https://v3-cinemeta.strem.io/catalog/movie/top.json"] = ["metas": movies]
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

    func testSourcesAreOrderedDifferentlyForWatchingAndDownloading() async throws {
        let rig = try ServicesRig()
        rig.http.json["https://a.example/stream/movie/tt1.json"] = ["streams": [
            ["name": "T\n2160p [RD+]", "title": "Peli 2160p REMUX HDR\n👤 200 💾 40 GB 🇬🇧", "url": "https://rd.example/big"],
            ["name": "T\n1080p [RD+]", "title": "Peli 1080p WEB-DL x265\n👤 100 💾 2 GB 🇬🇧", "url": "https://rd.example/small"]]]
        rig.services.settings.update { $0.audio = "en"; $0.quality = "4K" }
        let model = SourcesModel(rig.services, kind: "movie", metaID: "tt1", videoID: "tt1")
        await model.load(.watch)
        XCTAssertTrue(model.rows[0].recommended)
        XCTAssertEqual(model.rows[0].sizeGB ?? 0, 40, accuracy: 0.01)
        XCTAssertEqual(model.source(model.rows[0].id)?.playbackURL?.absoluteString, "https://rd.example/big")
        await model.load(.download)
        XCTAssertEqual(model.source(model.rows[0].id)?.playbackURL?.absoluteString, "https://rd.example/small", "para guardar: 1080p moderado primero")
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
