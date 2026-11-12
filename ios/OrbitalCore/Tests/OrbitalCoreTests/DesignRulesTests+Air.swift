import XCTest

/// El aire parejo (Fernando, 11 nov 2026: «"Guardar / Viendo" como que tiene muy poco espacio abajo… establecer una regla
/// para que ya no vuelva a pasar»). Regla en `docs/ios-interfaz.md` § «Aire parejo»: todo contenedor con fondo tiene el mismo
/// aire arriba y abajo de su contenido, y ese aire sale de un token. Estas pruebas la cuidan:
/// - las tarjetas de acción (ícono + nombre, en un renglón) salen de una sola pieza, `ActionTileLabel`, y nadie las arma a mano;
/// - esa pieza usa un solo relleno vertical (`padding(.vertical, …)` de un token) y no tiene renglón de estado (F1, 12 nov
///   2026: ese renglón dejaba huecos bajo «Descargar» y «Tráiler»; lo cuida también `DesignRulesTests+Actions.swift`);
/// - en `Design/`, un contenedor con fondo no lleva rellenos distintos arriba y abajo sin `ds-exception: <motivo>`.
extension DesignRulesTests {
    /// Las pantallas con tarjetas de acción: deben armarlas con la pieza del catálogo.
    static let actionTileScreens = ["Screens/TitleView.swift", "Screens/TitleView+Estado.swift", "Screens/TitleView+Descargas.swift",
                                    "Screens/TitleView+Watched.swift", "Screens/MiMediaView.swift",
                                    "Design/Remote.swift", "Screens/RemoteSheet.swift"]

    func testActionTilesComeFromTheCatalog() throws {
        let files = try sources(["Design", "Screens"])
        for path in Self.actionTileScreens {
            let file = try XCTUnwrap(files.first { $0.path == path }, "falta \(path)")
            XCTAssertTrue(file.lines.contains { $0.contains("ActionTileLabel(") }, "\(path) ya no usa `ActionTileLabel`: ¿se armó la tarjeta a mano?")
        }
        // Sus medidas son de la pieza: nadie más las usa para armar una tarjeta parecida.
        let tokens = #"DS\.ActionTile\.|DS\.TitleAction\.tile\b|DS\.Remote\.keyIcon\b"#
        check(hits(tokens, in: files) { $0.name == "TitleActions.swift" || $0.name.hasPrefix("Tokens") },
              "Las medidas de la tarjeta de acción solo las usa `ActionTileLabel` (TitleActions.swift)")
    }

    func testActionTileHasEvenAir() throws {
        let file = try XCTUnwrap(try sources(["Design"]).first { $0.name == "TitleActions.swift" })
        let text = file.lines.joined(separator: "\n")
        let start = try XCTUnwrap(text.range(of: "struct ActionTileLabel"))
        let end = text.range(of: "\nstruct ", range: start.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        let piece = String(text[start.lowerBound..<end])
        XCTAssertTrue(piece.contains("padding(.vertical, metrics.pad)"), "`ActionTileLabel` debe tener un solo relleno vertical (arriba = abajo) de su token")
        XCTAssertFalse(piece.range(of: #"padding\(\.(top|bottom)"#, options: .regularExpression) != nil, "`ActionTileLabel` no lleva rellenos sueltos arriba o abajo")
        // F1: un renglón. Sin `detail` ni renglón reservado: el estado lo dicen el nombre y el ícono («Guardada», lleno).
        XCTAssertNil(piece.range(of: #"\bdetail\b|reservesDetail"#, options: .regularExpression), "`ActionTileLabel` no lleva renglón de estado (F1: un solo renglón)")
        XCTAssertTrue(piece.contains("lineLimit(1)"), "el nombre de la tarjeta de la ficha va en un solo renglón")
    }

    /// Los rellenos de arriba y de abajo de cada contenedor con fondo en `Design/`: deben ser los mismos.
    func testContainersHaveEvenAir() throws {
        let files = try sources(["Design"])
        let background = try NSRegularExpression(pattern: #"\.(background|dsCard|glassEffect|dsGlass[A-Za-z]*|dsSurface[A-Za-z]*)\s*[({]"#)
        let padding = try NSRegularExpression(pattern: #"\.padding\((?:(?<edge>\.top|\.bottom|\.vertical|\.horizontal|\[[^\]]*\])\s*,\s*)?(?<amount>[^()]*(?:\([^()]*\)[^()]*)*)\)"#)
        var uneven: [String] = []
        for file in files where !isTokens(file) {
            var i = 0
            while i < file.lines.count {
                // Un renglón y los modificadores que le siguen («.algo» al principio): una sola pieza con su fondo.
                let first = i
                var statement = [file.lines[i]]
                while i + 1 < file.lines.count, file.lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(".") { i += 1; statement.append(file.lines[i]) }
                defer { i += 1 }
                let lines = statement.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                if statement.contains(where: { $0.contains("ds-exception:") }) { continue }
                let code = lines.map { $0.components(separatedBy: " //").first ?? $0 }.joined(separator: " ")
                let ns = NSRange(code.startIndex..., in: code)
                guard let last = background.matches(in: code, range: ns).last else { continue }
                var top: [String] = [], bottom: [String] = []
                for m in padding.matches(in: code, range: ns) where m.range.location < last.range.location {
                    let edge = Range(m.range(withName: "edge"), in: code).map { String(code[$0]) } ?? ""
                    let amount = Range(m.range(withName: "amount"), in: code).map { String(code[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
                    if amount.hasPrefix("EdgeInsets") {
                        let t = amount.range(of: #"top: *[^,)]+"#, options: .regularExpression).map { String(amount[$0].dropFirst(4)).trimmingCharacters(in: .whitespaces) } ?? "0"
                        let b = amount.range(of: #"bottom: *[^,)]+"#, options: .regularExpression).map { String(amount[$0].dropFirst(7)).trimmingCharacters(in: .whitespaces) } ?? "0"
                        top.append(t); bottom.append(b); continue
                    }
                    switch edge {
                    case ".top": top.append(amount)
                    case ".bottom": bottom.append(amount)
                    case ".horizontal": break
                    case "", ".vertical": top.append(amount); bottom.append(amount)
                    default:   // un conjunto: [.top, .horizontal]…
                        if edge.contains(".top") || edge.contains(".vertical") { top.append(amount) }
                        if edge.contains(".bottom") || edge.contains(".vertical") { bottom.append(amount) }
                    }
                }
                if top.sorted() != bottom.sorted() {
                    uneven.append("\(file.path):\(first + 1): arriba \(top.isEmpty ? "0" : top.joined(separator: " + ")) ≠ abajo \(bottom.isEmpty ? "0" : bottom.joined(separator: " + "))")
                }
            }
        }
        check(uneven, "Contenedores con fondo con distinto aire arriba que abajo (ver «Aire parejo» en docs/ios-interfaz.md; si es a propósito, `ds-exception: <motivo>`)")
    }
}
