import XCTest
@testable import OrbitalCore

// En macOS, ApplicationServices también exporta un `Translation` (Linux no lo tiene).
private typealias Translation = OrbitalCore.Translation

/// R4 · «Idioma colado»: los títulos y sinopsis de episodio que solo existen en inglés (Cinemeta) dicen de qué idioma son, y a
/// TMDB se le pide primero el español de México y luego el del mismo idioma de otro país.
final class ForeignTextMarkTests: XCTestCase {
    let meta: JSON = ["id": "tt0096697", "name": "The Simpsons", "videos": [
        ["id": "tt0096697:11:14", "season": 11, "episode": 14, "name": "Saddlesore Galactica", "overview": "The family visits the state fair."],
        ["id": "tt0096697:1:1", "season": 1, "episode": 1, "name": "Simpsons Roasting on an Open Fire", "overview": "Christmas special."],
        ["id": "tt0096697:1:2", "season": 1, "episode": 2, "name": "Episode 2", "overview": ""],
    ]]

    private func video(_ m: JSON, _ id: String) -> JSON? { m["videos"]?.array?.first { $0["id"]?.string == id } }

    func testUntranslatedEpisodeTextCarriesItsLanguage() {
        let found = Translation(episodes: [.init(season: 1, episode: 1): .init(name: "Especial de Navidad", overview: "")])
        let marked = Localizer.markUntranslated(original: meta, localized: Localizer.apply(meta, found))
        // Sin traducción: nombre y sinopsis en inglés, marcados.
        XCTAssertEqual(video(marked, "tt0096697:11:14")?[Localizer.nameLanguageKey]?.string, "en")
        XCTAssertEqual(video(marked, "tt0096697:11:14")?[Localizer.overviewLanguageKey]?.string, "en")
        // El nombre sí se tradujo (sin marca); la sinopsis no.
        XCTAssertNil(video(marked, "tt0096697:1:1")?[Localizer.nameLanguageKey])
        XCTAssertEqual(video(marked, "tt0096697:1:1")?[Localizer.overviewLanguageKey]?.string, "en")
        // Un nombre de relleno no es «inglés»: la app ya lo dice en tu idioma («Episodio 2»).
        XCTAssertNil(video(marked, "tt0096697:1:2")?[Localizer.nameLanguageKey])
    }

    func testParsedEpisodeKnowsItsLanguage() {
        let marked = Localizer.markUntranslated(original: meta, localized: meta)
        let episodes = CinemetaParsing.seasons(marked).flatMap(\.episodes)
        let saddlesore = episodes.first { $0.id == "tt0096697:11:14" }
        XCTAssertEqual(saddlesore?.titleLanguage, "en")
        XCTAssertEqual(saddlesore?.overviewLanguage, "en")
        XCTAssertNil(episodes.first { $0.id == "tt0096697:1:2" }?.titleLanguage)
        // Sin marcas (la app en inglés): nada.
        XCTAssertNil(CinemetaParsing.seasons(meta).flatMap(\.episodes).first?.titleLanguage)
    }

    func testEnglishAppMarksNothing() async {
        let english = Localizer(tmdb: Tmdb(http: FakeHTTP(), key: "K"), language: { "en" })
        let out = await english.meta(kind: "series", meta: meta)
        XCTAssertEqual(out, meta)
    }

    func testMissingMexicanEpisodeFallsBackToSameLanguageBeforeEnglish() async throws {
        let http = FakeHTTP()
        http.json["https://api.themoviedb.org/3/tv/456?language=es-MX&api_key=K"] = ["name": "Los Simpson", "overview": "Una familia.", "seasons": [["season_number": 11]]]
        http.json["https://api.themoviedb.org/3/tv/456?language=es-MX&append_to_response=season/11&api_key=K"] = ["season/11": ["episodes": [
            ["episode_number": 14, "name": "Episodio 14", "overview": ""], ["episode_number": 15, "name": "Trillizos", "overview": "Ya traducido."]]]]
        http.json["https://api.themoviedb.org/3/tv/456?language=es&append_to_response=season/11&api_key=K"] = ["season/11": ["episodes": [
            ["episode_number": 14, "name": "Galáctica de la silla de montar", "overview": "La familia va a la feria."],
            ["episode_number": 15, "name": "Otro nombre", "overview": "Otro texto."]]]]
        let found = try await Tmdb(http: http, key: "K").translation(kind: "series", tmdbID: 456, language: "es-MX", episodes: true)
        XCTAssertEqual(found.episodes[.init(season: 11, episode: 14)]?.name, "Galáctica de la silla de montar")
        XCTAssertEqual(found.episodes[.init(season: 11, episode: 14)]?.overview, "La familia va a la feria.")
        // Lo que ya estaba en es-MX no se cambia por el de otro país.
        XCTAssertEqual(found.episodes[.init(season: 11, episode: 15)]?.name, "Trillizos")
        XCTAssertEqual(found.episodes[.init(season: 11, episode: 15)]?.overview, "Ya traducido.")
        XCTAssertEqual(Tmdb.baseLanguage("es-MX"), "es")
        XCTAssertNil(Tmdb.baseLanguage("es"))
    }
}
