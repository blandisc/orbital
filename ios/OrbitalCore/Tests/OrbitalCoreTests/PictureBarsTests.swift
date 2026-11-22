import XCTest
@testable import OrbitalCore

final class PictureBarsTests: XCTestCase {
    /// Un cuadro de 160×90 con negro a los lados (`bar` columnas de cada lado) y la escena al centro con este brillo.
    private func frame(bar: Int, right: Int? = nil, scene: UInt8 = 120, width: Int = 160, height: Int = 90) -> [UInt8] {
        var luma = [UInt8](repeating: 10, count: width * height)
        for y in 0..<height { for x in bar..<(width - (right ?? bar)) { luma[y * width + x] = scene } }
        return luma
    }

    func testUnCuatroTercioRellenadoA16x9SeVeComoCuatroTercios() throws {
        // 4:3 dentro de 16:9: la imagen ocupa 3/4 del ancho, 20 columnas negras de cada lado en 160.
        let sides = try XCTUnwrap(PictureBars.sides(luma: frame(bar: 20), width: 160, height: 90))
        XCTAssertEqual(sides.left, 0.125, accuracy: 0.001)
        XCTAssertEqual(sides.right, 0.125, accuracy: 0.001)
        let aspect = try XCTUnwrap(PictureBars.pictureAspect(frameAspect: 16.0 / 9, samples: [sides, sides, sides]))
        XCTAssertEqual(aspect, 4.0 / 3, accuracy: 0.01)
    }

    func testSinRayasNoCambiaNada() throws {
        let sides = try XCTUnwrap(PictureBars.sides(luma: frame(bar: 0), width: 160, height: 90))
        XCTAssertNil(PictureBars.pictureAspect(frameAspect: 16.0 / 9, samples: [sides, sides, sides]))
    }

    func testUnFundidoANegroNoDiceNada() {
        XCTAssertNil(PictureBars.sides(luma: frame(bar: 0, scene: 5), width: 160, height: 90))
    }

    func testUnaEscenaOscuraEnUnCuadroNoEngañaSiEnOtroHayLuzALaOrilla() throws {
        let dark = try XCTUnwrap(PictureBars.sides(luma: frame(bar: 30), width: 160, height: 90))
        let lit = try XCTUnwrap(PictureBars.sides(luma: frame(bar: 0), width: 160, height: 90))
        XCTAssertNil(PictureBars.pictureAspect(frameAspect: 16.0 / 9, samples: [dark, lit, dark]))
    }

    func testRayasDisparejasNoSonRelleno() throws {
        let sides = try XCTUnwrap(PictureBars.sides(luma: frame(bar: 10, right: 40), width: 160, height: 90))
        XCTAssertNil(PictureBars.pictureAspect(frameAspect: 16.0 / 9, samples: [sides, sides, sides]))
    }

    func testConPocasMuestrasTodavíaNoDecide() throws {
        let sides = try XCTUnwrap(PictureBars.sides(luma: frame(bar: 20), width: 160, height: 90))
        XCTAssertNil(PictureBars.pictureAspect(frameAspect: 16.0 / 9, samples: [sides, sides]))
    }

    func testUnaMotaDeRuidoEnLaRayaNoLaVuelveImagen() throws {
        var luma = frame(bar: 20)
        luma[45 * 160 + 3] = 200   // un pixel suelto en la raya de la izquierda
        let sides = try XCTUnwrap(PictureBars.sides(luma: luma, width: 160, height: 90))
        XCTAssertEqual(sides.left, 0.125, accuracy: 0.001)
    }
}
