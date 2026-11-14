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
}
