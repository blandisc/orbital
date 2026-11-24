import XCTest

/// Lo que se abre encima no truena la app (23 nov 2026, la 2491 en la Mac: abrir una hoja con una película puesta).
/// Regla en `docs/ios-interfaz.md` § «El replanteamiento de la Mac».
extension DesignRulesTests {
    /// En la Mac la hoja arma lo que muestra antes de heredar `AppEnvironment` (como las cubiertas, `+Covers`): toda hoja
    /// pasa por `appSheet` (Screens/AppSheet.swift), que se la pone a mano. Un `.sheet(` suelto vuelve a tronar en la Mac.
    func testSheetsPassTheApp() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
        // Ajustes lo está tocando otra sesión (23 nov): sus dos hojas pasan a `appSheet` y se borra de aquí.
        let pending: Set<String> = []
        var loose: [String] = []
        var sheets = 0
        for case let file as URL in files where file.pathExtension == "swift" && file.lastPathComponent != "AppSheet.swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                if line.contains(".appSheet(") { sheets += 1 }
                if line.contains(".sheet("), !pending.contains(file.lastPathComponent) { loose.append("\(file.lastPathComponent):\(i + 1)") }
            }
        }
        XCTAssertGreaterThanOrEqual(sheets, 50, "se leyeron las hojas de ios/App/Sources")
        XCTAssertEqual(loose, [], "Hoja sin la app: usa `.appSheet(` (en la Mac la app truena al abrirla)")

        let wrapper = try String(contentsOf: root.appendingPathComponent("Screens/AppSheet.swift"), encoding: .utf8)
        XCTAssertTrue(wrapper.contains("{ sheet().environment(env) }"), "`appSheet(isPresented:)` pone la app en la hoja")
        XCTAssertTrue(wrapper.contains("{ sheet($0).environment(env) }"), "`appSheet(item:)` pone la app en la hoja")
        let rootView = try String(contentsOf: root.appendingPathComponent("Screens/RootView.swift"), encoding: .utf8)
        XCTAssertTrue(rootView.contains("{ sidePanel.environment(env) }"), "el panel de la derecha (inspector) también la lleva")
    }

    /// Un `ViewThatFits` que elige entre una lista (`ForEach`) se rearma con `.id(…)` cuando cambian sus opciones: en la Mac
    /// (la 2458, 22 nov 2026) tronó cuatro veces seguidas cuando la tira de pósters de Explorar cambió cuántas opciones tenía.
    func testListChoicesRebuildWhenTheyChange() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
        var bad: [String] = []
        var found = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            let code = try String(contentsOf: file, encoding: .utf8)
            var search = code.startIndex
            while let hit = code.range(of: "ViewThatFits(in: ", range: search..<code.endIndex) {
                search = hit.upperBound
                guard let open = code[hit.upperBound...].firstIndex(of: "{"), let close = Self.closing(code, open) else { continue }
                let body = code[code.index(after: open)..<close]
                guard Self.topLevel(body).contains("ForEach(") else { continue }
                found += 1
                let after = code[code.index(after: close)...].drop { $0 == " " || $0 == "\n" }
                if !after.hasPrefix(".id(") {
                    bad.append("\(file.lastPathComponent):\(code[..<hit.lowerBound].components(separatedBy: "\n").count)")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(found, 2, "se leyeron los ViewThatFits con lista")
        XCTAssertEqual(bad, [], "ViewThatFits con ForEach sin `.id(…)` de sus opciones")
    }

    /// La llave que cierra la que abre en `open`.
    private static func closing(_ code: String, _ open: String.Index) -> String.Index? {
        var depth = 0
        var i = open
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 } else if code[i] == "}" {
                depth -= 1
                if depth == 0 { return i }
            }
            i = code.index(after: i)
        }
        return nil
    }

    /// Lo que está en el primer nivel del bloque (sin lo de las llaves de adentro).
    private static func topLevel(_ body: Substring) -> String {
        var depth = 0
        var out = ""
        for ch in body {
            if ch == "{" { depth += 1 } else if ch == "}" { depth -= 1 } else if depth == 0 { out.append(ch) }
        }
        return out
    }
}
