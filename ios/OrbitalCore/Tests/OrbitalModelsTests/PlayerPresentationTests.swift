import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// La carga y el glifo del botón grande del reproductor (`PlayerPresentation`): cada bug del 28 oct tiene aquí su prueba.
@MainActor
final class PlayerPresentationTests: XCTestCase {
    /// Un reloj que avanza a mano y un «dormir» que solo anota cuánto se pidió (y cede el turno).
    @MainActor final class Timing: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_000)
        nonisolated(unsafe) var waits: [TimeInterval] = []
        lazy var presentation = PlayerPresentation(clock: { [unowned self] in now },
                                                   sleep: { [unowned self] seconds in waits.append(seconds); await Task.yield() })
    }

    func testOpeningShowsLoadingUntilItPlaysAndNeverThePlayInBetween() async {
        let rig = Timing(), p = rig.presentation
        XCTAssertTrue(p.showsLoading, "al abrir, la carga desde el primer cuadro")
        p.update(.now, playing: false, videoID: "e1")   // buscando versión, cargando
        XCTAssertTrue(p.showsLoading)
        p.update(.none, playing: true, videoID: "e1")   // ya suena
        XCTAssertFalse(p.showsLoading)
    }

    func testPausingAndResumingNeverShowLoading() async {
        let rig = Timing(), p = rig.presentation
        p.update(.none, playing: true, videoID: "e1")
        rig.now += 30
        p.update(.soon, playing: false, videoID: "e1")   // un instante de búfer al seguir
        p.update(.none, playing: true, videoID: "e1")    // y ya suena: se cancela
        await p.settle()
        XCTAssertFalse(p.showsLoading)
    }

    func testAStallWhilePlayingShowsLoadingAfterAMoment() async {
        let rig = Timing(), p = rig.presentation
        p.update(.none, playing: true, videoID: "e1")
        rig.now += 30
        p.update(.soon, playing: false, videoID: "e1")
        await p.settle()
        XCTAssertTrue(p.showsLoading)
        XCTAssertEqual(rig.waits.last, PlayerPresentation.stallDelay, "ya sonando de rato: un segundo")
    }

    func testInTheFirstSecondsItWaitsLonger() async {
        let rig = Timing(), p = rig.presentation
        p.update(.none, playing: true, videoID: "e1")
        rig.now += 2   // el motor hace sus ajustes al arrancar
        p.update(.soon, playing: false, videoID: "e1")
        await p.settle()
        XCTAssertEqual(rig.waits.last, PlayerPresentation.settleDelay)
    }

    func testANewEpisodeStartsWithLoadingAgain() async {
        let rig = Timing(), p = rig.presentation
        p.update(.none, playing: true, videoID: "e1")
        p.update(.now, playing: false, videoID: "e2")
        XCTAssertTrue(p.showsLoading)
    }

    func testTheGlyphFollowsYourTapAtOnceAndTheEngineOnlyIfItLasts() async {
        let rig = Timing(), p = rig.presentation
        p.update(.none, playing: true, videoID: "e1")   // ya cargó
        p.userToggled(toPlaying: false)
        XCTAssertFalse(p.showsPlaying, "tocaste pausa: cambia ya")
        var engine = true
        p.engineChanged { engine }   // el motor arranca solo (otro dispositivo, Siri)
        engine = false                // y se detiene un instante: al asentarse dice lo que de verdad pasa
        await p.settle()
        XCTAssertFalse(p.showsPlaying)
        XCTAssertEqual(rig.waits.last, PlayerPresentation.glyphSettle)
        p.engineChanged { true }
        p.userToggled(toPlaying: false)   // tocar cancela lo que el motor iba a cambiar
        await p.settle()
        XCTAssertFalse(p.showsPlaying)
    }

    func testWhileLoadingTheGlyphDoesNotFlipAndEndsOnPause() async {
        let rig = Timing(), p = rig.presentation
        p.update(.now, playing: false, videoID: "e1")
        p.engineChanged { false }   // el motor se detiene un instante mientras carga…
        await p.settle()
        XCTAssertTrue(p.showsPlaying, "…y el glifo no se entera (antes: carga → play → pausa)")
        p.update(.none, playing: true, videoID: "e1")
        XCTAssertFalse(p.showsLoading)
        XCTAssertTrue(p.showsPlaying, "al terminar de cargar dice pausa: va a sonar")
    }

    func testTheLoadKindComesFromThePlayerState() async throws {
        let rig = try playerRig()
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now, "sin haber sonado")
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .none)
        await rig.model.handle(rig.playing(10, state: .buffering))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .soon)
        await rig.model.handle(rig.playing(10, state: .paused))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .none, "en pausa, nada")
        await rig.model.togglePlay()
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .soon, "pediste play y no avanza")
    }

    private func playerRig() throws -> Rig {
        let r = try Rig()
        r.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [r.stream("best")]]
        return r
    }
}
