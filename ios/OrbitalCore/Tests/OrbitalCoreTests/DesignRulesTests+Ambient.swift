import XCTest

/// En la Mac nada se mueve solo (Fernando, 22 nov 2026: «se siente súper lenta, ni siquiera la puedo mover… está inusable»).
/// El cielo, el muro de Explorar y los canales que se deslizan ponían al compositor de la Mac a 60–95 % con Orbital en reposo
/// (su monitor va a 165 Hz). Regla en `docs/ios-interfaz.md` § «En la Mac nada se mueve solo».
extension DesignRulesTests {
    /// Todo archivo con un adorno que se mueve sin que lo toques (un reloj de cuadros, una animación sin fin, el muro que baja)
    /// pregunta por `ThisDevice.ambientMotion`. Fuera: las lecciones y la bienvenida (se ven una vez), el reproductor, la
    /// ruleta y la luna de «actualizar» (corren solo mientras haces algo).
    func testAmbientMotionStaysStillOnTheMac() throws {
        let patterns = [#"TimelineView\(\.animation"#, #"CoreDrift\("#, #"SkySchedule\("#, #"repeatCount = \.infinity"#, #"\.repeatForever\("#, #"DS\.Timing\.mosaicDrift"#]
        let allowed = ["Lessons/", "Onboarding/", "Player", "Roulette", "RefreshOrbit", "Tokens+Lessons", "Brand", "MosaicBench"]
        var missing: [String] = []
        for file in try sources() where !allowed.contains(where: { file.path.contains($0) }) {
            let moves = patterns.contains { p in !hits(p, in: [file]).isEmpty }
            if moves, !file.lines.contains(where: { $0.contains("ThisDevice.ambientMotion") }) { missing.append(file.path) }
        }
        XCTAssertEqual(missing, [], "Se mueven solos sin preguntar por ThisDevice.ambientMotion (en la Mac, quietos)")
    }

    /// Cargar se ve igual en toda la app (Fernando, 23 nov 2026: en Descargas salía la ruedita del sistema y en Inicio la luna
    /// de Orbital): tirar para actualizar es siempre `orbitalRefreshable` (o `orbitalRefreshableList` en una lista), nunca
    /// `.refreshable` del sistema.
    func testPullToRefreshIsAlwaysTheOrbit() throws {
        let used = try sources().filter { !$0.path.contains("RefreshOrbit") }.flatMap { f in f.lines.filter { $0.contains(".refreshable {") || $0.contains(".refreshable{") }.map { "\(f.path): \($0)" } }
        XCTAssertEqual(used, [], "Tirar para actualizar con la ruedita del sistema: usa orbitalRefreshable / orbitalRefreshableList")
    }
}
