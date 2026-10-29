import XCTest
@testable import OrbitalModels

/// Cuándo una imagen se recorta para llenar su marco y cuándo va completa sobre su copia difuminada.
final class ArtFitTests: XCTestCase {
    private let poster = CGSize(width: 500, height: 750), backdrop = CGSize(width: 1920, height: 1080)

    func testAPosterInsideAWideBoxIsShownWhole() {
        XCTAssertEqual(ArtFit.choose(image: poster, box: CGSize(width: 220, height: 124)), .whole, "«Seguir viendo» sin fondo")
        XCTAssertEqual(ArtFit.choose(image: poster, box: CGSize(width: 402, height: 447)), .whole, "la ficha del iPhone sin fondo")
    }

    func testMatchingShapesFillTheBox() {
        XCTAssertEqual(ArtFit.choose(image: poster, box: CGSize(width: 112, height: 168)), .fill, "un póster en su tarjeta")
        XCTAssertEqual(ArtFit.choose(image: backdrop, box: CGSize(width: 220, height: 124)), .fill, "un fondo en una tarjeta 16:9")
    }

    func testAWideImageInATallBoxStillFills() {
        // Lo ancho en un marco alto (la ficha, «En tendencia») se sigue recortando: eso lo resuelve el punto de interés, no esto.
        XCTAssertEqual(ArtFit.choose(image: backdrop, box: CGSize(width: 270, height: 430)), .fill)
    }

    func testUnknownSizesFill() {
        XCTAssertEqual(ArtFit.choose(image: .zero, box: CGSize(width: 100, height: 100)), .fill)
        XCTAssertEqual(ArtFit.choose(image: poster, box: .zero), .fill)
    }
}
