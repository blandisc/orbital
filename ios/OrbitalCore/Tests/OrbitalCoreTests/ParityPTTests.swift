import XCTest
@testable import OrbitalCore
import OrbitalAddons

/// La paridad TV ↔ iPhone del 4 nov 2026 (PT8, PT10, PT19): lo que vive en el núcleo.
final class ParityPTTests: XCTestCase {
    /// PT8: coma en español, punto en inglés; GB y TB con un decimal, MB y KB sin decimales.
    func testSizesUseTheAppLanguageSeparator() {
        XCTAssertEqual(ByteSize.text(1_200_000_000, language: "es"), "1,2 GB")
        XCTAssertEqual(ByteSize.text(1_200_000_000, language: "en"), "1.2 GB")
        XCTAssertEqual(ByteSize.text(350_000_000, language: "es"), "350 MB")
        XCTAssertEqual(ByteSize.text(gigabytes: 64, language: "es"), "64,0 GB")
        XCTAssertEqual(ByteSize.text(2_500_000_000_000, language: "es"), "2,5 TB")
        XCTAssertEqual(ByteSize.text(0, language: "es"), "0 KB")
    }

    /// PT10: un ícono distinto por estado; el triángulo solo para «Real-Debrid no lo dejó bajar», nunca para «Muchas descargas
    /// activas»; lo que baja, la nube con flecha (PT5).
    func testEachRequestStateHasItsOwnIcon() {
        let states = DebridRequest.State.allCases.filter { $0 != .gone }
        XCTAssertEqual(Set(states.map(DebridRequestWords.symbol)).count, states.count)
        XCTAssertEqual(states.filter { DebridRequestWords.symbol($0).contains("triangle") }, [.refused])
        XCTAssertEqual(DebridRequestWords.symbol(.downloading), "icloud.and.arrow.down")
        XCTAssertEqual(DebridRequestWords.symbol(.queued), "clock")
        XCTAssertNotEqual(DebridRequestWords.Icon.cancel, DebridRequestWords.Icon.remove)
    }

    /// PT19: las cuatro medidas de la TV, de chica a grande.
    func testFourSubtitleSizesLikeTheTV() {
        XCTAssertEqual(AppSettings.subtitleSizes, ["small", "medium", "large", "xlarge"])
        let heights = AppSettings.subtitleSizes.map { size -> Double in var s = AppSettings(); s.subtitleSize = size; return s.subtitleHeightFraction }
        XCTAssertEqual(heights, heights.sorted())
        XCTAssertEqual(Set(heights).count, 4)
    }
}
