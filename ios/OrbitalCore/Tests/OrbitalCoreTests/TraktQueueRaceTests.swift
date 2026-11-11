import XCTest
@testable import OrbitalCore

/// Revisión del 11 nov 2026: marcar y desmarcar MIENTRAS la cola manda (con red lenta o sin red). Gana siempre lo último que
/// hiciste por título: antes, lo que se reintentaba se volvía a sumar aunque ya hubieras marcado lo contrario, y como la cola
/// manda primero «no visto» y luego «visto», Trakt terminaba en «visto» tras un «no visto».
final class TraktQueueRaceTests: XCTestCase {
    let api = "https://api.trakt.tv"
    let dune = "tt1160419"
    let writes = ["/sync/history", "/sync/history/remove", "/sync/ratings", "/sync/ratings/remove"]

    struct Rig { let http: FakeHTTP; let store: InMemoryPendingStore; let queue: TraktQueue; let watch: WatchService; let box: TraktOutbox; let trakt: Trakt }

    func makeRig() -> Rig {
        let http = FakeHTTP(), clock = Clock(), store = InMemoryPendingStore(), queue = TraktQueue(store: store, clock: { clock.now })
        http.json["\(api)/search/imdb/\(dune)?type=movie"] = [["movie": ["ids": ["trakt": 42, "imdb": .string(dune)]]]]
        http.prefix["\(api)/sync/history/movies/42"] = []
        for path in writes { http.json[api + path] = [:] }
        let secrets = InMemorySecrets()
        secrets.set(SecretKey.traktTokens, #"{"access_token":"AT","refresh_token":"RT","expires_at":\#(clock.now.timeIntervalSince1970 + 90 * 86400)}"#)
        let trakt = Trakt(http: http, secrets: secrets, clientID: "CID", clock: { clock.now }, pause: { _ in })
        let watch = WatchService(cinemeta: Cinemeta(http: http), trakt: trakt, pending: store, clock: { clock.now }, queue: queue, sleep: { _ in })
        let box = TraktOutbox(queue: queue, kv: InMemoryKeyValueStore(), clock: { clock.now })
        return Rig(http: http, store: store, queue: queue, watch: watch, box: box, trakt: trakt)
    }

    var movie: TraktTarget { TraktTarget(videoID: dune, kind: "movie")! }

    /// Lo primero se queda «en el aire» (lento; `offline`: además falla como sin red), lo segundo llega durante el envío; luego
    /// vuelve la red y la cola se vacía. Devuelve las escrituras a Trakt que se hicieron DESPUÉS de volver la red.
    func race(_ rig: Rig, slow url: String, offline: Bool, first: () async -> Void, second: () async -> Void) async throws -> [String] {
        rig.http.delays[api + url] = 150
        if offline { rig.http.failing = [api + url] }
        await first()
        let flushing = Task { await rig.queue.flush(rig.trakt) }
        try await Task.sleep(nanoseconds: 40_000_000)
        await second()   // a media vuelta: lo contrario
        _ = await flushing.value
        rig.http.failing = []; rig.http.delays = [:]
        let before = rig.http.calls.count
        await rig.queue.flush(rig.trakt)
        await rig.queue.flush(rig.trakt)
        XCTAssertTrue(rig.store.load().isEmpty, "nada queda colgado: \(rig.store.load())")
        return rig.http.calls.dropFirst(before).filter { call in writes.contains { call == api + $0 } }.map { String($0.dropFirst(api.count)) }
    }

    func lastWrite(_ rig: Rig, among paths: [String]) -> String? {
        rig.http.calls.last { call in paths.contains { call == api + $0 } }.map { String($0.dropFirst(api.count)) }
    }

    func testVistoYLuegoNoVistoTerminaNoVisto() async throws {
        for offline in [false, true] {
            let rig = makeRig()
            let after = try await race(rig, slow: "/sync/history", offline: offline,
                                       first: { rig.store.update { $0.traktWatched = [.init(target: self.movie, at: 100)] } },
                                       second: { await rig.watch.unmarkWatched(kind: "movie", metaID: self.dune, videoID: self.dune) })
            XCTAssertFalse(after.contains("/sync/history"), "«visto» no se resucita (sin red: \(offline)): \(after)")
            XCTAssertEqual(lastWrite(rig, among: ["/sync/history", "/sync/history/remove"]), "/sync/history/remove", "Trakt termina en «no visto» (sin red: \(offline))")
        }
    }

    func testNoVistoYLuegoVistoTerminaVisto() async throws {
        for offline in [false, true] {
            let rig = makeRig()
            let after = try await race(rig, slow: "/sync/history/remove", offline: offline,
                                       first: { rig.store.update { $0.traktUnwatched = [self.movie] } },
                                       second: { await rig.watch.markWatched(kind: "movie", metaID: self.dune, videoID: self.dune) })
            XCTAssertFalse(after.contains("/sync/history/remove"), "«no visto» no se resucita (sin red: \(offline)): \(after)")
            XCTAssertEqual(lastWrite(rig, among: ["/sync/history", "/sync/history/remove"]), "/sync/history", "Trakt termina en «visto» (sin red: \(offline))")
        }
    }

    func testCalificarYLuegoQuitarLaCalificacionTerminaSinCalificacion() async throws {
        for offline in [false, true] {
            let rig = makeRig()
            let after = try await race(rig, slow: "/sync/ratings", offline: offline,
                                       first: { rig.box.enqueue(.rating(imdb: self.dune, series: false, 8)) },
                                       second: { rig.box.enqueue(.rating(imdb: self.dune, series: false, nil)) })
            XCTAssertFalse(after.contains("/sync/ratings"), "la calificación vieja no se vuelve a mandar (sin red: \(offline)): \(after)")
            XCTAssertEqual(lastWrite(rig, among: ["/sync/ratings", "/sync/ratings/remove"]), "/sync/ratings/remove", "Trakt termina sin calificación (sin red: \(offline))")
        }
    }

    func testQuitarLaCalificacionYLuegoCalificarTerminaCalificado() async throws {
        for offline in [false, true] {
            let rig = makeRig()
            _ = try await race(rig, slow: "/sync/ratings/remove", offline: offline,
                               first: { rig.box.enqueue(.rating(imdb: self.dune, series: false, nil)) },
                               second: { rig.box.enqueue(.rating(imdb: self.dune, series: false, 9)) })
            XCTAssertEqual(lastWrite(rig, among: ["/sync/ratings", "/sync/ratings/remove"]), "/sync/ratings", "Trakt termina con tu 9 (sin red: \(offline))")
        }
    }

    /// Lo que se reintenta y nadie tocó se queda, una sola vez (no se pierde ni se duplica).
    func testLoQueFallaYNadieTocoSeQuedaUnaSolaVez() async {
        let rig = makeRig()
        rig.http.failing = [api + "/sync/history"]
        rig.store.update { $0.traktWatched = [.init(target: self.movie, at: 100)] }
        await rig.queue.flush(rig.trakt)
        await rig.queue.flush(rig.trakt)
        XCTAssertEqual(rig.store.load().traktWatched.map(\.target.imdb), [dune])
    }
}
