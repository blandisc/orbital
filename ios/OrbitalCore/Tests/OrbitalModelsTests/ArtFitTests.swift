import XCTest
@testable import OrbitalModels

/// Cuándo una imagen se recorta para llenar su marco y cuándo va completa sobre su copia difuminada.
final class ArtFitTests: XCTestCase {
    private let poster = CGSize(width: 500, height: 750), backdrop = CGSize(width: 1920, height: 1080)

    func testAPosterInsideAWideBoxIsShownWhole() {
        XCTAssertEqual(ArtFit.choose(image: poster, box: CGSize(width: 220, height: 124)), .whole, "«Seguir viendo» sin fondo")
    }

    func testAPosterFillsTheTallHeroOfTheTitlePage() {
        // La portada de la ficha (0.9): el póster sin texto la llena, perdiendo un poco de arriba y de abajo.
        XCTAssertEqual(ArtFit.choose(image: poster, box: CGSize(width: 402, height: 447)), .fill)
        XCTAssertEqual(ArtFit.choose(image: poster, box: CGSize(width: 402, height: 300)), .whole, "una portada más ancha (iPad, letra chica)")
    }

    func testTheSubjectMovesTowardTheCenterWithoutLeavingGaps() {
        // Un sujeto algo a la izquierda (x 0.35) de un fondo 16:9 en la portada del iPhone.
        let box = CGSize(width: 402, height: 447)
        let drawn = ArtFit.filled(image: backdrop, box: box)
        XCTAssertEqual(drawn.height, 447, accuracy: 0.01)
        let moved = ArtFit.offset(image: backdrop, box: box, focus: CGPoint(x: 0.35, y: 0.5))
        XCTAssertEqual(moved.width, (0.5 - 0.35) * drawn.width, accuracy: 0.01, "el sujeto queda al centro")
        XCTAssertEqual(moved.height, 0, "no sobra alto: no se mueve")
        // El astronauta de Interstellar (x 0.2): la imagen llega a su borde antes de centrarlo, y ahí se queda.
        let edge = ArtFit.offset(image: backdrop, box: box, focus: CGPoint(x: 0.2, y: 0.5))
        XCTAssertEqual(edge.width, (drawn.width - box.width) / 2, accuracy: 0.01, "hasta el borde, nunca un hueco")
    }

    func testOnlyBigCropsLookForTheSubject() {
        XCTAssertTrue(ArtFit.needsFocus(image: backdrop, box: CGSize(width: 402, height: 447)))
        XCTAssertFalse(ArtFit.needsFocus(image: backdrop, box: CGSize(width: 220, height: 124)), "16:9 en 16:9")
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
