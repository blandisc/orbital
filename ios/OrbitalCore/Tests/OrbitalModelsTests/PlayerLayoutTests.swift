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

    func testAWeirdAspectFromTheEngineNeverFillsTheScreen() {
        for phone in phones {
            for aspect in [Double.nan, .infinity, 0, -1] {
                let rect = layout.portraitRect(in: phone.portrait, center: -1, aspect: aspect)
                XCTAssertEqual(rect.height, phone.portrait.width * 9 / 16, accuracy: 0.5, "\(phone.name) \(aspect): como 16:9")
                XCTAssertLessThanOrEqual(rect.maxY, phone.portrait.height - layout.controlsReserve + 0.5)
            }
        }
    }

    func testTheSidePanelLeavesVideoOnSmallPhones() {
        XCTAssertEqual(layout.sidePanelWidth(in: 956), 420, "en el Pro Max, su ancho de siempre")
        for phone in phones {
            let video = phone.landscapeWidth - layout.sidePanelWidth(in: phone.landscapeWidth)
            XCTAssertGreaterThan(video, phone.landscapeWidth * 0.44, "\(phone.name): queda casi la mitad para el video")
        }
    }

    // MARK: «Audio y subtítulos» (S1, 11 nov 2026)

    /// Vertical: el video queda justo arriba del panel (sin hueco negro) mientras cabe; si no, sube hasta arriba y nunca sale.
    func testWithThePanelOpenTheVideoSitsRightAboveIt() {
        let gap: CGFloat = 16
        for phone in phones {
            for panel in [CGFloat(180), 320, 480, 900] {
                let rect = layout.portraitRect(abovePanel: panel, gap: gap, in: phone.portrait, aspect: 16.0 / 9.0)
                XCTAssertGreaterThanOrEqual(rect.minY, 0, "\(phone.name) \(panel): nunca arriba de la orilla")
                XCTAssertLessThanOrEqual(rect.maxY, phone.portrait.height + 0.5, "\(phone.name) \(panel): nunca abajo de la orilla")
                if phone.portrait.height - panel - gap - rect.height >= 0 {
                    XCTAssertEqual(phone.portrait.height - panel - rect.maxY, gap, accuracy: 0.5, "\(phone.name) \(panel): sin hueco entre el video y el panel")
                } else {
                    XCTAssertEqual(rect.minY, 0, accuracy: 0.5, "\(phone.name) \(panel): el panel no cabe, el video sube hasta arriba")
                }
            }
        }
    }

    /// Horizontal: el panel dentro del área segura, de arriba abajo, y el video entero a su izquierda (sin que lo tape).
    func testInLandscapeThePanelNeverCoversTheVideoNorLeavesTheScreen() {
        let notch = PlayerLayout.Insets(top: 0, left: 62, bottom: 21, right: 62)
        let plain = PlayerLayout.Insets()
        for phone in phones {
            let size = CGSize(width: phone.landscapeWidth, height: phone.portrait.width)
            for insets in [notch, plain] {
                let dock = layout.sideDock(in: size, insets: insets, margin: 16, aspect: 16.0 / 9.0)
                XCTAssertLessThanOrEqual(dock.panel.maxX, size.width - max(insets.right, 16) + 0.5, "\(phone.name): el panel dentro del área segura")
                XCTAssertGreaterThanOrEqual(dock.panel.minY, max(insets.top, 16) - 0.5, "\(phone.name): arriba, con su aire")
                XCTAssertLessThanOrEqual(dock.panel.maxY, size.height - max(insets.bottom, 16) + 0.5, "\(phone.name): abajo no se corta")
                XCTAssertLessThanOrEqual(dock.video.maxX, dock.panel.minX - 16 + 0.5, "\(phone.name): el panel no tapa el video")
                XCTAssertGreaterThanOrEqual(dock.video.minX, max(insets.left, 16) - 0.5, "\(phone.name): el video no se pega a la orilla")
                XCTAssertEqual(dock.panel.width, layout.sidePanelWidth(in: size.width), "\(phone.name): el mismo ancho que mide el video")
                XCTAssertEqual(dock.video.width / dock.video.height, 16.0 / 9.0, accuracy: 0.01, "\(phone.name): en su proporción")
            }
        }
    }
}
