import XCTest

/// La galería de widgets de Orbital, como la ve quien los agrega: abre la app en modo demostración (deja el snapshot de
/// ejemplo con sus imágenes en el App Group), va a la pantalla de inicio, abre «Agregar widget», busca Orbital y captura cada
/// página (cada widget en cada tamaño). Las vistas previas leen el mismo snapshot que el widget puesto. Con `SHOTS=<carpeta>`
/// guarda las capturas ahí. Es para revisar el diseño: no da veredicto sobre la app.
final class WidgetGalleryUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testCaptureEveryWidgetInTheGallery() throws {
        // Primero Inicio (deja «Lo siguiente para ti», «Lo nuevo de lo tuyo» y «Un Simpson del día») y luego Explorar (deja las
        // listas del mosaico). Cada uno espera a que se bajen y reduzcan las imágenes.
        let app = XCUIApplication()
        let base = ["-demo", "-demo-widget", "sample", "-demo-no-idle", "-demo-console", "-demo-trakt", "-demo-mode", "lists"]
        app.launchArguments = base + ["-demo-tab", "0"]
        app.launch()
        sleep(15)
        app.terminate()
        app.launchArguments = base + ["-demo-tab", "1"]
        app.launch()
        sleep(20)
        XCUIDevice.shared.press(.home)
        sleep(2)

        // Mantener presionado un hueco de la pantalla de inicio: entra a editar.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 1.6)
        sleep(1)
        let edit = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["Edit", "Editar"])).firstMatch
        if edit.waitForExistence(timeout: 4) { edit.tap(); sleep(1) }
        let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'widget'")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "no apareció «Agregar widget»")
        add.tap()
        sleep(2)
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "no apareció la búsqueda de widgets")
        search.tap()
        search.typeText("Orbital")
        sleep(2)
        shot("busqueda")
        // El primer resultado bajo el buscador es Orbital (lo único que coincide). Se toca por su lugar: en iOS 27 el renglón no
        // se deja encontrar por su nombre (con «contiene» o «igual» se tocaba Contactos, de la lista sin filtrar).
        XCTAssertTrue(springboard.staticTexts["Orbital"].firstMatch.waitForExistence(timeout: 6), "Orbital no salió en la búsqueda de widgets")
        let first = search.frame.maxY + 40
        springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: springboard.frame.width / 2, dy: first)).tap()
        sleep(3)
        for page in 0..<14 {
            shot("galeria-\(page)")
            springboard.swipeLeft()
            sleep(2)
        }
    }

    /// «Viendo en la TV»: con la TV de mentira (`-demo-tv-now`) la actividad nace sola; se captura la isla en la pantalla de
    /// inicio y la pantalla bloqueada.
    func testCaptureTheTVLiveActivity() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demo", "-demo-tv-now", "-demo-no-idle"]
        app.launch()
        sleep(12)
        XCUIDevice.shared.press(.home)
        sleep(3)
        shot("tv-isla")
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(2)
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))   // la pantalla se enciende bloqueada
        sleep(3)
        shot("tv-bloqueo")
    }

    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name; a.lifetime = .keepAlways
        add(a)
        if let dir = ProcessInfo.processInfo.environment["SHOTS"] {
            try? s.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
