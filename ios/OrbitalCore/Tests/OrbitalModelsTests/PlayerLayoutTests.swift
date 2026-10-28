import CoreGraphics
import XCTest
@testable import OrbitalModels

/// Dónde va el video del reproductor en iPhone SE, mini y Pro Max (el área segura de cada uno, en vertical y en horizontal).
final class PlayerLayoutTests: XCTestCase {
    /// Las mismas medidas que la app (`PlayerLayout.app`, de los tokens).
    let layout = PlayerLayout(topClearance: 60, controlsReserve: 260, minAspect: 4.0 / 3.0, wideAspect: 16.0 / 9.0, defaultCenter: 0.3,
                              panelWidth: 420, panelShare: 0.55)
    let phones: [(name: String, portrait: CGSize, landscapeWidth: CGFloat)] = [
        ("SE", CGSize(width: 375, height: 647), 667), ("mini", CGSize(width: 375, height: 762), 812), ("Pro Max", CGSize(width: 440, height: 860), 956)]

    func testTheVideoAlwaysLeavesRoomForTheControlsAndNeverGoesAboveTheTop() {
        for phone in phones {
            for aspect in [4.0 / 3.0, 16.0 / 9.0, 2.39] {
                for center in [-1.0, 0, 0.3, 0.6, 1] {
                    let rect = layout.portraitRect(in: phone.portrait, center: center, aspect: aspect)
                    XCTAssertGreaterThanOrEqual(rect.minY, 0, "\(phone.name) \(aspect) \(center)")
                    XCTAssertLessThanOrEqual(rect.maxY, phone.portrait.height - layout.controlsReserve + 0.5, "\(phone.name) \(aspect) \(center)")
                    XCTAssertEqual(rect.width, phone.portrait.width)
                }
            }
        }
    }

    func testA43VideoGrowsTallerAndAWideOneStaysInTheBand() {
        for phone in phones {
            let simpsons = layout.portraitRect(in: phone.portrait, center: -1, aspect: 4.0 / 3.0)
            let movie = layout.portraitRect(in: phone.portrait, center: -1, aspect: 2.39)
            XCTAssertEqual(simpsons.height, phone.portrait.width * 3 / 4, accuracy: 0.5, "\(phone.name): 4:3 de orilla a orilla")
            XCTAssertEqual(movie.height, phone.portrait.width * 9 / 16, accuracy: 0.5, "\(phone.name): cine en la banda 16:9")
        }
    }

    func testItOpensBelowTheCloseButtonAndCanBeRaisedToTheTop() {
        for phone in phones {
            XCTAssertEqual(layout.portraitRect(in: phone.portrait, center: -1, aspect: 16.0 / 9.0).minY, layout.topClearance, "\(phone.name)")
            let limits = layout.portraitLimits(in: phone.portrait, aspect: 16.0 / 9.0)
            XCTAssertEqual(layout.portraitRect(in: phone.portrait, center: limits.lowerBound, aspect: 16.0 / 9.0).minY, 0, accuracy: 0.5,
                           "\(phone.name): se puede subir hasta arriba")
            let resolved = layout.resolvedCenter(-1, in: phone.portrait, aspect: 16.0 / 9.0)
            XCTAssertTrue(limits.contains(resolved), "\(phone.name): arrastrar parte de donde está")
        }
    }

    func testTheSidePanelLeavesVideoOnSmallPhones() {
        XCTAssertEqual(layout.sidePanelWidth(in: 956), 420, "en el Pro Max, su ancho de siempre")
        for phone in phones {
            let video = phone.landscapeWidth - layout.sidePanelWidth(in: phone.landscapeWidth)
            XCTAssertGreaterThan(video, phone.landscapeWidth * 0.44, "\(phone.name): queda casi la mitad para el video")
        }
    }
}
