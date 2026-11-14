import XCTest

/// Las estrellas que se tocan se atinan (Fernando, 13 nov 2026: «es bien difícil atinarle»): lugar táctil de 44 pt de alto
/// aunque la estrella sea chica, una burbuja que dice cuánto llevas al arrastrar, y en la pastilla «¿Qué tal…?» y en
/// «Por calificar» el tamaño `DS.Rating.starTouch`; `starInline` es solo para leer. Regla en `docs/ios-interfaz.md`.
extension DesignRulesTests {
    func testRatingStarsAreEasyToHit() throws {
        let files = try sources(["Design", "Screens"])
        let stars = try XCTUnwrap(files.first { $0.name == "Calificar.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(stars.contains("DS.Size.touchTarget - size"), "RatingStars: el lugar táctil mide al menos 44 pt de alto")
        XCTAssertTrue(stars.contains("bubble(dragging"), "RatingStars: al arrastrar, la burbuja dice cuánto llevas")
        // Las chicas de leer no se tocan: si llevan `starInline`, van con `.allowsHitTesting(false)`.
        var small: [String] = []
        for file in files {
            for (i, line) in file.lines.enumerated() where line.contains("RatingStars(") && line.contains("DS.Rating.starInline")
                && !line.contains("allowsHitTesting(false)") {
                small.append("\(file.name):\(i + 1)")
            }
        }
        XCTAssertEqual(small, [], "Estrellas para calificar con el tamaño de leer: usa `DS.Rating.starTouch`")
    }

    /// La pastilla «¿Qué tal…?» es un solo renglón: sus letreros nunca se parten letra por letra (Fernando, 14 nov 2026:
    /// «Guardada» salía «Gu / ar- / da / da» con las estrellas grandes y «y 2 más»). Cada `Text`/`Label` lleva `.lineLimit(1)`.
    func testRatingReminderLabelsStayOnOneLine() throws {
        let file = try XCTUnwrap(try sources(["Design"]).first { $0.name == "Calificar.swift" })
        let start = try XCTUnwrap(file.lines.firstIndex { $0.contains("struct RatingReminder") })
        let end = file.lines[(start + 1)...].firstIndex { $0.hasPrefix("struct ") || $0.hasPrefix("private struct ") } ?? file.lines.count
        var loose: [String] = []
        for i in start..<end where file.lines[i].contains("Text(\"") || file.lines[i].contains("Label(\"") {
            let near = file.lines[i...min(i + 1, end - 1)].joined()
            if !near.contains("lineLimit(1)") { loose.append("Calificar.swift:\(i + 1)") }
        }
        XCTAssertEqual(loose, [], "Letreros de la pastilla «¿Qué tal…?» sin .lineLimit(1): se parten letra por letra")
    }
}
