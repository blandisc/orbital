import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Gestor ola 3 (O3-B, Fernando, 10 nov 2026: «Vamos con todo y tus sugerencias»): cada vista con su fecha, borrar una sola,
/// cambiar la fecha, «Deshacer» solo la de hoy, notas (Trakt con VIP, iPhone sin VIP) y estrellas de temporada.
@MainActor
final class ViewingsTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func stubDune(_ rig: ServicesRig) {
        rig.http.json["\(api)/search/imdb/tt1160419?type=movie"] = [["movie": ["ids": ["trakt": 42, "imdb": "tt1160419"]]]]
        rig.http.prefix["\(api)/sync/history/movies/42"] = [
            ["id": 900, "watched_at": "2024-01-02T18:30:00.000Z", "action": "watch"],
            ["id": 901, "watched_at": "2025-03-14T21:12:00.000Z", "action": "watch"],
        ]
        rig.http.json["\(api)/sync/history/remove"] = ["deleted": ["movies": 1]]
        rig.http.json["\(api)/sync/history"] = ["added": ["movies": 1]]
    }

    func testCadaVistaConSuFechaLaMasNuevaPrimero() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        let found = try await rig.services.watch.viewings(kind: "movie", videoID: "tt1160419")
        XCTAssertEqual(found.map(\.id), [901, 900])
    }

    func testBorrarUnaSolaVistaMandaSuId() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        await rig.services.watch.removeViewing(TraktViewing(id: 900, at: Date()), kind: "movie", metaID: "tt1160419", videoID: "tt1160419", remaining: 1)
        let body = try XCTUnwrap(rig.http.bodies("\(api)/sync/history/remove").first.flatMap(JSON.parse))
        XCTAssertEqual(body["ids"]?.array?.compactMap(\.intValue), [900], "solo esa, no todas")
    }

    func testCambiarFechaAgregaLaNuevaYBorraLaVieja() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        // Trakt ya la tiene con la fecha nueva (así sabe la cola que llegó y borra la vieja).
        rig.http.prefix["\(api)/sync/history/movies/42"] = [["id": 900, "watched_at": "2024-01-02T18:30:00.000Z"],
                                                             ["id": 902, "watched_at": .string(LibraryRules.iso(day.timeIntervalSince1970))]]
        await rig.services.watch.moveViewing(TraktViewing(id: 900, at: Date()), kind: "movie", videoID: "tt1160419", to: day)
        XCTAssertEqual(rig.http.bodies("\(api)/sync/history").count, 1, "la nueva entra")
        XCTAssertEqual(rig.http.bodies("\(api)/sync/history/remove").first.flatMap(JSON.parse)?["ids"]?.array?.compactMap(\.intValue), [900])
        let left = await rig.services.watch.pending.load(); XCTAssertTrue(left.isEmpty)
    }

    func testSinRedLaFechaCambiadaEspera() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.offline = true
        await rig.services.watch.moveViewing(TraktViewing(id: 900, at: Date()), kind: "movie", videoID: "tt1160419", to: Date())
        let work = await rig.services.watch.pending.load()
        XCTAssertEqual(work.traktViewingRemovals, [], "la vieja no se borra antes de que llegue la nueva")
        XCTAssertEqual(work.traktRewatched.map(\.replaces), [900])
        XCTAssertEqual(work.goneViewings, [900], "pero ya no se enseña")
    }

    // MARK: la pasada del 10 nov (revisión)

    func testElHistorialSePideDeCienEnCien() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        _ = try await rig.services.watch.viewings(kind: "movie", videoID: "tt1160419")
        XCTAssertTrue(rig.http.calls.contains { $0.contains("/sync/history/movies/42") && $0.contains("limit=100") }, "Trakt da 10 si no se le pide más")
    }

    func testSiTraktRechazaLaFechaNuevaLaViejaSeQueda() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        rig.http.statuses["\(api)/sync/history"] = 422
        await rig.services.watch.moveViewing(TraktViewing(id: 900, at: Date()), kind: "movie", videoID: "tt1160419", to: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(rig.http.bodies("\(api)/sync/history/remove").isEmpty, "nunca se pierde la vista")
    }

    func testDeshacerNoBorraLaVistaDeLaTele() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        // La TV la marcó anoche (901, el 14 mar a las 21:12); en el iPhone se marca a las 9 de la mañana: no subió nada.
        let ok = await rig.services.watch.undoViewing(kind: "movie", metaID: "tt1160419", videoID: "tt1160419", at: Self.date("2025-03-15T09:00:00.000Z"), wasSeen: true)
        XCTAssertTrue(ok)
        XCTAssertTrue(rig.http.bodies("\(api)/sync/history/remove").isEmpty, "la de la TV se queda")
    }

    func testQuitarDeVistasTambienQuitaLaVueltaEnCola() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.offline = true
        await rig.services.watch.addViewing(kind: "movie", metaID: "tt1160419", videoID: "tt1160419", at: Date())
        await rig.services.watch.unmarkWatched(kind: "movie", metaID: "tt1160419", videoID: "tt1160419")
        let work = await rig.services.watch.pending.load()
        XCTAssertTrue(work.traktRewatched.isEmpty, "si no, Trakt la regresaría")
    }

    func testAlSerVIPLaNotaDelIPhoneNoSePierdeSiTraktLaRechaza() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/users/settings"] = ["user": ["vip": false]]
        let notes = NotesModel(rig.services)
        await notes.load()
        await notes.save("tt1160419", series: false, text: "Verla en IMAX")
        rig.http.json["\(api)/users/settings"] = ["user": ["vip": true]]
        rig.http.prefix["\(api)/users/me/notes/movies"] = []
        rig.http.prefix["\(api)/users/me/notes/shows"] = []
        rig.http.statuses["\(api)/notes"] = 422
        await notes.load()
        XCTAssertEqual(notes.note("tt1160419"), "Verla en IMAX", "se queda en el iPhone")
    }

    func testDeshacerQuitaSoloLaVistaDeHoy() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        stubDune(rig)
        let at = Self.date("2025-03-14T21:12:00.000Z")
        let ok = await rig.services.watch.undoViewing(kind: "movie", metaID: "tt1160419", videoID: "tt1160419", at: at, wasSeen: true)
        XCTAssertTrue(ok)
        XCTAssertEqual(rig.http.bodies("\(api)/sync/history/remove").first.flatMap(JSON.parse)?["ids"]?.array?.compactMap(\.intValue), [901])
    }

    func testRepetidasMenosDeUnaHora() {
        let t = TraktTarget(imdb: "tt0386676", season: 3, episode: 4)
        let a = TraktHistoryEntry(id: 1, at: Date(timeIntervalSince1970: 0), target: t, title: "The Bear")
        let b = TraktHistoryEntry(id: 2, at: Date(timeIntervalSince1970: 60), target: t, title: "The Bear")
        let c = TraktHistoryEntry(id: 3, at: Date(timeIntervalSince1970: 90_000), target: t, title: "The Bear")
        XCTAssertEqual(Trakt.repeats([a, b, c]), [2])
    }

    func testCalificarUnaTemporada() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/sync/ratings"] = ["added": ["seasons": 1]]
        try await rig.services.trakt!.setRating(imdb: RatingKey.season(show: "tt14452776", season: 3), series: true, rating: 6)
        let body = try XCTUnwrap(rig.http.bodies("\(api)/sync/ratings").first.flatMap(JSON.parse))
        let season = body["shows"]?.array?.first?["seasons"]?.array?.first
        XCTAssertEqual(season?["number"]?.intValue, 3)
        XCTAssertEqual(season?["rating"]?.intValue, 6)
    }

    func testSinVIPLaNotaSeQuedaEnElIPhone() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/users/settings"] = ["user": ["vip": false]]
        let notes = NotesModel(rig.services)
        await notes.load()
        XCTAssertEqual(notes.vip, false)
        await notes.save("tt1160419", series: false, text: "Verla en IMAX")
        XCTAssertEqual(notes.note("tt1160419"), "Verla en IMAX")
        XCTAssertTrue(rig.http.bodies("\(api)/notes").isEmpty, "nada sale a Trakt")
    }

    func testConVIPLaNotaVaATraktYPrivada() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.json["\(api)/users/settings"] = ["user": ["vip": true]]
        rig.http.prefix["\(api)/users/me/notes/movies"] = []
        rig.http.prefix["\(api)/users/me/notes/shows"] = []
        rig.http.json["\(api)/notes"] = ["id": 77]
        let notes = NotesModel(rig.services)
        await notes.load()
        await notes.save("tt1160419", series: false, text: "Verla en IMAX")
        let body = try XCTUnwrap(rig.http.bodies("\(api)/notes").first.flatMap(JSON.parse))
        XCTAssertEqual(body["notes"]?.string, "Verla en IMAX")
        XCTAssertEqual(body["privacy"]?.string, "private")
        XCTAssertEqual(body["movie"]?["ids"]?["imdb"]?.string, "tt1160419")
    }

    static func date(_ s: String) -> Date { Trakt.date(.string(s))! }
}
