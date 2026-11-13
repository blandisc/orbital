import XCTest

/// Recorridos para revisar a ojo lo nuevo (2 nov 2026): cada uno hace un gesto y se graba aparte con `simctl io recordVideo`.
/// Verifican lo mínimo (que la app responda); el veredicto del movimiento es el video.
final class PasadaQAUITests: XCTestCase {
    private var app: XCUIApplication!
    private let base = ["-demo", "-demo-mute", "-demo-trakt", "-demo-tmdb", "-demo-console", "-demo-airings", "-demo-because", "-demo-appearance", "dark"]

    private func launch(_ extra: [String]) {
        app = XCUIApplication()
        app.launchArguments = base + extra
        app.launch()
    }

    /// Tocar una tarjeta de «Seguir viendo»: el reproductor crece desde ella; al cerrar, regresa a ella.
    func testReproductorNaceDeSuTarjeta() {
        launch(["-demo-tab", "0", "-demo-no-idle"])
        let card = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Oficina' OR label CONTAINS 'Breaking'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "hay tarjetas en Seguir viendo")
        sleep(2)
        card.tap()
        let close = app.buttons["player-close"]
        if !close.waitForExistence(timeout: 8) { app.tap() }
        XCTAssertTrue(close.waitForExistence(timeout: 8), "se abrió el reproductor")
        sleep(3)
        if !close.isHittable { app.tap() }
        close.tap()
        sleep(3)
        XCTAssertTrue(card.waitForExistence(timeout: 8), "regresó a Inicio")
    }

    /// Jalar Inicio hacia abajo y sostener: la luna de Orbital.
    func testTirarParaActualizar() {
        launch(["-demo-tab", "0", "-demo-no-idle"])
        sleep(6)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62)), withVelocity: .slow, thenHoldForDuration: 1.5)
        sleep(3)
        XCTAssertTrue(app.buttons["home-all-continue"].waitForExistence(timeout: 8), "Inicio sigue ahí después de actualizar")
    }

    /// En la ficha, mantener el dedo en el arte y moverlo: se inclina con un brillo.
    func testInclinarElArteDeLaFicha() {
        launch(["-demo-tab", "0", "-demo-title", "series:tt0386676"])
        sleep(7)
        let art = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        art.press(forDuration: 0.5, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.32)), withVelocity: .slow, thenHoldForDuration: 1.2)
        sleep(2)
        art.press(forDuration: 0.5, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.18)), withVelocity: .slow, thenHoldForDuration: 1.2)
        sleep(2)
    }

    /// Una fila hasta el final: rebota (y en el iPhone, el golpe en la mano).
    func testFinDeUnaFila() {
        launch(["-demo-tab", "0", "-demo-no-idle"])
        let head = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Sugerencias para ti'")).firstMatch
        for _ in 0..<12 where !(head.exists && head.isHittable && head.frame.minY < app.frame.height * 0.4) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(head.waitForExistence(timeout: 5))
        let y = head.frame.maxY + 90
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for _ in 0..<6 {
            origin.withOffset(CGVector(dx: app.frame.width * 0.9, dy: y)).press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.05, dy: y)))
        }
        sleep(2)
    }

    /// Explorar al abrir: los estantes entran escalonados.
    func testExplorarEntraEscalonado() {
        launch(["-demo-tab", "1", "-demo-mode", "lists"])
        sleep(8)
        app.swipeUp(velocity: .slow)
        sleep(3)
    }

    /// Lo que ves: las barras y la dona se arman; cambiar de periodo las arma otra vez.
    func testLoQueVesSeArma() {
        launch(["-demo-tab", "1", "-demo-open", "watching"])
        sleep(7)
        let year = app.buttons["Año"].firstMatch
        if year.waitForExistence(timeout: 5) { year.tap() }
        sleep(4)
        app.swipeUp(velocity: .slow)
        sleep(3)
    }
}
