import XCTest

/// Las decisiones de Fernando del 2 nov 2026 (canvas «unslop vs Impeccable»), como reglas del sistema de diseño: si una se
/// rompe en cualquier pantalla, esta prueba lo dice. Él lo pidió así: «cuando te pido un cambio, impacta el sistema de diseño
/// y modifica todo lo demás que esté igual». Detalle en docs/sistema-de-diseno.md › «Decisiones del 2 nov 2026».
extension DesignRulesTests {
    /// «Ver todo» es la flecha pegada al título (`DSTitleChevron`), nunca una cápsula de texto.
    func testSeeAllIsTheTitleChevron() throws {
        let files = try sources()
        check(hits(#"DSCapsuleLabel\(title: Text\("Ver "#, in: files), "«Ver …» va como flecha del título (DSTitleChevron), no en cápsula")
        check(hits(#"struct SeeAllLabel"#, in: files), "SeeAllLabel ya no existe: usa DSTitleChevron")
    }

    /// Sin reflejos bajo pósters ni tarjetas, en ningún lado.
    func testNoReflections() throws {
        check(hits(#"scaleEffect\(x: 1, y: -1\)|[Rr]eflection\b|reflected\b"#, in: try sources()), "Sin reflejos (se quitaron de toda la app)")
    }

    /// La barra de pestañas siempre completa: nunca se encoge ni se esconde al bajar.
    func testTabBarAlwaysFull() throws {
        let files = try sources(["Design", "Screens", "App"])
        check(hits(#"tabBarMinimizeBehavior\("#, in: files, unless: #"\(\.never\)"#), "La barra de pestañas no se encoge (.never)")
        check(hits(#"for: \.tabBar"#, in: files), "La barra de pestañas no se esconde")
    }

    /// Nada en mayúsculas en la app: todo en letra normal. La única excepción es el sello del mazo de Match, que imita un
    /// sello físico (Fernando, 2 nov 2026).
    func testNoSpacedCaps() throws {
        check(hits(#"\.dsCaps\(\)"#, in: try sources(), skip: { $0.name.hasPrefix("MazoMatch") }),
              "Sin mayúsculas: todo en letra normal (solo el sello de Match)")
    }

    /// Lo nuevo y lo de hoy van en el turquesa del logo (`DS.fresh`), no en el verde de «listo».
    func testNewAndTodayAreFresh() throws {
        let files = try sources().filter { ["HomeTimeline", "CornerRibbon", "Projection"].contains(($0.name as NSString).deletingPathExtension) }
        check(hits(#"DS\.(success|onSuccess)\b"#, in: files), "«Hoy» y «Nuevo» van en DS.fresh (el turquesa del logo)")
    }

    /// Un solo interruptor: el turquesa de la marca lo pone `DSSwitchStyle` para toda la app; ninguna pantalla lo pinta.
    func testTogglesAreNotTintedPerScreen() throws {
        check(hits(#"\.tint\(DS\.switchOn\)"#, in: try sources(), skip: { $0.name == "Buttons.swift" }), "Los interruptores los pinta DSSwitchStyle, no cada pantalla")
    }

    /// El turquesa es la voz de Orbital (el porqué, lo nuevo, lo encendido o lo que pasa ahora), nunca decoración: no pinta
    /// fondos, orillas ni íconos sueltos (Fernando, 2 nov 2026).
    func testTurquoiseIsNotDecoration() throws {
        check(hits(#"(background|strokeBorder|stroke)\(DS\.(orbitalBlue|brandMoon|eyebrow)\b"#, in: try sources(), skip: isArt),
              "El turquesa no pinta fondos ni orillas")
        check(hits(#"Image\(systemName:[^)]*\)[^\n]*foregroundStyle\(DS\.orbitalBlue\)"#, in: try sources()),
              "El turquesa no pinta íconos sueltos")
    }

    /// De dónde viene una lista lo dice su porqué; el sello de Trakt ya no va junto a un título.
    func testTraktIsNotATitleStamp() throws {
        check(hits(#"source: \.trakt\b"#, in: try sources()), "Trakt va en el porqué («Recomendadas por Trakt»), no como sello del título")
    }
}
