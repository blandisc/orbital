import XCTest

/// Un aviso arriba a la vez en el reproductor (Fernando, 23 nov 2026: al pellizcar, «Suelta para llenar la pantalla» chocaba
/// con otro aviso). Todos los avisos de texto de arriba pasan por `topNotice` (que elige uno) y se dibujan con `topPill` o en su
/// caso del `switch`; ninguno se pinta por su cuenta leyendo su estado. Regla en `docs/ios-interfaz.md` § «Un aviso arriba a la vez».
extension DesignRulesTests {
    func testPlayerTopNoticesShowOneAtATime() throws {
        let player = try sources(["Screens"]).filter { $0.name.hasPrefix("PlayerScreen") || $0.name == "PlayerTopNotice.swift" }
        XCTAssertFalse(player.isEmpty)
        var wrong: [String] = []
        var pills = 0
        for file in player {
            for (i, line) in file.lines.enumerated() {
                let code = line.components(separatedBy: "//").first ?? line
                if code.contains("DSToastPill(") {
                    pills += 1
                    if file.name != "PlayerTopNotice.swift" { wrong.append("\(file.name):\(i + 1) píldora fuera de `topPill`") }
                }
                // Dibujar un aviso porque su estado está puesto, sin pasar por `topNotice`, es lo que hacía chocar a dos.
                let drawsOnItsOwn = "(if let [a-zA-Z]+ = |if |else if )(notices\\.notice|notices\\.subtitleToast|framing\\.zoomToast|framing\\.framedToast|framing\\.pinching)\\b"
                if file.name != "PlayerTopNotice.swift", !code.contains("withAnimation"), code.range(of: drawsOnItsOwn, options: .regularExpression) != nil {
                    wrong.append("\(file.name):\(i + 1) aviso de arriba sin `topNotice`")
                }
            }
        }
        XCTAssertEqual(pills, 1, "Una sola píldora de arriba (`topPill`) para todos los avisos breves del reproductor")
        XCTAssertEqual(wrong, [], "Los avisos de arriba del reproductor salen de uno en uno por `topNotice`")
    }

    /// Regla (26 nov 2026): un aviso del reproductor nunca tapa un botón ni la carga. En vertical va abajo, en el espacio libre
    /// (`noticeSlot`); arriba caía sobre la ruedita de carga.
    func testPlayerNoticesNeverCoverTheLoadingButton() throws {
        let files = try sources(["Screens"])
        let slot = try XCTUnwrap(files.first { $0.name == "PlayerTopNotice.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(slot.contains("VStack { Spacer(); content }"), "en vertical, el aviso va abajo")
        XCTAssertTrue(slot.contains("noticeSlot(DSToastPill("), "las píldoras pasan por el mismo lugar")
        let gestures = try XCTUnwrap(files.first { $0.name == "PlayerScreen+Gestos.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(gestures.contains("noticeSlot(\n                Toast("), "el aviso con botones pasa por el mismo lugar")
    }
}

