import XCTest

/// El sistema de tamaños de la Mac (Fernando, 16 nov 2026: «haz esa misma revisión en cuanto a tamaños de fuente y todos los
/// botones… crea reglas para que… queden registradas una vez y se apliquen siempre»). Regla en `docs/ios-interfaz.md`
/// § «La escala de la Mac»: el tamaño de la Mac se decide en un solo lugar (`DS.Mac`) y se pone una sola vez en la raíz
/// (`macDefaults`, en RootView). Ninguna pantalla pide su tamaño de control a mano: lo pide con `dsControlSize`, que en la Mac sube uno.
extension DesignRulesTests {
    func testMacSizesAreDecidedOnce() throws {
        let files = try sources(["Design", "Screens"])
        // 1. Ningún `.controlSize(` suelto: en la Mac saldría del tamaño del iPad (24–30 px).
        XCTAssertEqual(hits(#"\.controlSize\("#, in: files, unless: "func dsControlSize"), [],
                       "Pide el tamaño con `.dsControlSize(…)`: en la Mac sube uno solo")
        // 2. Ningún tope de letra por debajo del de la Mac: le quitaría la escala a esa pantalla.
        XCTAssertEqual(hits(#"dynamicTypeSize\(\.\.\.(DynamicTypeSize)?\.(xSmall|small|medium|large|xLarge)\)"#, in: files), [],
                       "Un tope de letra menor que `DS.Mac.systemType` encoge la Mac")
        // 3. La escala se pone una vez, en la raíz (`macDefaults` en RootView), con la letra del sistema y el control de la Mac.
        let calls = files.flatMap { $0.lines }.filter { $0.contains(".macDefaults()") }
        XCTAssertEqual(calls.count, 1, "`.macDefaults()` va una sola vez, en la raíz")
        let strip = try XCTUnwrap(files.first { $0.name == "MacTabStrip.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(strip.contains(".dynamicTypeSize(DS.Mac.systemType)") && strip.contains(".controlSize(DS.Mac.controlDefault)"),
                      "`macDefaults` pone la letra del sistema y el control de la Mac")
        // 4. La escala de la Mac: lo más chico no baja de 13 pt (× 1.25, ~12.5 px en pantalla) y los controles suben uno.
        let mac = try XCTUnwrap(files.first { $0.name == "Tokens+Mac.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(mac.contains(".footnote: 15, .caption: 14, .caption2: 13,"), "La letra chica de la Mac no baja de 13 pt")
        XCTAssertTrue(mac.contains("static let systemType: DynamicTypeSize = .xxLarge"), "La letra del sistema crece en la Mac")
        for step in ["case .mini: return .small", "case .small: return .regular", "case .regular: return .large"] {
            XCTAssertTrue(mac.contains(step), "En la Mac cada control sube un tamaño: \(step)")
        }
    }
}
