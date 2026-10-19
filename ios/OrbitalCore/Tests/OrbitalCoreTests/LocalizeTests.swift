import XCTest
@testable import OrbitalCore

// En macOS, ApplicationServices también exporta un `Translation` (Linux no lo tiene).
private typealias Translation = OrbitalCore.Translation

final class LocalizeTests: XCTestCase {
    let golden = try! Fixtures.json("ios/localize.json")
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")

    func testApplyMatchesPython() throws {
        let a = try XCTUnwrap(golden["apply"])
        var episodes: [Translation.Key: Translation.EpisodeText] = [:]
        for e in try XCTUnwrap(a["found"]?.array) {
            episodes[.init(season: e["season"]!.intValue!, episode: e["episode"]!.intValue!)] = .init(name: e["name"]!.string!, overview: e["overview"]!.string!)
        }
        let found = Translation(title: a["title"]!.string!, overview: a["overview"]!.string!, genres: a["genres"]!.array!.compactMap(\.string), episodes: episodes)
        XCTAssertEqual(Localizer.apply(series, found), a["result"])
        XCTAssertEqual(Localizer.apply(series, Translation()), a["partial"])
    }

    func testOriginalTitleIsKeptWhenNothingTranslates() {
        XCTAssertEqual(Localizer.apply(series, Translation())["name"], series["name"])
    }

    func testLanguagesMatchPython() throws {
        for (input, expected) in try XCTUnwrap(golden["languages"]?.object) {
            let arg: String? = input == "None" ? nil : input
            XCTAssertEqual(Localizer.tmdbLanguage(arg), expected.string, input)
        }
    }

    func testPlatformsMatchPython() throws {
        let rows: JSON = [["provider_id": 8, "provider_name": "Netflix", "logo_path": "/n.jpg"], ["provider_id": 337, "provider_name": "Disney Plus", "logo_path": "/d.jpg"],
                          ["provider_id": 1899, "provider_name": "Max", "logo_path": "/m.jpg"], ["provider_id": 9, "provider_name": "Otro"], "raro", ["provider_name": "Netflix"]]
        let got = Tmdb.matchPlatforms(rows)
        for (brand, info) in try XCTUnwrap(golden["platforms"]?.object) {
            XCTAssertEqual(got[brand]?.id, info["id"]?.intValue, brand)
            XCTAssertEqual(got[brand]?.logo, info["logo"]?.string, brand)
        }
        XCTAssertEqual(got.count, golden["platforms"]?.object?.count)
    }

    func testMissingMexicanOverviewFallsBackToSpainBeforeEnglish() async throws {
        let http = FakeHTTP()
        http.json["https://api.themoviedb.org/3/find/tt0000001?external_source=imdb_id&api_key=K&language=es-MX"] = ["movie_results": [["id": 7]]]
        http.json["https://api.themoviedb.org/3/movie/7?language=es-MX&api_key=K"] = ["title": "Dune", "overview": ""]
        http.json["https://api.themoviedb.org/3/movie/7/translations?api_key=K&language=es-MX"] = ["translations": [
            ["iso_639_1": "en", "data": ["overview": "English text."]],
            ["iso_639_1": "es", "iso_3166_1": "ES", "data": ["title": "Dune: Parte uno", "overview": "Texto en español."]]]]
        let found = try await Tmdb(http: http, key: "K").translation(kind: "movie", tmdbID: 7, language: "es-MX")
        XCTAssertEqual(found.overview, "Texto en español.")
        XCTAssertEqual(found.title, "Dune: Parte uno")
    }

    func testTranslationFetchesEpisodesAndLocalizes() async throws {
        let http = FakeHTTP()
        http.json["https://api.themoviedb.org/3/find/tt0386676?external_source=imdb_id&api_key=K&language=es-MX"] = ["tv_results": [["id": 2316]]]
        http.json["https://api.themoviedb.org/3/tv/2316?language=es-MX&api_key=K"] = ["name": "La Oficina", "overview": "Un falso documental.", "genres": [["name": "Comedia"]], "seasons": [["season_number": 1]]]
        http.json["https://api.themoviedb.org/3/tv/2316?language=es-MX&append_to_response=season/1&api_key=K"] = ["season/1": ["episodes": [["episode_number": 1, "name": "Piloto", "overview": "Michael presenta."]]]]
        let localizer = Localizer(tmdb: Tmdb(http: http, key: "K"), language: { "es" })
        let meta = await localizer.meta(kind: "series", meta: series)
        XCTAssertEqual(meta["name"]?.string, "La Oficina")
        XCTAssertEqual(series["name"]?.string?.isEmpty, false)
        let first = meta["videos"]?.array?.first { $0["season"]?.intValue == 1 && $0["episode"]?.intValue == 1 }
        XCTAssertEqual(first?["name"]?.string, "Piloto")
    }

    func testEnglishAndMissingKeyDoNotTouchTheMeta() async {
        let http = FakeHTTP()
        let english = Localizer(tmdb: Tmdb(http: http, key: "K"), language: { "en" })
        let noKey = Localizer(tmdb: Tmdb(http: http, key: ""), language: { "es" })
        let a = await english.meta(kind: "series", meta: series), b = await noKey.meta(kind: "series", meta: series)
        XCTAssertEqual(a, series); XCTAssertEqual(b, series)
        XCTAssertTrue(http.calls.isEmpty)
    }

    func testTMDBFailureFallsBackToOriginal() async {
        let http = FakeHTTP(); http.fail = true
        let localizer = Localizer(tmdb: Tmdb(http: http, key: "K"), language: { "es" })
        let meta = await localizer.meta(kind: "series", meta: series)
        XCTAssertEqual(meta, series)
    }
}
