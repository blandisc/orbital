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

    /// El bug del 29 oct: carga → pausa → play → carga → play con el video sonando. Al terminar cualquier carga, el glifo
    /// dice lo que pasa, aunque el motor lo haya volteado a medias.
    func testAfterAStallTheGlyphSaysPauseIfItPlays() async {
        let rig = Timing(), p = rig.presentation
        p.update(.now, playing: false, videoID: "e1")
        p.update(.none, playing: true, videoID: "e1")
        XCTAssertTrue(p.showsPlaying, "carga → pausa")
        rig.now += 2
        p.engineChanged { false }   // el motor se detiene un instante antes de que salga la carga: el glifo se voltea a play…
        await p.settle()
        p.update(.soon, playing: true, videoID: "e1")   // …se atora llenando el búfer
        await p.settle()
        XCTAssertTrue(p.showsLoading)
        p.engineChanged { true }    // vuelve a sonar mientras se ve la carga: esto solo no cambia el glifo
        p.update(.none, playing: true, videoID: "e1")   // y termina la carga, sonando
        await p.settle()
        XCTAssertFalse(p.showsLoading)
        XCTAssertTrue(p.showsPlaying, "suena: el botón dice pausa, no play")
    }

    func testIfItEndsLoadingPausedTheGlyphSaysPlay() async {
        let rig = Timing(), p = rig.presentation
        p.update(.now, playing: false, videoID: "e1")
        p.update(.none, playing: false, videoID: "e1")   // volvió a la app en pausa
        XCTAssertFalse(p.showsPlaying)
    }

    func testTheLoadKindComesFromThePlayerState() async throws {
        let rig = try playerRig()
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now, "sin haber sonado")
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(10))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now, "sonó, pero hasta que corra unos segundos sigue la carga")
        await rig.model.handle(rig.playing(10.6))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .none)
        await rig.model.handle(rig.playing(10.6, state: .buffering))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .soon)
        await rig.model.handle(rig.playing(10, state: .paused))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .none, "en pausa, nada")
        await rig.model.togglePlay()
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .soon, "pediste play y no avanza")
    }

    /// El bug que no quedaba (29 oct): el motor dice «suena» a los 3 s con casi nada en el búfer y enseguida se detiene a llenarlo
    /// (o recarga para cambiar la pista de audio). Se veía carga → pausa → carga → pausa. La carga no se quita hasta que el video
    /// corre de verdad: así se ve carga → pausa, nada más. Y se quita en cuanto corre (medio segundo): con 2 s el video ya sonaba
    /// con la ruedita encima.
    func testTheLoadStaysUntilTheVideoReallyRuns() async throws {
        let rig = try playerRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0))
        XCTAssertTrue(rig.model.hasPlayed)
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now, "el primer «suena» del motor no quita la carga")
        await rig.model.handle(rig.playing(0.4, state: .buffering))   // se detiene a llenar el búfer
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now, "sigue la misma carga, no una nueva")
        await rig.model.handle(rig.playing(0.4, state: .loading))     // o recarga entera por la pista de audio
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now)
        await rig.model.handle(rig.playing(0.45))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now, "todavía no avanzó lo suficiente")
        await rig.model.handle(rig.playing(0.6))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .none, "corre: pausa, sin esperar 2 s con el video sonando")
        XCTAssertTrue(rig.model.playbackSettled)
        await rig.model.handle(rig.playing(0.6, state: .buffering))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .soon, "ya corriendo, un atorón es la regla de siempre")
    }

    func testPausingRightAfterItStartsEndsTheLoad() async throws {
        let rig = try playerRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0))
        await rig.model.togglePlay()   // pausaste en el primer segundo
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .none, "pediste pausa: ya no es carga")
        await rig.model.handle(rig.playing(0.3, state: .paused))
        XCTAssertTrue(rig.model.playbackSettled)
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .none)
    }

    func testAJumpWhileStartingCountsFromTheNewPoint() async throws {
        let rig = try playerRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0))
        await rig.model.seek(to: 600)
        await rig.model.handle(rig.playing(600.3))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now, "saltaste al arrancar: el medio segundo cuenta desde ahí")
        await rig.model.handle(rig.playing(600.6))
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .none)
    }

    func testANewVideoStartsUnsettled() async throws {
        let rig = try playerRig()
        await rig.model.begin(rig.request())
        await rig.model.handle(rig.playing(0))
        await rig.model.handle(rig.playing(5))
        XCTAssertTrue(rig.model.playbackSettled)
        await rig.model.begin(rig.request())
        XCTAssertFalse(rig.model.playbackSettled)
        XCTAssertEqual(PlayerPresentation.loadKind(rig.model), .now)
    }

    private func playerRig() throws -> Rig {
        let r = try Rig()
        r.http.json["https://a.example/stream/series/tt0386676%3A1%3A1.json"] = ["streams": [r.stream("best")]]
        return r
    }
}
