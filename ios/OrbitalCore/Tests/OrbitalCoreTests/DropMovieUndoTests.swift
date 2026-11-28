import XCTest
@testable import OrbitalCore

/// «Deshacer» de «La dejé» en una película la regresa a «Seguir viendo» donde ibas (antes solo volvía a Mi lista y la fila la
/// perdía: revisión del 27 nov 2026). Regla en `docs/ios-interfaz.md` («Lo que quitas se puede deshacer»).
final class DropMovieUndoTests: XCTestCase {
    func testUndoingLaDejeBringsTheMovieBackToContinueWatching() async throws {
        let library = LocalLibrary()
        let clock = Clock()
        let service = WatchService(library: library, cinemeta: Cinemeta(http: FakeHTTP()), trakt: nil, pending: InMemoryPendingStore(),
                                   clock: { clock.now }, sleep: { _ in })
        let movie = "tt1160419"
        await service.report(ProgressEvent(kind: "movie", metaID: movie, videoID: movie, originalTitle: "Dune", position: 1800,
                                           duration: 9300, watched: 1800, at: clock.now.timeIntervalSince1970, channel: false),
                             phase: .paused)
        XCTAssertTrue(try XCTUnwrap(library.entry(movie)).inContinue, "a medias: en la fila")
        await service.dismissContinue(metaID: movie)
        XCTAssertFalse(try XCTUnwrap(library.entry(movie)).inContinue, "«La dejé»: fuera de la fila")
        await service.restoreContinue(metaID: movie)
        let back = try XCTUnwrap(library.entry(movie))
        XCTAssertTrue(back.inContinue, "«Deshacer»: de vuelta en la fila")
        XCTAssertEqual(back.position, 1800, "donde ibas")
    }
}
