import XCTest
@testable import OrbitalCore

/// Seguir viendo: cuándo un episodio cuenta como visto y cuándo una serie que ibas al día vuelve con su episodio nuevo.
/// Mismos casos que `tests/test_stremio.py` (la consola).
final class ContinueReturnTests: XCTestCase {
    func testAnEpisodeCountsAsSeenOnlyInItsLastStretch() {
        // Los Simpson (22 min): a 2 min del final (91 %) es la escena final, no los créditos.
        XCTAssertFalse(StremioLibrary.finished(position: 1200, duration: 1320, kind: "series"))
        XCTAssertTrue(StremioLibrary.finished(position: 1255, duration: 1320, kind: "series"))
        XCTAssertFalse(StremioLibrary.finished(position: 3400, duration: 3600, kind: "series"))   // una hora: 90 s
        XCTAssertTrue(StremioLibrary.finished(position: 3515, duration: 3600, kind: "series"))
        XCTAssertTrue(StremioLibrary.finished(position: 9200, duration: 10140, kind: "movie"))     // películas: 90 %
        XCTAssertFalse(StremioLibrary.finished(position: 9000, duration: 10140, kind: "movie"))
        XCTAssertFalse(StremioLibrary.finished(position: 100, duration: 0, kind: "series"))
        let item = StremioLibrary.withProgress(nil, metaID: "tt1", kind: "series", name: "X", poster: nil, videoID: "tt1:38:4",
                                               position: 1200, duration: 1320, watched: 1200, nextVideo: nil, now: 0)
        XCTAssertEqual(StremioLibrary.resumeSeconds(item, videoID: "tt1:38:4"), 1200)   // sigue en Seguir viendo, y se retoma ahí
    }

    private let now = 1_800_000_000.0

    private func show(e5: Double) -> JSON {
        let videos: [JSON] = [(3, now - 20 * 86400), (4, now - 5 * 86400), (5, e5)].map { n, at in
            .object(["id": .string("tt1:38:\(n)"), "season": .int(38), "episode": .int(n), "name": .string("E\(n)"),
                     "released": .string(StremioLibrary.iso(at))])
        }
        return .object(["id": "tt1", "name": "The Simpsons", "videos": .array(videos)])
    }

    func testTheNextEpisodeMustHaveAired() {
        XCTAssertNil(CinemetaParsing.nextEpisode(show(e5: now + 5 * 86400), after: "tt1:38:4", now: now))   // sale en 5 días
        XCTAssertEqual(CinemetaParsing.nextEpisode(show(e5: now - 86400), after: "tt1:38:4", now: now), "tt1:38:5")
    }

    func testACaughtUpSeriesComesBackWhenTheNewEpisodeAirs() throws {
        let finishedAt = now - 3 * 86400
        let new = try XCTUnwrap(CinemetaParsing.newEpisode(show(e5: now - 86400), after: "tt1:38:4", since: finishedAt, now: now))
        XCTAssertEqual(new.id, "tt1:38:5")
        XCTAssertNil(CinemetaParsing.newEpisode(show(e5: now + 86400), after: "tt1:38:4", since: finishedAt, now: now))      // aún no sale
        XCTAssertNil(CinemetaParsing.newEpisode(show(e5: now - 4 * 86400), after: "tt1:38:4", since: finishedAt, now: now))  // ya estaba

        let w = Watchable(id: "tt1", type: "series", name: "The Simpsons", poster: nil, videoID: "tt1:38:4", timeOffset: 0, duration: 0,
                          lastWatched: finishedAt, inContinue: false, inLibrary: false)
        XCTAssertTrue(w.mayReturn(now: now))
        XCTAssertFalse(w.mayReturn(now: now + 500 * 86400))   // hace más de 400 días: ya no
        let back = w.returning(videoID: new.id, released: new.released)
        XCTAssertTrue(back.inContinue && back.isNew)
        XCTAssertEqual(back.videoID, "tt1:38:5"); XCTAssertEqual(back.timeOffset, 1); XCTAssertEqual(back.lastWatched, new.released)

        // «Quitar»: apunta al episodio nuevo para que no vuelva otra vez.
        let gone = StremioLibrary.dismissed(.object(["_id": "tt1", "state": .object(["timeOffset": .int(0), "video_id": "tt1:38:4"])]),
                                            now: now, videoID: "tt1:38:5")
        XCTAssertEqual(StremioLibrary.state(of: gone)["video_id"]?.string, "tt1:38:5")
    }
}
