import XCTest

/// Las respuestas del sistema se arman fuera de la pantalla (13 nov 2026, la 2296: «la app truena al dar un comando de
/// voz»). Un cierre de permiso, de audio del micrófono o del reconocimiento de voz escrito dentro de una clase `@MainActor`
/// truena en Swift 6 cuando el sistema lo llama por otro hilo. Cada uno de estos va dentro de una función `nonisolated`.
/// Regla en `docs/ios-interfaz.md` § «Las respuestas del sistema se arman fuera de la pantalla».
extension DesignRulesTests {
    func testSystemCallbacksAreArmedOutsideTheMainActor() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
        // Las llamadas del sistema que contestan por otro hilo con un cierre.
        let calls = ["SFSpeechRecognizer.requestAuthorization {", ".installTap(onBus:", ".recognitionTask(with:",
                     "AVCaptureDevice.requestAccess(", "PHPhotoLibrary.requestAuthorization(", "CNContactStore().requestAccess("]
        var found = 0
        var bad: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where calls.contains(where: { line.contains($0) }) {
                found += 1
                // La función que la contiene: la última declaración `func` antes de la línea.
                let owner = lines[..<i].last(where: { $0.contains("func ") }) ?? ""
                if !owner.contains("nonisolated") { bad.append("\(file.lastPathComponent):\(i + 1)") }
            }
        }
        XCTAssertGreaterThanOrEqual(found, 3, "se encontraron las llamadas del dictado")
        XCTAssertEqual(bad, [], "Respuesta del sistema armada dentro de la pantalla (truena en Swift 6): va en una función `nonisolated`")
    }

    /// Un listón no recorta lo que crece (13 nov 2026): todo `ScrollView(.horizontal` lleva `.scrollClipDisabled()` en sus
    /// modificadores, salvo un carrusel de página completa marcado `// recorta:`.
    func testHorizontalRowsDoNotClipWhatGrows() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
        var rows = 0
        var clipped: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let chars = Array(text)
            var search = text.startIndex
            while let r = text.range(of: "ScrollView(.horizontal", range: search..<text.endIndex) {
                search = r.upperBound
                let lineEnd = text[r.lowerBound...].firstIndex(of: "\n") ?? text.endIndex
                if text[r.lowerBound..<lineEnd].contains("recorta:") { rows += 1; continue }
                guard let open = text[r.lowerBound..<lineEnd].firstIndex(of: "{") else { continue }
                rows += 1
                var depth = 0, i = text.distance(from: text.startIndex, to: open)
                while i < chars.count { if chars[i] == "{" { depth += 1 } else if chars[i] == "}" { depth -= 1; if depth == 0 { break } }; i += 1 }
                let after = String(chars[min(i + 1, chars.count)..<min(i + 1500, chars.count)]).components(separatedBy: "\n").dropFirst()
                let chain = after.prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix(".") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                if !chain.contains(where: { $0.contains(".scrollClipDisabled()") }) {
                    let line = text[..<r.lowerBound].filter { $0 == "\n" }.count + 1
                    clipped.append("\(file.lastPathComponent):\(line)")
                }
            }
        }
        XCTAssertGreaterThan(rows, 20, "se leyeron los listones")
        XCTAssertEqual(clipped, [], "Listón que recorta lo que crece: `.scrollClipDisabled()` o `// recorta: <motivo>`")
    }

    /// Un buscador que flota tapa lo que pasa por debajo (13 nov 2026): todo archivo con `.searchable(` lleva
    /// `.scrollEdgeEffectStyle(.hard, for: .top)` en la misma pantalla.
    func testSearchFieldsHideWhatPassesUnder() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
        var fields = 0
        var bare: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains(".searchable(") {
                fields += 1
                if !lines.contains(where: { $0.contains(".scrollEdgeEffectStyle(.hard, for: .top)") }) { bare.append("\(file.lastPathComponent):\(i + 1)") }
            }
        }
        XCTAssertGreaterThanOrEqual(fields, 5, "se encontraron los buscadores")
        XCTAssertEqual(bare, [], "Buscador sin borde firme arriba: lo de debajo se ve a través del campo")
    }

    /// El símbolo de la marca (Centro de control y Live Activity) es la marca de hoy (13 nov 2026: «el de Activity no es el
    /// nuevo y en el botón del panel de control tampoco»; seguía con el dibujo del 27 oct). La firma del símbolo debe decir
    /// las mismas medidas que `DS.Brand`; si cambian, se corre `python3 scripts/orbital_symbol.py`. Y la app y la extensión
    /// llevan el mismo.
    func testBrandSymbolMatchesTheMark() throws {
        let tokens = try String(contentsOf: repo.appendingPathComponent("ios/App/Sources/Design/Tokens.swift"), encoding: .utf8)
        func value(_ name: String) throws -> String {
            let r = try XCTUnwrap(tokens.range(of: "\\b\(name): CGFloat = |\\b\(name): Double = ", options: .regularExpression), name)
            return String(tokens[r.upperBound...].prefix { "0123456789.-".contains($0) })
        }
        let signature = "marca: planeta \(try value("planetRadius")) x \(try value("planetStroke")), anillo \(try value("ringRadius")) "
            + "\(try value("ringOuter"))/\(try value("ringInner")) a \(try value("ringTilt")), hueco \(try value("ringGap"))"
        let app = try String(contentsOf: repo.appendingPathComponent("ios/App/Resources/Assets.xcassets/orbital.mark.symbolset/orbital.mark.svg"), encoding: .utf8)
        let widgets = try String(contentsOf: repo.appendingPathComponent("ios/App/Widgets/Symbols.xcassets/orbital.mark.symbolset/orbital.mark.svg"), encoding: .utf8)
        XCTAssertTrue(app.contains(signature), "El símbolo de la marca no es el de hoy: corre python3 scripts/orbital_symbol.py (\(signature))")
        XCTAssertEqual(app, widgets, "La app y la extensión llevan símbolos distintos de la marca")
    }
}
