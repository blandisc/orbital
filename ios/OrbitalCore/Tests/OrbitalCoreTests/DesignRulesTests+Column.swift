import XCTest

/// Lo que le queda a la pantalla (11 nov 2026): en el iPad acostado y en la Mac, el control de la TV se abre como panel a la
/// derecha y las pestañas se angostan. Inicio medía su portada con la ventana entera y, con el panel abierto, cambiaba de
/// alto y se recorría. Regla en `docs/ios-interfaz.md` § «Lo que le queda a la pantalla»: todo lo que va dentro de las
/// pestañas se acomoda con el ancho de la columna (`WindowMetrics.column`), nunca con el de la ventana (`WindowMetrics.size`).
/// El alto sí puede salir de la ventana (el panel no lo cambia). Lo que de verdad depende de la ventana (decidir si hay
/// panel, una hoja que flota encima, el reproductor a pantalla completa) lleva `ds-exception: <motivo>` en su renglón.
extension DesignRulesTests {
    func testLayoutsInsideTheTabsMeasureTheColumn() throws {
        let files = try sources(["Design", "Screens"])
        // `WindowMetrics.size` entero o su ancho; `.size.height` sola no cuenta.
        let window = #"WindowMetrics\.size(?!\.height\b)\b"#
        check(hits(window, in: files), "Dentro de las pestañas el ancho sale de `WindowMetrics.column` (sin el panel del control), no de `WindowMetrics.size`")
    }

    /// `containerRelativeFrame` mide su contenedor con el panel del control incluido (al ScrollView de una pestaña el panel le
    /// llega como margen seguro): la página de Inicio salía ~20 pt más ancha, recorrida a la izquierda y cortada de los dos
    /// lados. El ancho de una página sale de la columna (`WindowMetrics.column`, que miden las pestañas); medir el ScrollView
    /// tampoco sirve: con el panel crece con lo que tiene adentro. Donde sí sirve (un carrusel que mide su propia fila, la barra
    /// de arriba, una hoja) va con `ds-exception: <motivo>`.
    func testPagesDoNotTakeTheirWidthFromTheContainer() throws {
        let files = try sources(["Design", "Screens"])
        check(hits(#"\.containerRelativeFrame\("#, in: files), "Una página toma su ancho de la columna, no de `containerRelativeFrame` (mide también el panel del control)")
        let home = try XCTUnwrap(files.first { $0.name == "HomeView.swift" })
        XCTAssertTrue(home.lines.contains { $0.contains(".frame(width: WindowMetrics.column.width") }, "Inicio debe tomar el ancho de su página de la columna (`WindowMetrics.column`)")
    }

    /// La columna la miden las pestañas, antes del panel de la derecha: si el `.tracksColumnSize()` se va o queda después del
    /// `.inspector`, `WindowMetrics.column` vuelve a ser la ventana entera y la regla de arriba no sirve de nada.
    func testTheColumnIsMeasuredBeforeThePanel() throws {
        let root = try XCTUnwrap(try sources(["Screens"]).first { $0.name == "RootView.swift" })
        let code = root.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        let measure = try XCTUnwrap(code.firstIndex { $0.contains(".tracksColumnSize()") }, "RootView ya no mide la columna (`.tracksColumnSize()`)")
        let panel = try XCTUnwrap(code.firstIndex { $0.contains(".inspector(") }, "RootView ya no tiene el panel de la derecha")
        XCTAssertLessThan(measure, panel, "`.tracksColumnSize()` debe ir antes del `.inspector`: después mediría la ventana con el panel")
    }
}
