import XCTest

/// La app compila sin advertencias (16 nov 2026: había 18). La que más se repetía: unir `Text` con `+`, que iOS 26 da por
/// obsoleto. Se escribe `Text("\(a)\(b)")` (o `Text("\(a) \(b)")`), que conserva el estilo de cada parte.
final class NoTextConcatenationTests: XCTestCase {
    func testNoTextIsJoinedWithPlus() throws {
        var repo = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { repo.deleteLastPathComponent() }
        let pattern = try NSRegularExpression(pattern: #"\+ Text\(|Text\("[^"]*"\) \+ "#)
        var found: [String] = []
        for root in ["ios/App/Sources", "ios/App/Widgets", "ios/App/Shared"] {
            guard let files = FileManager.default.enumerator(at: repo.appendingPathComponent(root), includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in files where file.pathExtension == "swift" {
                for (n, line) in try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").enumerated()
                where pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                    found.append("\(file.lastPathComponent):\(n + 1)")
                }
            }
        }
        XCTAssertEqual(found, [], "Text unido con «+» (obsoleto en iOS 26): usa Text(\"\\(a)\\(b)\")")
    }
}
