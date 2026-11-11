import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Revisión del 11 nov 2026: lo que no llegó a Trakt se ve en Ajustes (qué fue, cuándo y por qué, en palabras llanas) y lo que
/// venció se puede volver a mandar. Antes se guardaba en la bitácora y nadie lo veía.
@MainActor
final class TraktDiscardsModelTests: XCTestCase {
    let api = "https://api.trakt.tv"

    func rig() throws -> ServicesRig {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.services.library.update("tt1160419", make: { LibraryEntry(metaID: "tt1160419", kind: "movie", name: "Dune", poster: nil) }) { _ in }
        return rig
    }

    func expired(_ rig: ServicesRig, _ imdb: String = "tt1160419") {
        let watched = PendingWork.TraktWatched(target: TraktTarget(imdb: imdb), at: 1_700_000_000)
        rig.services.traktQueue.record(TraktAttempt(what: "Visto · \(imdb)", kind: .watched, target: watched.target, retry: .init(traktWatched: [watched])),
                                       error: nil, at: rig.clock.now.timeIntervalSince1970)
    }

    func testLoQueVencioSeVeConSuNombreYSuPorQue() throws {
        let rig = try rig()
        expired(rig)
        let model = TraktDiscardsModel(rig.services)
        XCTAssertEqual(model.count, 1)
        let row = try XCTUnwrap(model.rows.first)
        XCTAssertEqual(row.action, "Marcar como visto")
        XCTAssertEqual(row.title, "Dune", "el nombre, no el id")
        XCTAssertEqual(row.reason, "Pasaron 30 días sin poder mandarlo")
        XCTAssertTrue(row.canRetry)
    }

    func testLoQueTraktRechazoDiceElCodigoYNoOfreceReintentar() throws {
        let rig = try rig()
        rig.services.traktQueue.record(TraktAttempt(what: "Tu calificación · tt1", kind: .rating, target: TraktTarget(imdb: "tt1"), retry: .init()),
                                       error: TraktError.http(422), at: 1)
        rig.services.traktQueue.record(TraktAttempt(what: "Lista 77 · tt2", kind: .list, target: TraktTarget(imdb: "tt2"), retry: .init()),
                                       error: TraktError.http(404), at: 2)
        let model = TraktDiscardsModel(rig.services)
        XCTAssertEqual(model.rows.map(\.action), ["Una de tus listas", "Tu calificación"], "lo más nuevo primero")
        XCTAssertEqual(model.rows.map(\.reason), ["Trakt ya no lo encuentra (la lista o el título se borró)", "Trakt no lo aceptó (código %lld)"])
        XCTAssertEqual(model.rows.last?.status, 422)
        XCTAssertEqual(model.rows.map(\.title), ["tt2", "tt1"], "sin nombre conocido, el id")
        XCTAssertFalse(model.rows.contains(where: \.canRetry), "reintentar no arregla lo que Trakt rechaza")
    }

    func testReintentarLoVuelveAMandarYSaleDeLaLista() async throws {
        let rig = try rig()
        rig.http.json["\(api)/sync/history"] = ["added": ["movies": 1]]
        rig.http.prefix["\(api)/sync/history/"] = []   // todavía no la tiene en su historial
        rig.http.prefix["\(api)/search/"] = []
        expired(rig)
        let model = TraktDiscardsModel(rig.services)
        let row = try XCTUnwrap(model.rows.first)
        await model.retry(row)
        let sent = rig.http.bodies("\(api)/sync/history").compactMap { JSON.parse($0)?["movies"]?.array?.first?["ids"]?["imdb"]?.string }
        XCTAssertEqual(sent, ["tt1160419"], "llegó a Trakt")
        XCTAssertEqual(model.count, 0)
        XCTAssertTrue(rig.services.traktQueue.discards.isEmpty)
    }

    func testReintentarSinRedLoDejaEnLaColaComoNuevo() async throws {
        let rig = try rig()
        expired(rig)
        rig.http.offline = true
        let model = TraktDiscardsModel(rig.services)
        await model.retry(try XCTUnwrap(model.rows.first))
        XCTAssertEqual(model.count, 0, "ya no está perdido")
        let queued = rig.pending.load().traktWatched
        XCTAssertEqual(queued.map(\.target.imdb), ["tt1160419"], "espera en la cola")
        XCTAssertEqual(queued.first?.queuedAt, rig.clock.now.timeIntervalSince1970, "cuenta otra vez desde hoy (no vence en seguida)")
    }

    func testBorrarLaLista() throws {
        let rig = try rig()
        expired(rig); expired(rig, "tt2")
        let model = TraktDiscardsModel(rig.services)
        XCTAssertEqual(model.count, 2)
        model.clear()
        XCTAssertEqual(model.count, 0)
        XCTAssertTrue(rig.services.traktQueue.discards.isEmpty)
    }

    /// Los descartes de antes del 11 nov (solo «qué» y «por qué») se siguen leyendo y se dicen en palabras llanas.
    func testLosDeAntesSeSiguenLeyendo() throws {
        let data = Data(#"{"discards":[{"what":"Visto · tt1","reason":"venció sin poder mandarse","at":5}]}"#.utf8)
        let work = try JSONDecoder().decode(PendingWork.self, from: data)
        let rig = try rig()
        rig.pending.update { $0.discards = work.discards }
        let row = try XCTUnwrap(TraktDiscardsModel(rig.services).rows.first)
        XCTAssertEqual(row.action, "Algo de tu cuenta")
        XCTAssertEqual(row.reason, "Pasaron 30 días sin poder mandarlo")
        XCTAssertFalse(row.canRetry)
    }
}
