import XCTest
@testable import OrbitalCore

/// Calificar como en Trakt: 5 estrellas con medias en la app, entero 1…10 en Trakt; leer, escribir, quitar y mandar lo
/// pendiente cuando vuelve la conexión.
final class TraktRatingsTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func makeTrakt(_ http: FakeHTTP, clock: Clock = Clock()) -> Trakt {
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 7 * 86400)}"#)
        return Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
    }

    func testLaEscalaVaDeMediaEstrellaAUnPunto() {
        XCTAssertEqual(RatingScale.trakt(stars: 4.5), 9)
        XCTAssertEqual(RatingScale.trakt(stars: 0.5), 1)
        XCTAssertEqual(RatingScale.trakt(stars: 5), 10)
        XCTAssertEqual(RatingScale.trakt(stars: 0), 1, "nunca baja de 1: Trakt no acepta 0")
        XCTAssertEqual(RatingScale.stars(trakt: 7), 3.5)
        XCTAssertEqual(RatingScale.snap(2.1), 2.5, "el dedo en la mitad izquierda de la tercera estrella es 2.5")
        XCTAssertEqual(RatingScale.snap(2.6), 3)
        XCTAssertEqual(RatingScale.snap(0.01), 0.5)
        XCTAssertEqual(RatingScale.snap(9), 5)
    }

    func testLeeTusCalificacionesDePeliculasYSeries() async throws {
        let http = FakeHTTP()
        http.json["\(api)/sync/ratings/movies"] = [["rating": 9, "type": "movie", "movie": ["title": "Parásitos", "ids": ["imdb": "tt6751668"]]],
                                                   ["rating": 0, "type": "movie", "movie": ["title": "Rara", "ids": ["imdb": "tt1"]]]]
        http.json["\(api)/sync/ratings/shows"] = [["rating": 8, "type": "show", "show": ["title": "Mad Men", "ids": ["imdb": "tt0804503"]]]]
        let found = try await makeTrakt(http).myRatings()
        XCTAssertEqual(found, ["tt6751668": 9, "tt0804503": 8], "lo que no está entre 1 y 10 se ignora")
    }

    func testCalificarYQuitarMandanElCuerpoDeTrakt() async throws {
        let http = FakeHTTP()
        http.json["\(api)/sync/ratings"] = ["added": ["movies": 1]]
        http.json["\(api)/sync/ratings/remove"] = ["deleted": ["shows": 1]]
        let trakt = makeTrakt(http)
        try await trakt.setRating(imdb: "tt6751668", series: false, rating: 9)
        let added = try XCTUnwrap(http.bodies(for: "\(api)/sync/ratings").first.flatMap(JSON.parse))
        XCTAssertEqual(added["movies"]?.array?.first?["rating"]?.intValue, 9)
        XCTAssertEqual(added["movies"]?.array?.first?["ids"]?["imdb"]?.string, "tt6751668")
        try await trakt.setRating(imdb: "tt0804503", series: true, rating: nil)
        let removed = try XCTUnwrap(http.bodies(for: "\(api)/sync/ratings/remove").first.flatMap(JSON.parse))
        XCTAssertEqual(removed["shows"]?.array?.first?["ids"]?["imdb"]?.string, "tt0804503")
        XCTAssertNil(removed["shows"]?.array?.first?["rating"])
    }

    func testNoMandaUnaCalificacionFueraDeRango() async {
        do { try await makeTrakt(FakeHTTP()).setRating(imdb: "tt1", series: false, rating: 11); XCTFail() } catch {}
    }

    func testSinConexionLaCalificacionEsperaYLaUltimaEsLaQueCuenta() async {
        let kv = InMemoryKeyValueStore(), box = TraktOutbox(kv)
        box.enqueue(.rating(imdb: "tt6751668", series: false, 7))
        box.enqueue(.rating(imdb: "tt6751668", series: false, 9))
        box.enqueue(.rating(imdb: "tt0804503", series: true, nil))
        let again = TraktOutbox(kv)
        XCTAssertEqual(again.pendingRatings["tt6751668"], .some(9))
        XCTAssertEqual(again.pendingRatings["tt0804503"], .some(nil), "quitarla también espera")
        let http = FakeHTTP()
        http.json["\(api)/sync/ratings"] = ["added": ["movies": 1]]
        http.json["\(api)/sync/ratings/remove"] = ["deleted": ["shows": 1]]
        let sent = await again.flush(makeTrakt(http))
        XCTAssertEqual(sent, 2)
        XCTAssertTrue(again.pendingRatings.isEmpty)
        XCTAssertEqual(http.bodies(for: "\(api)/sync/ratings").first.flatMap(JSON.parse)?["movies"]?.array?.first?["rating"]?.intValue, 9)
    }
}
