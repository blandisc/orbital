import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// Dos correcciones de Fernando (12 nov 2026):
/// - «Asegúrate que no salga saltar intro hasta que ya esté cargada la serie».
/// - El aviso de «probando otra versión» no dice «sigue en el mismo punto» si la anterior nunca arrancó: «no es como que
///   falle y que luego busques otra para que continúe. Es que esa no estaba disponible».
extension PlayerModelTests {
    func testSkipIntroHidesWhileTheVideoIsLoading() async throws {
        let rig = try twoSources()
        let model = PlayerModel(engine: rig.engine, finder: rig.finder, watch: rig.watch, titlePrefs: rig.titlePrefs, settings: rig.settings, clock: { rig.clock.now },
                                skipSegments: { _ in SkipSegments(intro: 60...120, recap: nil, credits: nil) })
        await model.begin(rig.request())
        await model.handle(rig.playing(10))
        try await Task.sleep(nanoseconds: 50_000_000)   // las marcas llegan aparte
        await model.handle(rig.playing(70))
        XCTAssertEqual(model.skipIntroTo, 120, "ya corre dentro de la intro: hay botón")
        await model.handle(rig.playing(70, state: .buffering))
        XCTAssertNil(model.skipIntroTo, "llenando el búfer no hay qué saltar")
        await model.handle(rig.playing(70, state: .loading))
        XCTAssertNil(model.skipIntroTo, "cargando tampoco")
        await model.handle(rig.playing(71))
        XCTAssertEqual(model.skipIntroTo, 120, "en cuanto vuelve a correr, vuelve el botón")
    }

    func testTheRetryNoticeOnlyPromisesTheSamePointIfItHadPlayed() async throws {
        // Nunca arrancó (lo común: Real-Debrid no la tenía lista): no hay punto que conservar.
        let never = try twoSources()
        await never.model.begin(never.request())
        never.clock.advance(PlaybackRules.startupTimeout + 1)
        await never.model.tick()
        await never.model.waitForTransition()
        XCTAssertEqual(never.model.notice, .triedAnotherSource(attempt: 2, of: 2))
        XCTAssertFalse(never.model.retriedAfterPlaying, "«La anterior no estaba disponible»")
        // Ya sonaba y falló: la siguiente sí sigue donde ibas.
        let played = try twoSources()
        await played.model.begin(played.request())
        await played.model.handle(played.playing(300))
        await played.model.handle(played.playing(300, state: .failed("403")))
        await played.model.waitForTransition()
        XCTAssertTrue(played.model.retriedAfterPlaying, "«La anterior se cortó. Sigue en el mismo punto»")
    }
}
