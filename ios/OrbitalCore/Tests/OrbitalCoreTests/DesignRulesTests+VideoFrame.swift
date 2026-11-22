import XCTest

/// El recuadro del video sigue a la imagen de verdad y parado no hay zoom (Fernando, 21 nov 2026: *It's Always Sunny* con rayas
/// negras pintadas a los lados y «hacia arriba… hace como un zoom raro»). Regla en `docs/ios-interfaz.md` § «El video, del
/// tamaño de su imagen».
extension DesignRulesTests {
    func testTheEngineGetsTheFrameZoomAndPortraitHasNoZoom() throws {
        var wrong: [String] = []
        for file in try sources(["Screens"]) {
            for (i, line) in file.lines.enumerated() {
                // Al motor siempre `engineZoom` (el que quita las rayas pintadas), nunca el zoom del botón.
                if line.contains("engine.setZoom("), !line.contains("engine.setZoom(engineZoom)") { wrong.append("\(file.name):\(i + 1) motor sin engineZoom") }
                // Parado no se guarda ni se pone otro zoom.
                if line.contains("portraitZoom") || line.contains("fillsPortrait") { wrong.append("\(file.name):\(i + 1) zoom en vertical") }
                if line.contains("var zoom: VideoZoom"), !line.contains(": .fit }") { wrong.append("\(file.name):\(i + 1) el zoom parado no es .fit") }
                if line.contains("var portraitAspect: Double"), !line.contains("pictureAspect ??") { wrong.append("\(file.name):\(i + 1) recuadro sin pictureAspect") }
            }
        }
        XCTAssertEqual(wrong, [], "El video: al motor `engineZoom`, parado sin zoom y el recuadro con la imagen de verdad")
    }
}
