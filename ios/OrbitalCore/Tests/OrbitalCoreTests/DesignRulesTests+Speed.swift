import XCTest

/// Cambiar de pantalla no relee nada ni vuelve a pintar lo que no cambió (Fernando, 22 nov 2026: «le pico en Explorar y se
/// tardan 3 segundos en cambiar pantalla… es inaceptable»). Una muestra del cambio de pestaña en la Mac: 16 % releyendo
/// `Localizable.strings` del disco por cada texto (el idioma de la app no era el del sistema) y cada póster repintado porque
/// un valor del entorno llevaba acciones dentro. Regla en `docs/ios-interfaz.md` § «Revisión pantalla por pantalla en la Mac».
extension DesignRulesTests {
    func testSwitchingScreensRereadsNothingAndRepaintsOnlyWhatChanged() throws {
        // 1 · Lo que viaja por el entorno lleva solo datos; lo que hace vive aparte (V9, como `RemoteOpener`). La tira de
        // pestañas de la Mac (`MacTabs`) se queda: la leen solo sus renglones de arriba y cambia con la pestaña de todos modos.
        // Tampoco cuentan los que pone una sola pantalla para lo suyo (Ajustes, una historia, el reproductor): no los lee
        // cada póster de las cuatro pestañas.
        let files = try sources(["Design", "Screens"])
        let entry = try NSRegularExpression(pattern: #"@Entry var \w+: (\w+)\?"#)
        let closure = try NSRegularExpression(pattern: #"^\s*(let|var) \w+: (@Sendable )?\("#)
        var types = Set<String>()
        for file in files { for line in file.lines {
            let range = NSRange(line.startIndex..., in: line)
            if let m = entry.firstMatch(in: line, range: range), let r = Range(m.range(at: 1), in: line) { types.insert(String(line[r])) }
        } }
        types.subtract(["MacTabs", "SettingsPane", "SettingsSubPane", "StoryTurn", "PlayerCommands"])
        var offenders: [String] = []
        for file in files {
            var inside: String?
            for line in file.lines {
                if let name = types.first(where: { line.hasPrefix("struct \($0)") && line.contains("{") }) { inside = name; continue }
                if inside != nil, line.hasPrefix("}") { inside = nil; continue }
                if let name = inside, closure.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    offenders.append("\(file.name) · \(name): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertEqual(offenders, [], "Un valor del entorno con acciones dentro se da por cambiado en cada pasada y repinta todo lo que lo lee")

        // 2 · El idioma de Orbital es el preferido de la app y su `Locale` es el del sistema cuando coinciden: con otro, cada
        // texto se resolvía leyendo la tabla del disco en el hilo principal.
        let app = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/OrbitalApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains(#"forKey: "AppleLanguages")"#), "OrbitalApp ya no pone el idioma de Orbital como preferido de la app")
        let env = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/AppEnvironment.swift"), encoding: .utf8)
        XCTAssertTrue(env.contains("? Locale.current : Locale(identifier: language)"), "uiLocale debe ser Locale.current cuando ya habla el idioma de Orbital")

        // 3 · Desplazarse no vuelve a armar la pantalla: lo que se anota al pasar (qué sección ves en Explorar) va a una caja
        // que lee solo quien lo enseña. Como estado de la pantalla entraba en un ciclo (98 % sin tocar nada, 22 nov 2026).
        let spy = try XCTUnwrap(files.first { $0.name == "CollectionsView.swift" })
        let body = spy.lines.drop { !$0.contains("struct SectionSpy") }.prefix(14)
        XCTAssertFalse(body.contains { $0.contains("@Binding") }, "SectionSpy no escribe un estado de la pantalla: usa SectionTracker")

        // 4 · Nada que se pinta le pregunta al disco cuánto espacio queda: lo sabe `DiskSpace`, que lo mide por detrás (abrir la
        // ficha de una serie tardaba 125 ms en la Mac por esa pregunta en su menú de descargas, 22 nov 2026).
        let asking = try sources(["Design", "Screens", "App", "Platform"]).filter { file in
            file.name != "DeviceInfo.swift" && file.lines.contains { $0.contains(".volumeAvailableCapacity") }
        }.map(\.name)
        XCTAssertEqual(asking, [], "Pide el espacio libre con DiskSpace.freeBytes(): no le preguntes al disco al pintar")
    }
}
