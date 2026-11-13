import XCTest
@testable import OrbitalModels

final class HeroCollapseTests: XCTestCase {
    let tuning = HeroCollapse.Tuning(blur: 8, blurFrom: 0.3, fadeFrom: 0.6, contentFadeEnd: 0.35, contentShrink: 0.06)

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
        XCTAssertEqual(s, HeroCollapse(progress: 0, scale: 1, blur: 0, artOpacity: 1, contentOpacity: 1, contentScale: 1))
    }

    /// AR1 (13 nov 2026): el arte se desenfoca y se desvanece hacia el fondo de verdad; no se encoge ni se queda atrás (eso
    /// lo sacaba de su marco y dejaba costuras).
    func testCollapsingIsMonotonicAndEndsFaded() {
        var last = HeroCollapse.at(minY: 0, height: 400, reduceMotion: false, tuning: tuning)
        for y in stride(from: 4.0, through: 480, by: 4) {
            let s = HeroCollapse.at(minY: -y, height: 400, reduceMotion: false, tuning: tuning)
            XCTAssertGreaterThanOrEqual(s.progress, last.progress); XCTAssertGreaterThanOrEqual(s.blur, last.blur)
            XCTAssertLessThanOrEqual(s.artOpacity, last.artOpacity); XCTAssertLessThanOrEqual(s.contentOpacity, last.contentOpacity)
            XCTAssertEqual(s.scale, 1, "no se encoge al recogerse: sin costuras a los lados")
            // Sin saltos: de 4 en 4 pt nada cambia más de lo que permite la pendiente máxima del smoothstep (1,5 / tramo).
            XCTAssertLessThan(abs(s.artOpacity - last.artOpacity), 0.04); XCTAssertLessThan(abs(s.contentOpacity - last.contentOpacity), 0.05)
            last = s
        }
        XCTAssertEqual(last.progress, 1); XCTAssertEqual(last.blur, 8, accuracy: 1e-9); XCTAssertEqual(last.artOpacity, 0)
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
        XCTAssertEqual(s.progress, 0); XCTAssertEqual(s.contentOpacity, 1)
    }

    func testReduceMotionOnlyFades() {
        for y in [-100.0, -250, -400, 120] {
            let s = HeroCollapse.at(minY: y, height: 400, reduceMotion: true, tuning: tuning)
            XCTAssertEqual(s.scale, 1); XCTAssertEqual(s.blur, 0); XCTAssertEqual(s.contentScale, 1)
            let moving = HeroCollapse.at(minY: y, height: 400, reduceMotion: false, tuning: tuning)
            XCTAssertEqual(s.artOpacity, moving.artOpacity); XCTAssertEqual(s.contentOpacity, moving.contentOpacity)
        }
    }

    /// En claro el arte es una tarjeta: sube nítida con el contenido, sin desenfoque ni desvanecido (se lavaba a un rectángulo gris).
    func testTheLightCardRisesSharp() {
        for y in [-100.0, -250, -400] {
            let s = HeroCollapse.at(minY: y, height: 400, reduceMotion: false, card: true, tuning: tuning)
            XCTAssertEqual(s.blur, 0); XCTAssertEqual(s.artOpacity, 1); XCTAssertEqual(s.scale, 1)
            XCTAssertEqual(s.contentOpacity, HeroCollapse.at(minY: y, height: 400, reduceMotion: false, tuning: tuning).contentOpacity)
        }
        XCTAssertEqual(HeroCollapse.at(minY: 100, height: 400, reduceMotion: false, card: true, tuning: tuning).scale, 1.25, accuracy: 1e-9)
    }

    func testZeroHeightDoesNotDivideByZero() {
        let s = HeroCollapse.at(minY: -10, height: 0, reduceMotion: false, tuning: tuning)
        XCTAssertEqual(s.progress, 1)
        XCTAssertFalse(s.scale.isNaN)
    }
}
