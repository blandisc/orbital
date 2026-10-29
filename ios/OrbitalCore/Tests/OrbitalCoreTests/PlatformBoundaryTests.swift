import XCTest

/// iPhone, iPad y Mac con una sola app (`docs/producto/ipad-y-mac-2026-10.md`): lo que depende del aparato o de la pantalla
/// vive solo en `ios/App/Sources/Platform/`. Las pantallas deciden por el espacio de su ventana, nunca por «qué aparato es».
/// Lo que hoy está fuera es la lista de pendientes: solo puede encogerse (Etapa 0 y Etapa 1 del plan la vacían).
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
        "AppEnvironment.swift": 3,                      // candado de orientación (1.2), escenas
        "Design/Collections.swift": 1,                  // ancho de pantalla (0.3)
        "Design/Tokens.swift": 4,                       // anchos y altos de pantalla (0.3)
        "Screens/DecideView.swift": 1,                  // alto de pantalla (0.3)
        "Screens/ParaTiView.swift": 1,                  // ancho de pantalla (0.3)
        "Screens/TitleView.swift": 1,                   // alto de pantalla (0.3)
        "Screens/RemoteSheet.swift": 3,                 // alto de pantalla (0.3)
        "Screens/SourcesSheet.swift": 1,                // supone una sola ventana
        "Screens/PlayerScreen.swift": 5,                // brillo y orientación del reproductor (1.3)
        "Screens/PlayerScreen+CicloDeVida.swift": 11,   // giro forzado y área segura (1.3)
        "Screens/PlayerScreen+Gestos.swift": 3,         // gesto de brillo y giro (1.3)
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
