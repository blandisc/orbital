import XCTest

/// Un día del calendario se lee en tu zona (28 nov 2026: Letterboxd y «El día que salió» salían un día antes en México y se
/// mandaban así a Trakt). Un «2005-10-18» leído con `.iso8601.year().month().day()` es medianoche UTC: se lee con
/// `ISODates.localDay`. Regla en `docs/ios-interfaz.md` § «Los días son de tu calendario».
extension DesignRulesTests {
    func testCalendarDaysAreReadInYourTimeZone() throws {
        var problems: [String] = []
        let roots = ["ios/App/Sources", "ios/OrbitalCore/Sources"].map { repo.appendingPathComponent($0) }
        for root in roots {
            let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).allObjects
            for case let file as URL in files where file.pathExtension == "swift" {
                let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
                for (i, line) in lines.enumerated() where line.contains(".iso8601.year().month().day()") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("///") {
                    problems.append("\(file.lastPathComponent):\(i + 1)")
                }
            }
        }
        check(problems, "Un día leído como medianoche UTC sale un día antes en México: usa ISODates.localDay")
    }
}
