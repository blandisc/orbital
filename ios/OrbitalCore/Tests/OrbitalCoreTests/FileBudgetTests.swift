import XCTest

/// Nada se vuelve un monolito sin que se note: ningún archivo de Swift de la app o del paquete pasa de `budget` líneas.
/// Los que hoy lo pasan están en `pending` con su tamaño: solo pueden encogerse (al partir uno, bájalo o quítalo de la lista).
final class FileBudgetTests: XCTestCase {
    var repo: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    static let budget = 600
    /// Margen para no pedir que se baje el número con cada línea que se quita.
    static let slack = 100
    static let roots = ["ios/App/Sources", "ios/App/Widgets", "ios/App/Shared", "ios/OrbitalCore/Sources"]

    /// Pendientes (ruta desde `ios/`): su tamaño el día de la auditoría (29 oct 2026). Solo puede bajar.
    static let pending: [String: Int] = [
        "OrbitalCore/Sources/OrbitalModels/PlayerModel.swift": 1267,
        "App/Sources/Design/SubtitlePanel.swift": 618,
        "App/Sources/Screens/ParaTiView.swift": 936,
        "App/Sources/Support/Demo.swift": 854,
        "App/Sources/Screens/TitleView.swift": 813,
        "OrbitalCore/Sources/OrbitalCore/ForYou.swift": 730,
        "OrbitalCore/Sources/OrbitalCore/Trakt.swift": 676,
        "OrbitalCore/Sources/OrbitalModels/DecideModel.swift": 651,
        "App/Sources/Screens/PlayerScreen+Gestos.swift": 630,
        "OrbitalCore/Sources/OrbitalCore/Downloads.swift": 624,
        "App/Sources/Design/Mosaic.swift": 622,
        "App/Sources/Platform/BackgroundDownloadTransport.swift": 610,
    ]

    func testNoSwiftFileOutgrowsItsBudget() throws {
        let ios = repo.appendingPathComponent("ios")
        var sizes: [String: Int] = [:]
        for root in Self.roots {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: repo.appendingPathComponent(root), includingPropertiesForKeys: nil)).allObjects
            for case let file as URL in files where file.pathExtension == "swift" {
                let relative = file.path.replacingOccurrences(of: ios.path + "/", with: "")
                sizes[relative] = try String(contentsOf: file, encoding: .utf8).filter { $0 == "\n" }.count   // como `wc -l`
            }
        }
        XCTAssertGreaterThan(sizes.count, 100, "faltan las fuentes de ios/")
        var problems: [String] = []
        for (file, lines) in sizes.sorted(by: { $0.key < $1.key }) {
            let allowed = Self.pending[file] ?? Self.budget
            if lines > allowed { problems.append("\(file): \(lines) líneas (tope \(allowed)). Pártelo por responsabilidad en vez de seguir creciendo") }
            if let listed = Self.pending[file], lines < listed - Self.slack { problems.append("\(file): ya tiene \(lines), la lista dice \(listed). ¡Bien! Baja el número en `pending`") }
        }
        for (file, listed) in Self.pending {
            if sizes[file] == nil { problems.append("\(file): ya no existe (la lista dice \(listed)). Quítalo de `pending`") }
            else if sizes[file]! <= Self.budget { problems.append("\(file): ya cabe en el tope (\(sizes[file]!) líneas). Quítalo de `pending`") }
        }
        XCTAssertTrue(problems.isEmpty, "Archivos fuera de presupuesto:\n" + problems.joined(separator: "\n"))
    }
}
