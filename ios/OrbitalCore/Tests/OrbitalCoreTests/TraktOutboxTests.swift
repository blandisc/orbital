import XCTest
@testable import OrbitalCore

/// Guardar en Trakt sin conexión (o con tu Orbital apagada): se queda en el iPhone y se manda después; no se pierde.
extension TraktOutbox {
    /// Para las pruebas: la cola única sobre `store` (el mismo `store` y `kv` = la misma app tras cerrarla).
    convenience init(_ kv: KeyValueStore, store: PendingStore = InMemoryPendingStore()) {
        self.init(queue: TraktQueue(store: store), kv: kv)
    }
}

final class TraktOutboxTests: XCTestCase {
    func testLoUltimoQueEligesEsLoQueCuentaYSobreviveAlCierre() {
        let kv = InMemoryKeyValueStore(), store = InMemoryPendingStore()
        let box = TraktOutbox(kv, store: store)
        box.enqueue(.init(target: TraktOutbox.watchlist, imdb: "tt1", series: false, add: true))
        box.enqueue(.init(target: TraktOutbox.watchlist, imdb: "tt1", series: false, add: false))
        box.enqueue(.init(target: "123", imdb: "tt1", series: false, add: true))
        let again = TraktOutbox(kv, store: store)
        XCTAssertEqual(again.pending.count, 2)
        XCTAssertEqual(again.pending(target: TraktOutbox.watchlist, imdb: "tt1"), false)
        XCTAssertEqual(again.pending(target: "123", imdb: "tt1"), true)
        XCTAssertNil(again.pending(target: "123", imdb: "tt2"))
    }

    func testQueSeGuardaParaDespues() {
        XCTAssertTrue(TraktOutbox.retryable(TraktError.network("x")))
        XCTAssertTrue(TraktOutbox.retryable(TraktError.auth("x")))
        XCTAssertTrue(TraktOutbox.retryable(TraktError.http(503)))
        XCTAssertTrue(TraktOutbox.retryable(TraktError.http(429)))
        XCTAssertFalse(TraktOutbox.retryable(TraktError.http(404)))   // la lista ya no existe
        XCTAssertFalse(TraktOutbox.retryable(TraktError.invalid("x")))
    }

    func testRecuerdaTusListasParaElegirlasSinConexion() {
        let kv = InMemoryKeyValueStore()
        TraktOutbox(kv).remember(lists: [("1", "Para ver con Ana"), ("2", "Terror")])
        XCTAssertEqual(TraktOutbox(kv).cachedLists.map(\.name), ["Para ver con Ana", "Terror"])
    }

    func testSinSesionNoMandaNada() async {
        let box = TraktOutbox(InMemoryKeyValueStore())
        box.enqueue(.init(target: TraktOutbox.watchlist, imdb: "tt1", series: false, add: true))
        let sent = await box.flush(nil)
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(box.pending.count, 1, "espera a que haya sesión")
    }
}
