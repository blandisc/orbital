import XCTest
@testable import OrbitalCore

/// La cola única de Trakt (F4, 11 nov 2026): lo visto y lo de tus listas en un solo archivo, una sola política de reintento y
/// vencimiento, lo descartado en una bitácora, y nada se pierde al rearmar los servicios.
final class TraktQueueTests: XCTestCase {
    let api = "https://api.trakt.tv"
    let dune = TraktTarget(videoID: "tt1160419", kind: "movie")!

    func makeTrakt(_ http: FakeHTTP, clock: Clock) -> Trakt {
        // Antes de subir una vista sola, Trakt revisa que no esté ya (Dune = 42, sin vistas).
        http.json["\(api)/search/imdb/tt1160419?type=movie"] = [["movie": ["ids": ["trakt": 42, "imdb": "tt1160419"]]]]
        http.prefix["\(api)/sync/history/movies/42"] = []
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 90 * 86400)}"#)
        return Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
    }

    func makeWatch(_ http: FakeHTTP, trakt: Trakt, store: PendingStore, queue: TraktQueue, clock: Clock) -> WatchService {
        WatchService(cinemeta: Cinemeta(http: http), trakt: trakt, pending: store,
                     clock: { clock.now }, queue: queue, sleep: { _ in })
    }

    func testLoQueEsperabaEnUserDefaultsPasaAlArchivoSinPerderNada() throws {
        let kv = InMemoryKeyValueStore(), store = InMemoryPendingStore()
        let old = [TraktOutbox.Item(target: TraktOutbox.watchlist, imdb: "tt1", series: false, add: true),
                   .rating(imdb: "tt2", series: true, 8)]
        kv.set(TraktOutbox.legacyKey, data: try JSONEncoder().encode(old))
        var work = PendingWork()
        work.traktWatched = [.init(target: dune, at: 100)]
        work.outbox = [.init(target: TraktOutbox.watchlist, imdb: "tt1", series: false, add: false)]   // más nuevo: no se pisa
        store.save(work)
        let box = TraktOutbox(kv, store: store)
        XCTAssertEqual(box.pending.map(\.imdb), ["tt1", "tt2"])
        XCTAssertEqual(box.pending(target: TraktOutbox.watchlist, imdb: "tt1"), false, "lo que ya estaba en el archivo gana")
        XCTAssertEqual(box.pendingRatings["tt2"], .some(8))
        XCTAssertNotNil(box.pending.last?.queuedAt, "desde la migración cuenta para vencer")
        XCTAssertNil(kv.data(TraktOutbox.legacyKey), "UserDefaults queda vacío")
        XCTAssertEqual(store.load().traktWatched.count, 1, "lo visto que esperaba sigue ahí")
        _ = TraktOutbox(kv, store: store)
        XCTAssertEqual(store.load().outbox.count, 2, "migrar otra vez no duplica")
    }

    func testLoQueTraktRechazaQuedaEnLaBitacora() async {
        let http = FakeHTTP(), clock = Clock(), store = InMemoryPendingStore()
        let box = TraktOutbox(queue: TraktQueue(store: store, clock: { clock.now }), kv: InMemoryKeyValueStore(), clock: { clock.now })
        http.json["\(api)/users/me/lists/77/items"] = [:]; http.statuses["\(api)/users/me/lists/77/items"] = 404   // la lista ya no existe
        box.enqueue(.init(target: "77", imdb: "tt1", series: false, add: true))
        let sent = await box.flush(makeTrakt(http, clock: clock))
        XCTAssertEqual(sent, 0)
        XCTAssertTrue(box.pending.isEmpty, "no se reintenta para siempre")
        XCTAssertEqual(box.discards.map(\.what), ["Lista 77 · tt1"])
        XCTAssertEqual(box.discards.first?.reason, "Trakt respondió 404")
    }

    func testLoVistoSinSesionAhoraSeReintentaYNoSeDescarta() async {
        let http = FakeHTTP(), clock = Clock(), store = InMemoryPendingStore(), queue = TraktQueue(store: store, clock: { clock.now })
        let trakt = makeTrakt(http, clock: clock)
        http.json["\(api)/sync/history"] = [:]; http.statuses["\(api)/sync/history"] = 401
        http.json["\(api)/oauth/token"] = [:]; http.statuses["\(api)/oauth/token"] = 401   // la sesión caducó: hay que reconectar
        store.update { $0.traktWatched = [.init(target: self.dune, at: clock.now.timeIntervalSince1970)] }
        await queue.flush(trakt)
        XCTAssertEqual(store.load().traktWatched.count, 1, "un 401 (sesión por reconectar) espera, como tus listas")
        XCTAssertTrue(store.load().discards.isEmpty)
    }

    func testLoQueNoSePudoMandarEnTreintaDiasVenceYSeDice() async {
        let http = FakeHTTP(), clock = Clock(), store = InMemoryPendingStore(), queue = TraktQueue(store: store, clock: { clock.now })
        let trakt = makeTrakt(http, clock: clock)
        http.failing = ["\(api)/sync/history"]
        store.update { $0.traktWatched = [.init(target: self.dune, at: clock.now.timeIntervalSince1970)] }
        await queue.flush(trakt)
        XCTAssertEqual(store.load().traktWatched.count, 1, "sin red: espera")
        clock.now = clock.now.addingTimeInterval(TraktQueue.expiry + 60)
        await queue.flush(trakt)
        XCTAssertTrue(store.load().traktWatched.isEmpty)
        XCTAssertEqual(store.load().discards.map(\.reason), ["venció sin poder mandarse"])
        XCTAssertEqual(store.load().discards.first?.what, "Visto · tt1160419")
    }

    func testUnaFechaCambiadaQueTraktRechazaNoBorraLaVistaVieja() async {
        let http = FakeHTTP(), clock = Clock(), store = InMemoryPendingStore(), queue = TraktQueue(store: store, clock: { clock.now })
        let trakt = makeTrakt(http, clock: clock)
        http.json["\(api)/sync/history"] = [:]; http.statuses["\(api)/sync/history"] = 422
        http.json["\(api)/sync/history/remove"] = ["deleted": ["movies": 1]]
        store.update { $0.traktRewatched = [.init(target: self.dune, at: 500, replaces: 42)] }
        await queue.flush(trakt)   // sin cómo preguntar a Trakt (sin respuesta para el historial de Dune)
        XCTAssertTrue(http.bodies(for: "\(api)/sync/history/remove").isEmpty, "la vieja se queda: nunca se pierde la vista")
        XCTAssertEqual(store.load().discards.count, 1)
        XCTAssertTrue(store.load().isEmpty)
    }

    /// `Services.rebuild()`: el `WatchService` viejo sigue vaciando mientras el nuevo ya anota. Antes cada uno leía y guardaba
    /// el archivo por su lado y lo del nuevo se podía perder; ahora comparten la cola y cada cambio es un solo paso.
    func testAlRearmarLosServiciosNadaDeLoPendienteSePierde() async throws {
        let http = FakeHTTP(), clock = Clock(), store = InMemoryPendingStore(), queue = TraktQueue(store: store, clock: { clock.now })
        let trakt = makeTrakt(http, clock: clock)
        http.json["\(api)/sync/history"] = ["added": ["movies": 1]]
        http.json["\(api)/sync/history/remove"] = ["deleted": ["episodes": 1]]
        http.json["\(api)/sync/ratings"] = ["added": ["movies": 1]]
        http.delays["\(api)/sync/history"] = 120   // la subida del viejo tarda: el nuevo anota en medio
        let old = makeWatch(http, trakt: trakt, store: store, queue: queue, clock: clock)
        let new = makeWatch(http, trakt: trakt, store: store, queue: queue, clock: clock)
        let box = TraktOutbox(queue: queue, kv: InMemoryKeyValueStore(), clock: { clock.now })
        store.update { $0.traktWatched = [.init(target: self.dune, at: clock.now.timeIntervalSince1970)] }
        let flushing = Task { await old.flushPending() }
        try await Task.sleep(nanoseconds: 40_000_000)
        await new.unmarkWatched(kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:5")
        box.enqueue(.rating(imdb: "tt0386676", series: true, 9))
        _ = await flushing.value
        await new.flushPending()
        let left = store.load()
        XCTAssertTrue(left.isEmpty, "lo del viejo y lo del nuevo llegaron: \(left)")
        XCTAssertEqual(http.bodies(for: "\(api)/sync/history").count, 1, "lo del viejo se mandó una sola vez")
        XCTAssertEqual(http.bodies(for: "\(api)/sync/history/remove").count, 1, "lo que anotó el nuevo durante el vaciado llegó")
        XCTAssertEqual(http.bodies(for: "\(api)/sync/ratings").count, 1, "tu calificación también, por la misma cola")
        XCTAssertTrue(left.discards.isEmpty)
    }

    /// Revisión del 11 nov 2026: el aviso de tu avance que pidió un `WatchService` que `Services.rebuild()` ya soltó se manda
    /// de verdad en la vuelta siguiente. Antes (`[weak self]`) la llamada no hacía nada, no lanzaba, y la cola lo daba por
    /// enviado: tu avance desaparecía sin llegar a Trakt.
    func testElAvanceQuePidioUnServicioYaSueltoLlegaATrakt() async throws {
        let http = FakeHTTP(), clock = Clock(), store = InMemoryPendingStore(), queue = TraktQueue(store: store, clock: { clock.now })
        let trakt = makeTrakt(http, clock: clock)
        http.json["\(api)/sync/history"] = ["added": ["movies": 1]]
        http.json["\(api)/scrobble/start"] = [:]; http.json["\(api)/scrobble/pause"] = [:]
        http.prefix["\(api)/sync/playback"] = []
        http.delays["\(api)/sync/history"] = 150   // la vuelta del servicio viejo tarda: a media vuelta se rearman los servicios
        let old = makeWatch(http, trakt: trakt, store: store, queue: queue, clock: clock)
        store.update { $0.traktWatched = [.init(target: self.dune, at: clock.now.timeIntervalSince1970)] }
        let flushing = Task { await old.flushPending() }
        try await Task.sleep(nanoseconds: 40_000_000)
        weak var released: WatchService?
        do {
            // El servicio nuevo (tras `rebuild()`) anota tu avance y pide vaciar mientras el viejo vacía; luego también lo suelta
            // otro `rebuild()`: lo suyo sale en la vuelta siguiente del viejo.
            let rebuilt = makeWatch(http, trakt: trakt, store: store, queue: queue, clock: clock)
            released = rebuilt
            await rebuilt.queue(progress: ProgressEvent(kind: "movie", metaID: "tt1160419", videoID: "tt1160419", originalTitle: "Dune",
                                                       position: 3000, duration: 9000, watched: 60, at: clock.now.timeIntervalSince1970))
            await rebuilt.flushPending()
        }
        _ = await flushing.value
        XCTAssertNil(released, "el servicio que pidió el aviso ya se soltó (como tras `Services.rebuild()`)")
        XCTAssertEqual(http.bodies(for: "\(api)/scrobble/start").count, 1, "tu avance se mandó de verdad")
        XCTAssertEqual(http.bodies(for: "\(api)/scrobble/pause").count, 1)
        XCTAssertTrue(store.load().traktProgress.isEmpty, "y solo entonces sale de la cola")
    }

    /// Sin nadie que sepa mandar tu avance (sin Trakt en el servicio), la cola no lo da por enviado: espera.
    func testSinTraktElAvanceNoSeDaPorEnviado() async throws {
        let http = FakeHTTP(), clock = Clock()
        let service = WatchService(cinemeta: Cinemeta(http: http), trakt: nil, pending: InMemoryPendingStore(), clock: { clock.now }, sleep: { _ in })
        let target = TraktTarget(videoID: "tt1160419", kind: "movie")!
        let event = ProgressEvent(kind: "movie", metaID: "tt1160419", videoID: "tt1160419", originalTitle: "Dune", position: 3000, duration: 9000, watched: 60, at: 1)
        do { try await service.sendCheckpoint(event, target); XCTFail("debía lanzar") }
        catch { XCTAssertTrue(TraktQueue.retry(error), "y el error se reintenta: el avance se queda en la cola") }
    }
}
