import CoreGraphics
import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El iPad compartiendo pantalla (Split View, Stage Manager): ventanas angostas y muy altas, o anchas y bajas, que el iPhone
/// nunca tiene. Tamaños del iPad Pro 11" (834×1210 completo): un tercio, la mitad y dos tercios, de pie y acostado.
final class IPadWindowLayoutTests: XCTestCase {
    let player = PlayerLayout(topClearance: 60, controlsReserve: 260, minAspect: 4.0 / 3.0, wideAspect: 16.0 / 9.0, defaultCenter: 0.3,
                              panelWidth: 420, panelShare: 0.55)
    /// Ventanas en las que el reproductor va en vertical (más altas que anchas).
    let tall: [(name: String, size: CGSize)] = [
        ("completo de pie", CGSize(width: 834, height: 1210)), ("un tercio acostado", CGSize(width: 375, height: 834)),
        ("mitad acostado", CGSize(width: 597, height: 834)), ("dos tercios acostado", CGSize(width: 821, height: 834)),
        ("un tercio de pie", CGSize(width: 320, height: 1210)), ("mitad de pie", CGSize(width: 414, height: 1210)),
    ]
    /// Ventanas acostadas de verdad (más anchas que altas): video a lo ancho con el panel a la derecha.
    let wide: [CGFloat] = [1210, 1080, 980]

    func testInATallWindowTheVideoFitsAboveTheControls() {
        for window in tall {
            for aspect in [4.0 / 3.0, 16.0 / 9.0, 2.39] {
                for center in [-1.0, 0, 0.3, 1] {
                    let rect = player.portraitRect(in: window.size, center: center, aspect: aspect)
                    XCTAssertGreaterThanOrEqual(rect.minY, 0, "\(window.name) \(aspect) \(center): sube de más")
                    XCTAssertLessThanOrEqual(rect.maxY, window.size.height - player.controlsReserve + 0.5, "\(window.name) \(aspect): tapa los controles")
                    XCTAssertEqual(rect.width, window.size.width, "\(window.name): el video va de orilla a orilla")
                }
            }
        }
    }

    func testInAWideWindowThePanelLeavesMostOfTheWidthToTheVideo() {
        for width in wide {
            let panel = player.sidePanelWidth(in: width)
            XCTAssertLessThanOrEqual(panel, player.panelWidth, "\(width): el panel no pasa de su ancho")
            XCTAssertGreaterThanOrEqual(width - panel, width * 0.45, "\(width): al video le queda casi la mitad o más")
        }
    }

    func testTheMosaicFitsEveryWindowWidth() {
        // Como la app (`MosaicView.columnCount`): 3 columnas parejas en ventana angosta (como el iPhone); 6 con ancho regular,
        // que en el iPad empieza en los dos tercios (821 pt).
        let widths = tall.map { Double($0.size.width) } + wide.map(Double.init)
        for (columns, uniform, range) in [(3, true, 0.0...700), (6, false, 700.0...2000)] {
            let geo = MosaicGeometry(columnCount: columns, gap: 12, ring: 8, growRatio: 1.8, focusedRowRatio: 1.2, uniform: uniform)
            for width in widths where range.contains(width) {
                for focus in [nil, 0, columns - 1] as [Int?] {
                    let frames = geo.columnFrames(totalWidth: width, focusedColumn: focus)
                    XCTAssertEqual(frames.count, columns)
                    for frame in frames {
                        XCTAssertGreaterThanOrEqual(frame.x, 0, "\(columns) columnas en \(width)")
                        XCTAssertLessThanOrEqual(frame.x + frame.width, width + 0.0001, "\(columns) columnas en \(width): una sale del ancho")
                        XCTAssertGreaterThan(frame.width, 40, "\(columns) columnas en \(width), foco \(String(describing: focus)): una queda de \(frame.width) pt")
                    }
                }
            }
        }
    }
}
