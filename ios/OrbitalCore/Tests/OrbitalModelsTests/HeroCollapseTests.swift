import XCTest
@testable import OrbitalModels

final class HeroCollapseTests: XCTestCase {
    let tuning = HeroCollapse.Tuning(parallax: 0.4, shrink: 0.05, blur: 8, blurFrom: 0.3, dim: 0.55, riseEnd: 0.8, fadeFrom: 0.6,
                                     contentFadeEnd: 0.35, contentShrink: 0.06)

    func testSmoothstepIsZeroToOneWithoutJumps() {
        XCTAssertEqual(HeroCollapse.smoothstep(0, 1, -0.5), 0)
        XCTAssertEqual(HeroCollapse.smoothstep(0, 1, 0), 0)
        XCTAssertEqual(HeroCollapse.smoothstep(0, 1, 0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HeroCollapse.smoothstep(0, 1, 1), 1)
        XCTAssertEqual(HeroCollapse.smoothstep(0, 1, 2), 1)
        // Suave en las orillas: casi plano al empezar y al terminar.
        XCTAssertLessThan(HeroCollapse.smoothstep(0, 1, 0.01), 0.001)
        XCTAssertGreaterThan(HeroCollapse.smoothstep(0, 1, 0.99), 0.999)
        XCTAssertEqual(HeroCollapse.smoothstep(0.5, 0.5, 0.4), 0, "un tramo vacío es un escalón, sin dividir entre cero")
    }

    func testAtRestNothingChanges() {
        let s = HeroCollapse.at(minY: 0, height: 400, reduceMotion: false, tuning: tuning)
        XCTAssertEqual(s, HeroCollapse(progress: 0, offset: 0, scale: 1, blur: 0, dim: 0, rise: 0, artOpacity: 1, contentOpacity: 1, contentScale: 1))
    }

    func testCollapsingIsMonotonicAndEndsCollapsed() {
        var last = HeroCollapse.at(minY: 0, height: 400, reduceMotion: false, tuning: tuning)
        for y in stride(from: 4.0, through: 480, by: 4) {
            let s = HeroCollapse.at(minY: -y, height: 400, reduceMotion: false, tuning: tuning)
            XCTAssertGreaterThanOrEqual(s.progress, last.progress)
            XCTAssertGreaterThanOrEqual(s.dim, last.dim); XCTAssertGreaterThanOrEqual(s.rise, last.rise); XCTAssertGreaterThanOrEqual(s.blur, last.blur)
            XCTAssertLessThanOrEqual(s.artOpacity, last.artOpacity); XCTAssertLessThanOrEqual(s.contentOpacity, last.contentOpacity)
            XCTAssertLessThanOrEqual(s.scale, last.scale)
            // Sin saltos: de 4 en 4 pt nada cambia más de lo que permite la pendiente máxima del smoothstep (1,5 / tramo).
            XCTAssertLessThan(abs(s.dim - last.dim), 0.02); XCTAssertLessThan(abs(s.contentOpacity - last.contentOpacity), 0.05)
            last = s
        }
        XCTAssertEqual(last.progress, 1); XCTAssertEqual(last.dim, 0.55, accuracy: 1e-9); XCTAssertEqual(last.rise, 1)
        XCTAssertEqual(last.blur, 8, accuracy: 1e-9); XCTAssertEqual(last.artOpacity, 0); XCTAssertEqual(last.scale, 0.95, accuracy: 1e-9)
        XCTAssertEqual(last.offset, 480 * 0.4, accuracy: 1e-9, "el parallax sigue al desplazamiento")
    }

    func testTheLogoLeavesBeforeTheArt() {
        let s = HeroCollapse.at(minY: -140, height: 400, reduceMotion: false, tuning: tuning)   // 35 %
        XCTAssertEqual(s.contentOpacity, 0, "el logo ya se fue: no se queda detrás de los datos")
        XCTAssertEqual(s.artOpacity, 1, "el arte sigue ahí")
        XCTAssertEqual(s.blur, HeroCollapse.smoothstep(0.3, 1, 0.35) * 8, accuracy: 1e-9)
        XCTAssertLessThan(s.blur, 0.5, "el desenfoque apenas empieza")
    }

    func testPullingDownStretchesFromTheBottom() {
        let s = HeroCollapse.at(minY: 100, height: 400, reduceMotion: false, tuning: tuning)
        XCTAssertEqual(s.scale, 1.25, accuracy: 1e-9)
        XCTAssertEqual(s.progress, 0); XCTAssertEqual(s.offset, 0); XCTAssertEqual(s.contentOpacity, 1)
    }

    func testReduceMotionOnlyDimsAndFades() {
        for y in [-100.0, -250, -400, 120] {
            let s = HeroCollapse.at(minY: y, height: 400, reduceMotion: true, tuning: tuning)
            XCTAssertEqual(s.offset, 0); XCTAssertEqual(s.scale, 1); XCTAssertEqual(s.blur, 0); XCTAssertEqual(s.rise, 0); XCTAssertEqual(s.contentScale, 1)
            let moving = HeroCollapse.at(minY: y, height: 400, reduceMotion: false, tuning: tuning)
            XCTAssertEqual(s.dim, moving.dim); XCTAssertEqual(s.artOpacity, moving.artOpacity); XCTAssertEqual(s.contentOpacity, moving.contentOpacity)
        }
    }

    func testZeroHeightDoesNotDivideByZero() {
        let s = HeroCollapse.at(minY: -10, height: 0, reduceMotion: false, tuning: tuning)
        XCTAssertEqual(s.progress, 1)
        XCTAssertFalse(s.scale.isNaN)
    }
}
