import XCTest
@testable import OrbitalCore

/// Fernando, 5 nov: «se tardan mucho en cargar las imágenes en búsqueda, muchos espacios vacíos en gris». Uno de cada cuatro
/// resultados de Cinemeta apunta a un póster que metahub no tiene (307 → 404): de reserva va el de TMDB, que llega en la
/// misma consulta del nombre en tu idioma.
final class SearchPosterFallbackTests: XCTestCase {
    func testTheTranslationBringsTheTmdbPosterAndRemembersIt() async throws {
        let http = FakeHTTP()
        http.json["https://api.themoviedb.org/3/movie/7?language=es-MX&api_key=K"] = [
            "title": "La dama", "original_title": "The Lady", "original_language": "en", "overview": "…", "poster_path": "/abc.jpg"]
        let found = try await Tmdb(http: http, key: "K").translation(kind: "movie", tmdbID: 7, language: "es-MX")
        XCTAssertEqual(found.poster, "https://image.tmdb.org/t/p/w342/abc.jpg")
        XCTAssertEqual(Localizer.apply(["name": "The Lady"], found)[Localizer.posterKey]?.string, found.poster)
        XCTAssertFalse(Translation(poster: "x").isEmpty, "solo con póster también se recuerda")
    }
}
