import XCTest
@testable import OrbitalCore
@testable import OrbitalAddons

/// Lo que encontró el análisis de fondo con la TV (3 nov: «análisis de fondo… para que no encuentre yo más errores»), pieza
/// por pieza. Los escenarios completos están en `tests/fixtures/rd-scenarios` (OrbitalModelsTests › RDScenarioTests).
final class AnalisisDeFondoTests: XCTestCase {
    // MARK: «¿Otro episodio?»
    /// Torrentio pone en «Breaking Bad» T1 E1 un paquete latino de la temporada 4 («T4 … 04 - CAPITULO 01.mkv»).
    func testAReleaseOfAnotherSeasonIsMarked() {
        XCTAssertTrue(Streams.otherEpisode(release: "Breaking Bad T4 720p Dual Latino-Ingles", filename: "04 - CAPITULO 01.mkv", season: 1))
        XCTAssertTrue(Streams.otherEpisode(release: "Show Season 3 1080p", filename: "", season: 1))
        XCTAssertTrue(Streams.otherEpisode(release: "Pack", filename: "Show.S02E01.1080p.mkv", season: 1), "el archivo manda")
    }

    func testThisSeasonPacksAndRangesAreNotMarked() {
        XCTAssertFalse(Streams.otherEpisode(release: "Breaking Bad (S01)(2008)(1080p)", filename: "Breaking Bad - S01E01_Pilotní díl.mkv", season: 1))
        XCTAssertFalse(Streams.otherEpisode(release: "Breaking Bad S01-S05 Seasons 1-5 Complete 1080p", filename: "", season: 1))
        XCTAssertFalse(Streams.otherEpisode(release: "Во все тяжкие / Breaking Bad [S01-05] (2008-2013) BDRip 1080p", filename: "", season: 2))
        XCTAssertFalse(Streams.otherEpisode(release: "Breaking Bad 2008 - 1ª Temporada Completa [4k]", filename: "", season: 1))
        XCTAssertFalse(Streams.otherEpisode(release: "Breaking.Bad.S01.1080p.BluRay.x265-RARBG", filename: "Breaking.Bad.S01E01.1080p.BluRay.x265-RARBG.mp4", season: 1))
        XCTAssertFalse(Streams.otherEpisode(release: "Show 1080p x264", filename: "Show 720x480.mkv", season: 1), "ni «x264» ni «720x480» son episodios")
    }

    func testOnlyEpisodesWithASeasonAreChecked() {
        XCTAssertEqual(Streams.season(of: "tt0903747:4:1"), 4)
        XCTAssertNil(Streams.season(of: "kitsu:1:5"), "Kitsu va de corrido")
        XCTAssertNil(Streams.season(of: "tt0061752"))
        var s = Streams.parse(["name": "[RD download] Torrentio\n720p", "title": "Breaking Bad T4 720p Dual Latino-Ingles\n👤 7 💾 322 MB",
                               "url": "https://x.example/a.mkv"], addon: "Torrentio", transportURL: "", index: 0)
        Streams.markOtherEpisode(&s, videoID: "tt0903747:1:1", filename: "04 - CAPITULO 01.mkv")
        XCTAssertTrue(s.tags.contains(Streams.otherEpisodeTag))
        XCTAssertLessThan(Streams.score(s, prefs: Preferences(audio: "es", quality: "1080p", spanish: "es-419"), kind: "series"), -1000, "nunca la recomendada")
    }

    // MARK: 1440p
    func test1440pIsRecognizedAndCountsLike1080p() {
        let s = Streams.parse(["name": "Torrentio\n1440p", "title": "[luchotaq] COWBOY BEBOP 1440p - (AUDIO ENG - LAT - JPN)", "url": "https://x.example/a.mkv"],
                              addon: "Torrentio", transportURL: "", index: 0)
        XCTAssertEqual(s.resolution, "1440p")
        var hd = s; hd.resolution = "1080p"
        let prefs = Preferences(audio: "es", quality: "1080p", spanish: "es-419")
        XCTAssertEqual(Streams.score(s, prefs: prefs, kind: "series"), Streams.score(hd, prefs: prefs, kind: "series"))
    }

    // MARK: el título de un video que no es de IMDb
    func testTheTitleOfAKitsuVideoKeepsItsNumber() {
        XCTAssertEqual(StreamFinder.metaID(of: "kitsu:1:5"), "kitsu:1")
        XCTAssertEqual(StreamFinder.metaID(of: "tt0903747:1:2"), "tt0903747")
        XCTAssertEqual(StreamFinder.metaID(of: "tt0061752"), "tt0061752")
        XCTAssertEqual(StreamFinder.metaID(of: "tmdb:603"), "tmdb:603")
    }

    // MARK: el título en español
    /// Sin sinopsis en es-MX, la de España no le cambia el nombre: «Eterno resplandor…», no «¡Olvídate de mí!».
    func testTheSpainOverviewDoesNotReplaceTheLatinTitle() async throws {
        let http = FakeHTTP()
        http.json["https://api.themoviedb.org/3/movie/38?language=es-MX&api_key=K"] = [
            "title": "Eterno resplandor de una mente sin recuerdos", "original_title": "Eternal Sunshine of the Spotless Mind", "original_language": "en", "overview": ""]
        http.json["https://api.themoviedb.org/3/movie/38/translations?api_key=K&language=es-MX"] = ["translations": [
            ["iso_639_1": "es", "iso_3166_1": "ES", "data": ["title": "¡Olvídate de mí!", "overview": "Joel y Clementine…"]]]]
        http.json["https://api.themoviedb.org/3/movie/39?language=es-MX&api_key=K"] = [
            "title": "Untranslated", "original_title": "Untranslated", "original_language": "en", "overview": ""]
        http.json["https://api.themoviedb.org/3/movie/39/translations?api_key=K&language=es-MX"] = ["translations": [
            ["iso_639_1": "es", "iso_3166_1": "ES", "data": ["title": "Sin traducir", "overview": "Algo…"]]]]
        let tmdb = Tmdb(http: http, key: "K")
        let latin = try await tmdb.translation(kind: "movie", tmdbID: 38, language: "es-MX")
        XCTAssertEqual(latin.title, "Eterno resplandor de una mente sin recuerdos")
        XCTAssertEqual(latin.overview, "Joel y Clementine…", "la sinopsis sí, de España")
        let missing = try await tmdb.translation(kind: "movie", tmdbID: 39, language: "es-MX")
        XCTAssertEqual(missing.title, "Sin traducir", "sin título en es-MX (TMDB da el original), el de España")
    }
}
