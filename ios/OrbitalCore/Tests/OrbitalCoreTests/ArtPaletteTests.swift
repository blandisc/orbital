import XCTest
@testable import OrbitalCore

/// Los mismos casos que `tests/web/color.test.mjs`: el color del arte sale igual en la TV y en el iPhone.
final class ArtPaletteTests: XCTestCase {
    private func image(_ colors: [(ArtPalette.RGB, Int)]) -> [UInt8] {
        colors.flatMap { c, n in Array(repeating: [UInt8(c.r), UInt8(c.g), UInt8(c.b), 255], count: n).flatMap { $0 } }
    }

    func testHslRoundTrip() {
        for c in [(255, 0, 0), (20, 120, 200), (250, 200, 40)] {
            let (h, s, l) = ArtPalette.rgbToHsl(c)
            let back = ArtPalette.hslToRgb(h, s, l)
            XCTAssertEqual([back.r, back.g, back.b], [c.0, c.1, c.2])
        }
    }

    func testTheHeaviestHueWinsNotTheAverage() throws {
        let d = try XCTUnwrap(ArtPalette.dominantHue(rgba: image([((40, 140, 230), 70), ((220, 40, 40), 30)])))
        XCTAssertTrue(d.hue > 195 && d.hue < 225, "tono \(d.hue)")
    }

    func testWhitesBlacksAndGraysDoNotCount() {
        XCTAssertNil(ArtPalette.dominantHue(rgba: image([((255, 255, 255), 50), ((0, 0, 0), 50), ((128, 128, 130), 50)])))
        let neutral = ArtPalette.palette(for: nil)
        XCTAssertEqual([neutral.accent.r, neutral.accent.g, neutral.accent.b], [205, 205, 211])
    }

    func testAccentIsAlwaysLightAndTintAlwaysDark() {
        for hue in [0.0, 60, 120, 240, 300] {
            let p = ArtPalette.palette(for: (hue, 1))
            XCTAssertGreaterThan(ArtPalette.rgbToHsl(p.accent).l, 0.7, "\(hue)")
            XCTAssertLessThan(ArtPalette.rgbToHsl(p.tint).l, 0.25, "\(hue)")
        }
    }
}
