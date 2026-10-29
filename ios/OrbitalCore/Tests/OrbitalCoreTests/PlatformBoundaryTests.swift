import XCTest

/// iPhone, iPad y Mac con una sola app (`docs/producto/ipad-y-mac-2026-10.md`): lo que depende del aparato o de la pantalla
/// vive solo en `ios/App/Sources/Platform/`. Las pantallas deciden por el espacio de su ventana, nunca por «qué aparato es».
/// Lo que queda fuera es la lista de pendientes: solo puede encogerse.
final class PlatformBoundaryTests: XCTestCase {
    var repo: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    /// Mide la pantalla en vez de la ventana, pregunta qué aparato es, fuerza el giro o supone una sola ventana.
    static let deviceAPI = #"UIScreen|UIDevice|userInterfaceIdiom|requestGeometryUpdate|supportedInterfaceOrientations|AppDelegate\.orientations|connectedScenes|import ActivityKit|MPVolumeView"#

    /// Pendientes por archivo (ruta desde `ios/App/Sources/`): cuántos usos quedan. Al quitar uno, baja aquí el número.
    static let pending: [String: Int] = [
        "AppEnvironment.swift": 1,   // el método del AppDelegate que iOS pregunta (responde `Orientation.supported`)
    ]

    func testDeviceSpecificCodeLivesInPlatform() throws {
        let sources = repo.appendingPathComponent("ios/App/Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)).allObjects
        XCTAssertFalse(files.isEmpty, "falta ios/App/Sources")
        let pattern = try NSRegularExpression(pattern: Self.deviceAPI)
        var found: [String: Int] = [:]
        for case let file as URL in files where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: sources.path + "/", with: "")
            if relative.hasPrefix("Platform/") { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.components(separatedBy: "\n") {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") { continue }
                let hits = pattern.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
                if hits > 0 { found[relative, default: 0] += hits }
            }
        }
        var problems: [String] = []
        for (file, count) in found.sorted(by: { $0.key < $1.key }) {
            let allowed = Self.pending[file] ?? 0
            if count > allowed { problems.append("\(file): \(count) usos de API del aparato (permitidos \(allowed)). Muévelos a Platform/ o decide por el tamaño de la ventana") }
            if count < allowed { problems.append("\(file): quedan \(count), la lista dice \(allowed). ¡Bien! Baja el número en `pending`") }
        }
        for (file, allowed) in Self.pending where found[file] == nil {
            problems.append("\(file): ya no tiene usos (la lista dice \(allowed)). Quítalo de `pending`")
        }
        XCTAssertTrue(problems.isEmpty, "Código del aparato fuera de Platform/ (docs/producto/ipad-y-mac-2026-10.md):\n" + problems.joined(separator: "\n"))
    }
}
