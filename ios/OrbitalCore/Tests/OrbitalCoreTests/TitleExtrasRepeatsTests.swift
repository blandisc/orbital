import XCTest
@testable import OrbitalCore

/// Revisión del 11 nov: la ficha repetía datos. La misma película salía en «La saga» y en «Más como esto», y el idioma decía
/// «Idiomas: Inglés» (los que se hablan) en vez del original.
final class TitleExtrasRepeatsTests: XCTestCase {
    func testMoreLikeThisSkipsTheSagaAndTheTitleItself() {
        var x = TitleExtras(tmdbID: 438631)
        x.collection = ("Dune", [TmdbTitle(tmdbID: 438631, kind: "movie", title: "Dune"), TmdbTitle(tmdbID: 693134, kind: "movie", title: "Dune: Parte dos")])
        x.recommendations = [TmdbTitle(tmdbID: 693134, kind: "movie", title: "Dune: Parte dos"), TmdbTitle(tmdbID: 438631, kind: "movie", title: "Dune"),
                             TmdbTitle(tmdbID: 157336, kind: "movie", title: "Interestelar")]
        XCTAssertEqual(x.withoutRepeats(selfID: 438631).recommendations.map { $0.tmdbID }, [157336])
        var alone = TitleExtras(tmdbID: 1)
        alone.recommendations = [TmdbTitle(tmdbID: 1, kind: "movie", title: "Ella misma"), TmdbTitle(tmdbID: 2, kind: "movie", title: "Otra")]
        XCTAssertEqual(alone.withoutRepeats(selfID: 1).recommendations.map { $0.tmdbID }, [2], "sin saga, solo se quita ella misma")
    }

    func testOriginalLanguageComesFromTMDB() {
        let raw: JSON = ["original_language": "ko", "spoken_languages": [["iso_639_1": "en"], ["iso_639_1": "ko"]]]
        let x = Tmdb.parseExtras(raw, kind: "movie", region: "MX")
        XCTAssertEqual(x.originalLanguage, "ko")
        XCTAssertEqual(x.languages, ["en", "ko"])
    }
}
