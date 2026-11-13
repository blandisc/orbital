import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Un número dice lo de ahora» (13 nov 2026): en la hoja de filtros de «Decide por mí» las baldosas de «Calificación»
/// decían «0» mientras arriba decía «5 opciones». Lo que cuenta cada número, que no se enseñe «0» mientras no se sabe, y
/// que lo que llega de TMDB o Letterboxd antes que Cinemeta ya no tape la calificación de IMDb.
@MainActor
final class DecideCountsTests: XCTestCase {
    private func item(_ id: String, kind: String = "movie") -> Suggestion {
        Suggestion(kind: kind, imdb: id, title: id, year: 2015, runtime: 100, poster: "", wide: "", reason: .recommended)
    }

    private func cinemeta(_ rig: ServicesRig, _ id: String, rating: String, genres: [String] = ["Drama"]) {
        rig.http.json["https://v3-cinemeta.strem.io/meta/movie/\(id).json"] =
            ["meta": ["id": .string(id), "type": "movie", "name": .string(id), "imdbRating": .string(rating), "genres": .array(genres.map { .string($0) })]]
    }

    /// Mientras Cinemeta no contesta, «6+» no dice «0» (no se sabe) y se puede tocar; cuando contesta, una sola tanda avisa
    /// a la pantalla y el número es el de ahora.
    func testLaCalificacionNoDiceCeroMientrasNoSeSabe() async throws {
        let rig = try ServicesRig()
        cinemeta(rig, "tt1", rating: "7.5"); cinemeta(rig, "tt2", rating: "6.2"); cinemeta(rig, "tt3", rating: "8.4")
        let model = DecideModel(rig.services, pool: [item("tt1"), item("tt2"), item("tt3")])
        model.ratingSources = [.imdb]
        let before = model.tally { $0.minRating = 7 }
        XCTAssertEqual(before.known, 0)
        XCTAssertEqual(before.pending, 3)
        XCTAssertNil(before.shown, "sin datos no se enseña «0»")
        XCTAssertTrue(before.open, "y no se apaga: tal vez sí tenga")
        var notices = 0
        let sub = model.onChange { notices += 1 }
        await model.describe(model.pool)
        XCTAssertEqual(notices, 1, "una tanda de datos, un solo aviso (no uno por título)")
        XCTAssertEqual(model.tally { $0.minRating = 7 }.shown, 2)
        XCTAssertEqual(model.tally { $0.minRating = 8 }.shown, 1)
        XCTAssertEqual(model.tally { $0.minRating = 6 }.shown, 3)
        sub.cancel()
        model.stop()
    }

    /// Lo de Letterboxd llega antes que Cinemeta: antes creaba el detalle vacío, Cinemeta ya no se preguntaba y «no hay
    /// calificación de IMDb» se tomaba por sabido (las baldosas se quedaban en 0 o 1). Ahora Cinemeta se pregunta igual y lo
    /// de Letterboxd se queda.
    func testLetterboxdAntesQueCinemetaNoTapaLaCalificacion() async throws {
        let rig = try ServicesRig()
        cinemeta(rig, "tt1", rating: "7.5")
        rig.http.raw["https://letterboxd.com/imdb/tt1/"] = Data(#"<meta property="og:url" content="https://letterboxd.com/film/x/" /><meta name="twitter:data2" content="4.1 out of 5" /><body data-tmdb-id="1">"#.utf8)
        let model = DecideModel(rig.services, pool: [item("tt1")])
        model.ratingSources = [.imdb]
        model.fetchLetterboxdInBackground()
        await model.ratingLetterboxd?.value
        XCTAssertNil(model.tally { $0.minRating = 7 }.shown, "con solo Letterboxd, IMDb aún no se sabe")
        await model.describe(model.pool)
        XCTAssertEqual(model.tally { $0.minRating = 7 }.shown, 1, "Cinemeta se preguntó aunque ya había detalle")
        XCTAssertEqual(model.tally { $0.minLetterboxd = 4 }.shown, 1, "y lo de Letterboxd no se perdió")
        model.stop()
    }

    /// La baldosa elegida dice lo mismo que la cuenta de arriba y que «Ver N»; en «Una por una» todo cuenta como el mazo
    /// (sin tiempo ni ánimo), igual que `deckPool`.
    func testLaBaldosaElegidaDiceLoMismoQueArriba() async throws {
        let rig = try ServicesRig()
        for (id, r) in [("tt1", "7.5"), ("tt2", "6.2"), ("tt3", "8.4"), ("tt4", "5.0")] { cinemeta(rig, id, rating: r, genres: id == "tt3" ? ["Comedy"] : ["Drama"]) }
        let model = DecideModel(rig.services, pool: ["tt1", "tt2", "tt3", "tt4"].map { item($0) })
        model.ratingSources = [.imdb]
        await model.describe(model.pool)
        model.minRating = 7
        XCTAssertEqual(model.tally { $0.minRating = model.minRating }, model.tally(), "elegida = arriba")
        XCTAssertEqual(model.tally().known, model.count())
        model.mood = .light
        XCTAssertEqual(model.tally().known, 1, "7+ y ligera: solo la comedia")
        XCTAssertEqual(model.tally(deck: true).known, model.deckPool().count, "el mazo no usa el ánimo")
        XCTAssertEqual(model.tally(deck: true).known, 2)
        XCTAssertEqual(model.tally(deck: true) { $0.minRating = 8 }.known, 1)
        model.stop()
    }
}
