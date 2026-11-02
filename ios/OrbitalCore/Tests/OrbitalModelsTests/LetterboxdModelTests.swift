import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Letterboxd en el iPhone: conectar con tu usuario lee tu diario y lo cruza con su IMDb (por TMDB), un usuario que no existe
/// se dice, lo que solo está en Letterboxd se ofrece pasar a Trakt (con el día y tus estrellas) y desconectar lo olvida todo.
@MainActor
final class LetterboxdModelTests: XCTestCase {
    let rss = """
    <rss><channel><item> <title>The Invite, 2026 - ★★★★</title> <link>https://letterboxd.com/fer/film/the-invite-2026/</link>
    <guid isPermaLink="false">letterboxd-review-1</guid> <letterboxd:watchedDate>2026-11-01</letterboxd:watchedDate>
    <letterboxd:rewatch>No</letterboxd:rewatch> <letterboxd:filmTitle>The Invite</letterboxd:filmTitle> <letterboxd:filmYear>2026</letterboxd:filmYear>
    <letterboxd:memberRating>4.0</letterboxd:memberRating> <letterboxd:memberLike>Yes</letterboxd:memberLike> <tmdb:movieId>950028</tmdb:movieId>
    <description><![CDATA[ <p><img src="x"/></p> <p>Una cena que se tuerce.</p> ]]></description> </item></channel></rss>
    """

    func testConectarLeeTuDiarioYLoCruzaConIMDb() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID", tmdbKey: "K")
        rig.http.raw["https://letterboxd.com/fer/rss/"] = Data(rss.utf8)
        rig.http.prefix["https://api.themoviedb.org/3/movie/950028?"] = ["id": 950028, "title": "The Invite", "imdb_id": "tt31000001", "release_date": "2026-10-01"]
        let model = LetterboxdModel(rig.services)
        XCTAssertFalse(model.connected)
        let problem = await model.connect(" @Fer ")
        XCTAssertNil(problem)
        XCTAssertEqual(model.user, "fer")
        let entry = try XCTUnwrap(model.reviews.first)
        XCTAssertEqual(entry.imdb, "tt31000001")
        XCTAssertEqual(entry.review, "Una cena que se tuerce.")
        XCTAssertEqual(model.entry(imdb: "tt31000001")?.rating, 4)
        XCTAssertEqual(model.averageRating, 4)
        XCTAssertEqual(LetterboxdModel(rig.services).entries.count, 1, "queda guardado en el iPhone")

        // Lo que Trakt no tiene: al historial con su día y con sus estrellas (8 de 10).
        XCTAssertEqual(model.missingInTrakt(watched: ["tt31000001"]).count, 0)
        let missing = model.missingInTrakt(watched: [])
        rig.http.json["https://api.trakt.tv/sync/history"] = ["added": ["movies": 1]]
        rig.http.json["https://api.trakt.tv/sync/ratings"] = ["added": ["movies": 1]]
        let passed = await model.passToTrakt(missing)
        XCTAssertEqual(passed, 1)
        let history = try XCTUnwrap(JSON.parse(try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/sync/history").last)))
        XCTAssertEqual(history["movies"]?.array?.first?["ids"]?["imdb"]?.string, "tt31000001")
        XCTAssertEqual(history["movies"]?.array?.first?["watched_at"]?.string?.prefix(10), "2026-11-01")
        let rating = try XCTUnwrap(JSON.parse(try XCTUnwrap(rig.http.bodies("https://api.trakt.tv/sync/ratings").last)))
        XCTAssertEqual(rating["movies"]?.array?.first?["rating"]?.intValue, 8)

        model.disconnect()
        XCTAssertFalse(model.connected)
        XCTAssertTrue(LetterboxdModel(rig.services).entries.isEmpty)
    }

    func testUnUsuarioQueNoExisteSeDice() async throws {
        let rig = try ServicesRig()
        rig.http.statuses["https://letterboxd.com/nadie/rss/"] = 404
        let model = LetterboxdModel(rig.services)
        let problem = await model.connect("nadie")
        XCTAssertEqual(problem, "No encontré ese usuario en Letterboxd")
        XCTAssertNil(model.user)
        let blank = await model.connect("dos palabras")
        XCTAssertNotNil(blank)
    }
}
