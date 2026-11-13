import XCTest
@testable import OrbitalCore

/// V2 (Fernando, 13 nov 2026: «vamos con B2»): el canal no desordena tu serie, pero lo que dejaste a medias siempre se puede
/// retomar. Regla en `docs/ios-interfaz.md` («El canal no desordena tu serie…»).
final class ChannelProgressTests: XCTestCase {
    let series = try! Fixtures.json("cinemeta/meta_series_tt0386676.json")
    let show = "tt0386676"

    func make(trakt: Trakt? = nil, http: FakeHTTP = FakeHTTP(), clock: Clock = Clock()) -> (WatchService, LocalLibrary, Clock) {
        let library = LocalLibrary()
        http.json["https://v3-cinemeta.strem.io/meta/series/tt0386676.json"] = ["meta": series]
        let service = WatchService(library: library, cinemeta: Cinemeta(http: http), trakt: trakt, pending: InMemoryPendingStore(),
                                   clock: { clock.now }, sleep: { _ in })
        return (service, library, clock)
    }

    func event(_ clock: Clock, _ video: String, position: Double, watched: Double = 120, channel: Bool) -> ProgressEvent {
        ProgressEvent(kind: "series", metaID: show, videoID: video, originalTitle: "The Office", position: position, duration: 1320, watched: watched,
                      at: clock.now.timeIntervalSince1970, channel: channel)
    }

    /// En tu orden: terminaste T1 E1, te toca T1 E2.
    func inOrder(_ service: WatchService, _ clock: Clock) async {
        await service.report(event(clock, "\(show):1:1", position: 1320, watched: 1300, channel: false), phase: .stopped(finished: true))
        clock.advance(3600)
    }

    func testAChannelEpisodeLeftHalfwayShowsInContinueWatching() async throws {
        let (service, library, clock) = make()
        await inOrder(service, clock)
        await service.report(event(clock, "\(show):2:3", position: 600, channel: true), phase: .paused)
        let rows = await service.continueWatching()
        let row = try XCTUnwrap(rows.first { $0.id == show })
        XCTAssertEqual(row.videoID, "\(show):2:3", "«T2 E3 · quedan 12 min», no el siguiente de tu orden")
        XCTAssertEqual(row.progress ?? 0, 600.0 / 1320, accuracy: 0.001)
        XCTAssertEqual(library.entry(show)?.detour?.before.videoID, "\(show):1:2", "tu orden queda apartado")
    }

    func testAChannelEpisodeWatchedToTheEndIsSeenButDoesNotMoveYourNext() async throws {
        let (service, library, clock) = make()
        await inOrder(service, clock)
        await service.report(event(clock, "\(show):2:3", position: 600, channel: true), phase: .tick)
        clock.advance(720)
        await service.report(event(clock, "\(show):2:3", position: 1320, watched: 720, channel: true), phase: .stopped(finished: true))
        let mine = try XCTUnwrap(library.entry(show))
        XCTAssertTrue(mine.seen.contains("\(show):2:3"), "lo viste: queda visto")
        XCTAssertEqual(mine.videoID, "\(show):1:2"); XCTAssertTrue(mine.nextUp, "sigues en tu orden, no en T2 E4")
        XCTAssertNil(mine.detour)
        let rows = await service.continueWatching().filter { $0.id == show }
        XCTAssertEqual(rows.map(\.videoID), ["\(show):1:2"])
    }

    func testAChannelEpisodeOfASeriesYouDoNotWatchLeavesNoNextEpisode() async throws {
        let (service, library, clock) = make()
        await service.report(event(clock, "\(show):2:3", position: 1320, watched: 1320, channel: true), phase: .stopped(finished: true))
        let mine = try XCTUnwrap(library.entry(show))
        XCTAssertEqual(mine.seen, ["\(show):2:3"])
        XCTAssertNil(mine.videoID); XCTAssertFalse(mine.inContinue)
        let continuing = await service.continueWatching()
        XCTAssertTrue(continuing.isEmpty)
    }

    func testZappingAChannelChangesNothing() async throws {
        let (service, library, clock) = make()
        await service.report(event(clock, "\(show):2:3", position: 700, watched: 5, channel: true), phase: .paused)
        XCTAssertNil(library.entry(show), "una serie que no tienes no entra por zapear")
        await inOrder(service, clock)
        let before = library.entry(show)
        await service.report(event(clock, "\(show):2:3", position: 700, watched: 5, channel: true), phase: .paused)
        XCTAssertEqual(library.entry(show), before)
    }

    func testFromTheTitleInOrderItIsAsAlways() async throws {
        let (service, library, clock) = make()
        await inOrder(service, clock)
        await service.report(event(clock, "\(show):1:2", position: 1320, watched: 1300, channel: false), phase: .stopped(finished: true))
        let mine = try XCTUnwrap(library.entry(show))
        XCTAssertEqual(mine.videoID, "\(show):1:3"); XCTAssertTrue(mine.nextUp)
    }

    /// La mezcla: canal a medias, la ficha lo continúa y lo termina (vuelve a tu orden) y luego sigues en orden.
    func testMixingTheChannelAndYourOrder() async throws {
        let (service, library, clock) = make()
        await inOrder(service, clock)
        await service.report(event(clock, "\(show):2:3", position: 600, channel: true), phase: .paused)
        clock.advance(60)
        // Desde la ficha, «Continuar T2 E3» (no es canal): a medias sigue apartando tu orden.
        await service.report(event(clock, "\(show):2:3", position: 900, channel: false), phase: .paused)
        XCTAssertEqual(library.entry(show)?.detour?.before.videoID, "\(show):1:2")
        clock.advance(400)
        await service.report(event(clock, "\(show):2:3", position: 1320, watched: 420, channel: false), phase: .stopped(finished: true))
        var mine = try XCTUnwrap(library.entry(show))
        XCTAssertEqual(mine.videoID, "\(show):1:2", "al terminarlo vuelves a tu orden de antes"); XCTAssertTrue(mine.nextUp)
        XCTAssertTrue(mine.seen.contains("\(show):2:3"))
        clock.advance(60)
        await service.report(event(clock, "\(show):1:2", position: 1320, watched: 1300, channel: false), phase: .stopped(finished: true))
        mine = try XCTUnwrap(library.entry(show))
        XCTAssertEqual(mine.videoID, "\(show):1:3"); XCTAssertTrue(mine.nextUp)
    }

    func testTwoChannelEpisodesKeepYourOrderFromBeforeTheFirst() async throws {
        let (service, library, clock) = make()
        await inOrder(service, clock)
        await service.report(event(clock, "\(show):2:3", position: 600, channel: true), phase: .paused)
        await service.report(event(clock, "\(show):2:9", position: 300, channel: true), phase: .paused)
        XCTAssertEqual(library.entry(show)?.videoID, "\(show):2:9")
        await service.report(event(clock, "\(show):2:9", position: 1320, watched: 1000, channel: true), phase: .stopped(finished: true))
        XCTAssertEqual(library.entry(show)?.videoID, "\(show):1:2")
    }

    func testDismissingTheChannelEpisodeGoesBackToYourOrderOutOfTheRow() async throws {
        let (service, library, clock) = make()
        await inOrder(service, clock)
        await service.report(event(clock, "\(show):2:3", position: 600, channel: true), phase: .paused)
        await service.dismissContinue(metaID: show)
        let mine = try XCTUnwrap(library.entry(show))
        XCTAssertEqual(mine.videoID, "\(show):1:2"); XCTAssertTrue(mine.nextUp); XCTAssertNil(mine.detour)
        XCTAssertFalse(mine.inContinue, "quitarlo lo saca de la fila, sin dejar un «siguiente»")
    }

    func testTheChannelPuttingYourNextEpisodeCountsAsInOrder() async throws {
        let (service, library, clock) = make()
        await inOrder(service, clock)
        await service.report(event(clock, "\(show):1:2", position: 1320, watched: 1300, channel: true), phase: .stopped(finished: true))
        XCTAssertEqual(library.entry(show)?.videoID, "\(show):1:3")
    }

    /// Trakt anota visto el episodio del canal; cuando la sincronización lo devuelve como «lo último», no mueve tu orden.
    func testTraktEchoOfTheChannelEpisodeDoesNotMoveYourOrder() async throws {
        let (service, library, clock) = make()
        await inOrder(service, clock)
        let at = clock.now
        await service.report(event(clock, "\(show):2:3", position: 1320, watched: 1320, channel: true), phase: .stopped(finished: true))
        let echo = TraktShowProgress(imdb: show, lastWatchedAt: at.addingTimeInterval(30), completed: [(1, 1), (2, 3)], next: (2, 4), last: (2, 3))
        let merged = LibraryMerge.show(library.entry(show), echo, name: "The Office")
        XCTAssertEqual(merged.videoID, "\(show):1:2"); XCTAssertTrue(merged.nextUp)
        XCTAssertTrue(merged.seen.contains("\(show):2:3"))
        let later = TraktShowProgress(imdb: show, lastWatchedAt: at.addingTimeInterval(3600), completed: [(1, 1), (1, 2), (2, 3)], next: (1, 3), last: (1, 2))
        XCTAssertEqual(LibraryMerge.show(library.entry(show), later, name: "The Office").videoID, "\(show):1:3", "lo que veas después en otro aparato sí cuenta")
    }

    /// Lo que se guardó antes de V2 se sigue leyendo; el desvío viaja con el archivo.
    func testTheDetourSurvivesTheFile() throws {
        var entry = LibraryEntry(metaID: show, kind: "series", name: "The Office")
        entry.videoID = "\(show):1:2"; entry.nextUp = true
        entry.channelProgress(videoID: "\(show):2:3", position: 600, duration: 1320, watched: 120, at: 10)
        let back = try JSONDecoder().decode(LibraryEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(back, entry)
        let old = try JSONDecoder().decode(ProgressEvent.self, from: Data(#"{"kind":"series","metaID":"a","videoID":"a:1:1"}"#.utf8))
        XCTAssertFalse(old.channel)
    }
}

private extension Clock {
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}
