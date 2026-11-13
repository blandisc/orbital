import XCTest

/// Las preguntas y elecciones de la app son tarjetas de la app, no diálogos del sistema (Fernando, 13 nov 2026: «Cuando le
/// picas un episodio ya visto, que créate una tarjeta, que no aparezca esta notificación como del sistema, toda fea»). Regla
/// en `docs/ios-interfaz.md` § «Las preguntas son tarjetas de la app».
extension DesignRulesTests {
    /// Diálogos del sistema que viven en archivos de otra tarea en curso (el buscador de versiones y el reproductor): cuántos
    /// hay hoy en cada uno y por qué siguen. Uno más ahí también falla.
    static let pendingDialogs: [String: (count: Int, why: String)] = [
        "SourcesSheet.swift": (2, "«¿Para el resto de la serie también?» y lo de un pedido a la nube: pendientes de pasar a tarjeta cuando se libere «Versión»"),
        "PlayerScreen.swift": (2, "«Real-Debrid aún no tiene esta versión» (pendiente de tarjeta) y «¿Sigues viendo?» (sí o no sobre el video)"),
    ]

    /// Un `confirmationDialog`, `alert` o `actionSheet` nuevo es una tarjeta de la app (`ChoiceSheet`). Los que se quedan
    /// (confirmaciones cortas y destructivas, pedir un nombre, un sí o no que llega sobre lo que esté abierto) llevan
    /// `ds-exception: <motivo>` en su renglón.
    func testQuestionsAreAppCardsNotSystemDialogs() throws {
        let files = try sources(["Design", "Screens", "Platform"])
        let pattern = #"\bconfirmationDialog\(|\.alert\(|\.actionSheet\("#
        let pending = Self.pendingDialogs
        var problems = hits(pattern, in: files) { pending[$0.name] != nil }
        for (name, expected) in pending {
            let found = hits(pattern, in: files.filter { $0.name == name })
            if found.count > expected.count {
                problems += found.map { $0 + " (en «\(name)» ya había \(expected.count): \(expected.why))" }
            }
        }
        check(problems, "Pregunta o elección en un diálogo del sistema: hazla tarjeta de la app (`ChoiceSheet`) o marca su porqué con `ds-exception:`")
    }

    /// Lo que se quedó como diálogo dice por qué: el motivo no puede ir vacío.
    func testKeptDialogsSayWhy() throws {
        var problems: [String] = []
        for file in try sources(["Design", "Screens", "Platform"]) {
            for (i, line) in file.lines.enumerated() where line.range(of: #"\bconfirmationDialog\(|\.alert\(|\.actionSheet\("#, options: .regularExpression) != nil {
                guard let mark = line.range(of: "ds-exception:") else { continue }
                if line[mark.upperBound...].trimmingCharacters(in: .whitespaces).count < 8 { problems.append("\(file.path):\(i + 1)") }
            }
        }
        check(problems, "Diálogo del sistema con `ds-exception:` sin su porqué")
    }

    /// El episodio que ya viste abre su tarjeta (EV1, 13 nov), no la pregunta del sistema.
    func testRewatchIsAnAppCard() throws {
        let file = try XCTUnwrap(try sources(["Screens"]).first { $0.name == "TitleView+Acciones.swift" })
        let code = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        XCTAssertTrue(code.contains("struct RewatchCard") && code.contains(".choiceSheet(item:"), "«Ya lo viste» es una `ChoiceSheet`")
        XCTAssertFalse(code.contains("confirmationDialog("), "«Ya lo viste» no vuelve a la pregunta del sistema")
        let piece = try XCTUnwrap(try sources(["Design"]).first { $0.name == "ChoiceSheet.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(piece.contains(".fittedSheet()") && piece.contains(".dsSheetContent("), "la tarjeta mide lo que trae y tiene el aire de las hojas")
        XCTAssertTrue(piece.contains("WatchedOption("), "sus renglones son los de «¿Cuándo la viste?»")
        XCTAssertFalse(piece.contains("\"Cancelar\""), "sin «Cancelar»: se cierra deslizándola, tocando fuera o con Esc")
        XCTAssertTrue(piece.contains("safeAreaInsets.bottom"), "sin barra de inicio (SE, iPad) la tarjeta pone su margen abajo: el último renglón no toca la orilla")
        // Con letra grande el nombre de un renglón parte en dos: su aire arriba y abajo no puede depender solo del alto mínimo.
        let option = try XCTUnwrap(try sources(["Design"]).first { $0.name == "WatchedWhenSheet.swift" }).lines.joined(separator: "\n")
        let row = try XCTUnwrap(option.range(of: "struct WatchedOption")).lowerBound
        XCTAssertTrue(option[row...].contains(".padding(.vertical, DS.Space."), "`WatchedOption` lleva su aire vertical (aire parejo con letra grande)")
    }
}
