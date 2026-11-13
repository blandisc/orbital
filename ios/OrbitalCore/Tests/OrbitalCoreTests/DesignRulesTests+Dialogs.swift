import XCTest

/// Las preguntas y elecciones de la app son tarjetas de la app, no diálogos del sistema (Fernando, 13 nov 2026: «Cuando le
/// picas un episodio ya visto, que créate una tarjeta, que no aparezca esta notificación como del sistema, toda fea»). Regla
/// en `docs/ios-interfaz.md` § «Las preguntas son tarjetas de la app».
extension DesignRulesTests {
    /// Diálogos del sistema pendientes de pasar a tarjeta, por archivo: cuántos hay y por qué siguen. Uno más ahí también falla.
    /// Vacío desde el 13 nov 2026: las dos de «Versión» (`SourcesSheet`) y las dos del reproductor (`PlayerScreen`) ya son
    /// tarjetas (Fernando: «Sí, también conviértelos en la tarjeta, los otros tres diálogos»).
    static let pendingDialogs: [String: (count: Int, why: String)] = [:]

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

    /// «Versión»: «¿Para el resto de la serie también?» y el pedido que baja en la nube («Ver Inglés…, ya arranca») son
    /// tarjetas (13 nov), con las mismas salidas de antes y sin «Cancelar» ni «Esperar a que llegue» (esperar es cerrarla).
    func testVersionQuestionsAreAppCards() throws {
        let file = try XCTUnwrap(try sources(["Screens"]).first { $0.name == "SourcesSheet.swift" })
        let code = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        XCTAssertTrue(code.contains(".choiceSheet(item: $seriesAsk)") && code.contains(".choiceSheet(item: $waiting)"), "las dos preguntas de «Versión» son `ChoiceSheet`")
        XCTAssertTrue(code.contains("forSeries: ask.code") && code.contains("forSeries: nil"), "«Sí, desde aquí» y «Solo este episodio» hacen lo de siempre")
        XCTAssertFalse(code.contains("confirmationDialog(") || code.contains(".alert("), "«Versión» no vuelve a los diálogos del sistema")
        XCTAssertFalse(code.contains("\"Esperar a que llegue\"") || code.contains("\"Cancelar\""), "sin «Cancelar»: la tarjeta se cierra deslizándola, tocando fuera o con Esc")
    }

    /// El reproductor: «¿Sigues viendo?» y «Real-Debrid aún no tiene esta versión» son la misma tarjeta flotando sobre el video
    /// (en horizontal una hoja de iOS sube a todo el alto), encima de todo, sin vibrar, y «¿Sigues viendo?» no se cierra sin
    /// contestar (el siguiente episodio espera en pausa, como antes).
    func testPlayerQuestionsAreFloatingCards() throws {
        let screens = try sources(["Screens"])
        let player = try XCTUnwrap(screens.first { $0.name == "PlayerScreen.swift" }).lines.joined(separator: "\n")
        XCTAssertFalse(player.contains("confirmationDialog(") || player.contains(".alert("), "el reproductor no vuelve a los diálogos del sistema")
        XCTAssertTrue(player.contains("questionLayer(model)"), "las preguntas van en el escenario del reproductor")
        XCTAssertTrue(player.contains("dismissPlayerQuestion()"), "Esc cierra primero la pregunta, no el reproductor")
        let file = try XCTUnwrap(screens.first { $0.name == "PlayerScreen+Preguntas.swift" })
        let code = file.lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        XCTAssertTrue(code.contains("ChoiceSheet(card: card, floating: true)"), "la misma tarjeta de la app, flotando")
        XCTAssertTrue(code.contains("still-watching-card") && code.contains("slow-pick-card"), "las dos preguntas del reproductor son tarjetas")
        XCTAssertTrue(code.contains("confirmStillWatching()") && code.contains("await close()") && code.contains("switchSource(to: index)"), "las mismas salidas de antes")
        XCTAssertTrue(code.contains("guard dockState.slowPick != nil else { return false }"), "«¿Sigues viendo?» no se cierra tocando fuera")
        XCTAssertTrue(code.contains("ScrollView") && code.contains("ViewThatFits(in: .vertical)"), "si no cabe (horizontal, letra grande) se desplaza, nunca cortada")
        for haptic in [".sensoryFeedback", "FeedbackGenerator", "Haptics."] { XCTAssertFalse(code.contains(haptic), "el reproductor no vibra (\(haptic))") }
        XCTAssertFalse(code.contains(".sheet("), "en el reproductor la pregunta no es una hoja")
        let piece = try XCTUnwrap(try sources(["Design"]).first { $0.name == "ChoiceSheet.swift" }).lines.joined(separator: "\n")
        XCTAssertTrue(piece.contains("var floating = false") && piece.contains(".glassEffect("), "flotando, de vidrio como los paneles del reproductor")
    }
}
