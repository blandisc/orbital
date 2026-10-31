import XCTest
@testable import OrbitalCore

/// La regla «nada se crea suelto» (como `tests/web/design-system.test.mjs` en la TV): la paleta es la misma que la de
/// Orbital y las pantallas no escriben colores, tamaños de letra ni duraciones a mano.
final class DesignTests: XCTestCase {
    var repo: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    func testPaletteMatchesOrbitalsPaletteJSON() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent("orbital/web/styles/palette.json"))
        let json = try XCTUnwrap(JSON.parse(data)?.object)
        for (name, hex) in DesignTokens.palette {
            XCTAssertEqual(json[name]?.string?.lowercased(), hex.lowercased(), "el color \(name) cambió en Orbital: actualiza DesignTokens")
        }
        let known = Set(DesignTokens.palette.keys)
        for key in json.keys where key != "_" { XCTAssertTrue(known.contains(key), "Orbital tiene un color nuevo («\(key)») que falta en DesignTokens") }
    }

    /// Una sola experiencia: espacios, radios, duraciones, opacidades y papeles iguales a `design/tokens.json`, el archivo que
    /// también vigila la TV (`tests/web/design-parity.test.mjs`, que además lee este código en CI).
    func testTokensMatchSharedJSON() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent("design/tokens.json"))
        let json = try XCTUnwrap(JSON.parse(data)?.object)
        func num(_ value: JSON?) -> Double? {
            switch value { case .int(let i)?: Double(i); case .double(let d)?: d; default: nil }
        }
        func group(_ name: String) throws -> [String: JSON] { try XCTUnwrap(json[name]?.object, "falta «\(name)» en tokens.json") }

        let space = try group("space")
        let spaces: [String: Double] = ["1": DesignTokens.Space.s1, "2": DesignTokens.Space.s2, "3": DesignTokens.Space.s3, "4": DesignTokens.Space.s4,
                                        "5": DesignTokens.Space.s5, "6": DesignTokens.Space.s6, "8": DesignTokens.Space.s8, "10": DesignTokens.Space.s10, "14": DesignTokens.Space.s14]
        for (key, value) in spaces { XCTAssertEqual(num(space[key]), value, "Space.s\(key)") }

        let radius = try group("radius")
        let radii: [String: Double] = ["xs": DesignTokens.Radius.xs, "sm": DesignTokens.Radius.sm, "md": DesignTokens.Radius.md,
                                       "lg": DesignTokens.Radius.lg, "xl": DesignTokens.Radius.xl, "xxl": DesignTokens.Radius.xxl]
        for (key, value) in radii { XCTAssertEqual(num(radius[key]?.object?["value"]), value, "Radius.\(key)") }

        let duration = try group("duration")
        let motion: [String: Double] = ["fast": DesignTokens.Motion.fast, "base": DesignTokens.Motion.base, "slow": DesignTokens.Motion.slow,
                                        "enter": DesignTokens.Motion.enter, "tint": DesignTokens.Motion.tint]
        for (key, seconds) in motion { XCTAssertEqual(num(duration[key]), (seconds * 1000).rounded(), "Motion.\(key) (la TV manda)") }

        let opacity = try group("opacity")
        let opacities: [String: Double] = ["hairline": DesignTokens.Opacity.hairline, "fill": DesignTokens.Opacity.fill, "fillStrong": DesignTokens.Opacity.fillStrong,
                                           "faint": DesignTokens.Opacity.faint, "track": DesignTokens.Opacity.track, "scrim": DesignTokens.Opacity.scrim,
                                           "badge": DesignTokens.Opacity.badge, "onArtSecondary": DesignTokens.Opacity.onArtSecondary]
        for (key, value) in opacities { XCTAssertEqual(num(opacity[key]?.object?["value"]), value, "Opacity.\(key)") }

        let platforms = try group("platforms")
        for (brand, hex) in DesignTokens.Platform.hex { XCTAssertEqual(platforms[brand]?.string, hex, "Platform.\(brand)") }

        // Los papeles en oscuro: el color de la paleta (o el del iPhone, si la diferencia está explicada).
        let roles = try group("roles")
        for role in DesignTokens.Role.allCases {
            let spec = try XCTUnwrap(roles[role.rawValue]?.object, "tokens.json no tiene el papel «\(role.rawValue)»")
            guard let name = spec["ios"]?.string ?? spec["color"]?.string else { continue }   // `overlay`: lo revisa la prueba de la TV
            XCTAssertEqual(role.hex.dark.lowercased(), DesignTokens.palette[name], "Role.\(role.rawValue) (oscuro)")
        }
    }

    /// Modo claro y oscuro: el texto se lee en los dos (WCAG AA), y el acento y la acción principal se distinguen del fondo.
    func testBothAppearancesHaveReadableContrast() {
        typealias R = DesignTokens.Role
        for mode in ["dark", "light"] {
            func hex(_ role: R) -> String { mode == "dark" ? role.hex.dark : role.hex.light }
            for background in [R.background, .surface] {
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.label), hex(background)), 7, "\(mode): texto sobre \(background)")
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.secondaryLabel), hex(background)), 4.5, "\(mode): texto secundario sobre \(background)")
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.accent), hex(background)), 4.5, "\(mode): el acento se lee sobre \(background)")
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.live), hex(background)), 4.5, "\(mode): «En vivo» se lee sobre \(background)")
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.danger), hex(background)), 4.5, "\(mode): el error se lee sobre \(background)")
            }
            XCTAssertGreaterThanOrEqual(DesignTokens.contrast(hex(.onPrimary), hex(.primary)), 7, "\(mode): texto del botón principal")
            // «Aumentar contraste»: cada texto contrasta más que en el modo normal y el fondo se separa más de la superficie.
            func high(_ role: R) -> String { mode == "dark" ? role.highContrastHex.dark : role.highContrastHex.light }
            for background in [R.background, .surface] {
                for role in [R.label, .secondaryLabel, .tertiaryLabel, .accent, .live, .warning, .danger] {
                    XCTAssertGreaterThan(DesignTokens.contrast(high(role), high(background)), DesignTokens.contrast(hex(role), hex(background)),
                                         "\(mode) con alto contraste: \(role) sobre \(background)")
                }
                XCTAssertGreaterThanOrEqual(DesignTokens.contrast(high(.secondaryLabel), high(background)), 7, "\(mode) con alto contraste: texto secundario sobre \(background)")
            }
            XCTAssertGreaterThan(DesignTokens.contrast(high(.background), high(.surface)), DesignTokens.contrast(hex(.background), hex(.surface)),
                                 "\(mode) con alto contraste: el fondo se separa más de la superficie")
            XCTAssertGreaterThanOrEqual(DesignTokens.contrast(high(.onPrimary), high(.primary)), 7, "\(mode) con alto contraste: texto del botón principal")
            // Los íconos de las listas (no son texto: 3:1).
            for (name, tint) in DesignTokens.ListTint.hex {
                for background in [R.background, .surface] {
                    let color = mode == "dark" ? tint.dark : tint.light
                    XCTAssertGreaterThanOrEqual(DesignTokens.contrast(color, hex(background)), 3, "\(mode): el color de la lista «\(name)» sobre \(background)")
                }
            }
        }
    }

    func testHexParsing() throws {
        let c = try XCTUnwrap(rgb(hex: "#f5f4f0"))
        XCTAssertEqual(c.r, 245.0 / 255, accuracy: 1e-9)
        XCTAssertNil(rgb(hex: "#12345")); XCTAssertNil(rgb(hex: "zzzzzz"))
        for (_, hex) in DesignTokens.palette { XCTAssertNotNil(rgb(hex: hex)) }
    }

    /// Los encabezados en dos niveles (30 oct 2026): una sección (`level: .section`) va sola, sin porqué; una subsección (toda
    /// fila o estante: `DSSectionHead`, `Shelf`, `Rail`) lleva siempre su porqué en turquesa (`eyebrow:` o `meta:`).
    func testSectionsHaveNoReasonAndSubsectionsAlwaysDo() throws {
        let screens = repo.appendingPathComponent("ios/App/Sources/Screens")
        let files = try FileManager.default.contentsOfDirectory(at: screens, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        var problems: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let chars = Array(text)
            for name in ["DSSectionHead(", "Shelf(", "Rail("] {
                var search = text.startIndex
                while let found = text.range(of: name, range: search..<text.endIndex) {
                    search = found.upperBound
                    let start = text.distance(from: text.startIndex, to: found.lowerBound)
                    // Solo la pieza misma (no `HomeShelf(` ni `struct Rail(`).
                    if start > 0, chars[start - 1].isLetter || chars[start - 1].isNumber { continue }
                    var depth = 1, end = start + name.count
                    while depth > 0, end < chars.count { if chars[end] == "(" { depth += 1 } else if chars[end] == ")" { depth -= 1 }; end += 1 }
                    let call = String(chars[start..<end])
                    let line = chars[..<start].filter { $0 == "\n" }.count + 1
                    let section = call.contains("level: .section"), reason = call.contains("eyebrow:") || call.contains("meta:")
                    if section && reason { problems.append("\(file.lastPathComponent):\(line): una sección no lleva porqué (lo que explica va en el cuerpo)") }
                    if !section && !reason { problems.append("\(file.lastPathComponent):\(line): una subsección lleva su porqué en turquesa (eyebrow:)") }
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "Encabezados fuera de la regla:\n" + problems.joined(separator: "\n"))
    }

    /// El porqué de una subsección cabe en un renglón en un iPhone SE (≤ 38 letras) y no promete cifras que pueden cambiar
    /// (lenguaje de diseño, regla 3: «Más de 50 formas» mentía si había menos).
    func testReasonsFitOneLineAndPromiseNoNumbers() throws {
        let roots = ["ios/App/Sources/Screens", "ios/App/Sources/Design"].map { repo.appendingPathComponent($0) }
        let files = roots.compactMap { FileManager.default.enumerator(at: $0, includingPropertiesForKeys: nil) }.flatMap { $0.allObjects }
        let pattern = try NSRegularExpression(pattern: #"(?:eyebrow:|Eyebrow\(text:)\s*Text\("([^"\\]*)"\)"#)
        var problems: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let reason = String(text[range])
                if reason.count > 38 { problems.append("\(file.lastPathComponent): «\(reason)» (\(reason.count) letras, máximo 38)") }
                if reason.range(of: #"\d"#, options: .regularExpression) != nil { problems.append("\(file.lastPathComponent): «\(reason)» promete una cifra") }
            }
        }
        XCTAssertTrue(problems.isEmpty, "Porqués fuera de la regla:\n" + problems.joined(separator: "\n"))
    }

    /// Un contenedor con identificador no tapa los de adentro (lenguaje de diseño, regla 8): SwiftUI le pone el id del
    /// contenedor a cada hijo si no se declara `.accessibilityElement(children: .contain)`, y VoiceOver y las pruebas de
    /// interfaz ya no encuentran sus botones (pasó en el mazo, el Wrapped, el filtro, la repisa, la ficha y Ajustes).
    func testContainersWithAnIdentifierKeepTheirChildren() throws {
        let roots = ["ios/App/Sources/Screens", "ios/App/Sources/Design"].map { repo.appendingPathComponent($0) }
        let files = roots.compactMap { FileManager.default.enumerator(at: $0, includingPropertiesForKeys: nil) }.flatMap { $0.allObjects }
        // `Group` no cuenta: no es un contenedor, le pasa el id a su único hijo.
        let containers = #"^(VStack|HStack|ZStack|LazyVStack|LazyHStack|LazyVGrid|LazyHGrid|ScrollView|GeometryReader|List|Form)\b"#
        var problems: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains(".accessibilityIdentifier(") && !line.contains("ds-exception:") {
                // Sube por la cadena de modificadores hasta lo que los recibe.
                var head = index
                var chain = [line]
                while head > 0, lines[head].trimmingCharacters(in: .whitespaces).hasPrefix(".") || head == index {
                    head -= 1; chain.append(lines[head])
                }
                if chain.contains(where: { $0.contains(".accessibilityElement(") }) { continue }
                guard lines[head].trimmingCharacters(in: .whitespaces).hasSuffix("}") else { continue }
                // La apertura de ese bloque: si es un contenedor, sus hijos perderían su id.
                var depth = 0, opener = head
                while opener >= 0 {
                    depth += lines[opener].filter { $0 == "}" }.count - lines[opener].filter { $0 == "{" }.count
                    if depth <= 0 { break }
                    opener -= 1
                }
                guard opener >= 0 else { continue }
                let start = lines[opener].trimmingCharacters(in: .whitespaces)
                if start.range(of: containers, options: .regularExpression) != nil {
                    problems.append("\(file.lastPathComponent):\(index + 1): \(start.prefix(40))… lleva id sin .accessibilityElement(children: .contain)")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "Contenedores que tapan los ids de adentro:\n" + problems.joined(separator: "\n"))
    }

    /// Los archivos de pantalla (todo lo que no es el sistema de diseño) no pintan nada «suelto».
    func testScreensUseOnlyDesignSystemTokens() throws {
        // Las pantallas y la extensión de widgets (que usa los mismos tokens: `Sources/Design/Tokens.swift`).
        let sources = repo.appendingPathComponent("ios/App")
        let roots = ["ios/App/Sources", "ios/App/Widgets"].map { repo.appendingPathComponent($0) }
        let files = roots.compactMap { FileManager.default.enumerator(at: $0, includingPropertiesForKeys: nil) }.flatMap { $0.allObjects }
        XCTAssertEqual(files.isEmpty, false, "faltan ios/App/Sources y ios/App/Widgets")
        let forbidden: [(String, String)] = [
            (#"Color\(\s*(red|white|hue|\.sRGB)"#, "color escrito a mano"), (#"Color\(\s*""#, "color por nombre (usa un token)"),
            (#"UIColor\(\s*(red|white|hue|named)"#, "UIColor a mano"), (#"#colorLiteral"#, "color literal"), (#"\.foregroundColor\(\.(red|blue|green|white|black|gray|yellow|orange|pink|purple)"#, "color del sistema"),
            (#"\.(red|blue|green|yellow|orange|pink|purple)\b(?!\w)"#, "color del sistema"),
            (#"\.font\(\.system\(size:"#, "tamaño de letra a mano"), (#"\.animation\(\.[a-zA-Z]+\(duration:\s*[0-9.]+"#, "duración a mano"),
            (#"withAnimation\(\.[a-zA-Z]+\(duration:\s*[0-9.]+"#, "duración a mano"), (#"\.cornerRadius\(\s*[0-9]"#, "radio a mano"),
            (#"\.padding\(\s*[0-9]"#, "espacio a mano"), (#"\.zIndex\(\s*[0-9]"#, "capa a mano"),
            (#"\.frame\([^)]*\b(width|height|minHeight|maxWidth|minWidth|maxHeight):\s*[0-9]"#, "medida a mano"),
            (#"\.opacity\(\s*[0-9]"#, "opacidad a mano"), (#"sleep\(nanoseconds:\s*[0-9]"#, "espera a mano"),
            (#"(struct|class)\s+\w+\s*:\s*[^{]*\b(ButtonStyle|PrimitiveButtonStyle|ToggleStyle|PickerStyle|TabViewStyle|LabelStyle|MenuStyle)\b"#, "estilo de control propio: usa el nativo de Apple (HIG)"),
            (#"\.presentationBackground\s*[({]"#, "fondo de hoja propio: deja el vidrio nativo (Liquid Glass)"),
            // Lo que se colaba (revisión del 29 oct 2026): animar sin token (sin «Reducir movimiento»), resortes y letras a mano.
            (#"withAnimation\s*\{"#, "animación sin token: usa DS.Motion.…(reduceMotion)"), (#"\.spring\(response:\s*[0-9]"#, "resorte a mano"),
            (#"\.font\(\.system\("#, "letra a mano: usa una receta"),
            (#"\.listRowBackground\(DS\.fill\)"#, "renglón con relleno translúcido: los renglones van en DS.surface (blancos en claro)"),
            (#"\.aspectRatio\(\s*[0-9]"#, "relación de aspecto a mano"), (#"\.minimumScaleFactor\(\s*[0-9]"#, "escala a mano"),
            // Lenguaje de diseño (30 oct 2026): el velo bajo el texto sobre arte es una pieza; lo que se mueve solo se pausa.
            (#"LinearGradient\(.*(scrim|backdropDeep)"#, "velo armado a mano: ArtVeil"),
            (#"TimelineView\(\.animation\)"#, "animación continua sin pausa: TimelineView(.animation(paused: reduceMotion…))"),
        ]
        var problems: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let relative = file.path.replacingOccurrences(of: sources.path + "/", with: "")
            if relative.hasPrefix("Sources/Design/Tokens") { continue }   // aquí se convierten los tokens a SwiftUI; el resto, también del diseño, los usa
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() where !line.contains("ds-exception:") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                for (pattern, what) in forbidden where line.range(of: pattern, options: .regularExpression) != nil {
                    problems.append("\(relative):\(index + 1): \(what): \(line.trimmingCharacters(in: .whitespaces))")
                }
                // La app (no el widget, que tiene sus propios tamaños) solo escribe texto con las recetas de Proyección.
                if relative.hasPrefix("Sources/"), line.contains("DS.font(") {
                    problems.append("\(relative):\(index + 1): tamaño de letra suelto (usa una receta: DS.TextRecipe / .recipe(…)): \(line.trimmingCharacters(in: .whitespaces))")
                }
                // Las esperas de las pantallas son tokens (las de las capturas del modo demo, no).
                if relative.hasPrefix("Sources/Screens/") || relative.hasPrefix("Sources/Design/"), !line.contains("Demo"),
                   line.range(of: #"Task\.sleep\(for:\s*\.(seconds|milliseconds)\(\s*[0-9]"#, options: .regularExpression) != nil {
                    problems.append("\(relative):\(index + 1): espera a mano: \(line.trimmingCharacters(in: .whitespaces))")
                }
                // Una sola pieza por papel en las pantallas (lenguaje de diseño, 30 oct 2026): los botones, los selectores, los
                // vacíos y el porqué salen del catálogo, no se arman en cada pantalla.
                if relative.hasPrefix("Sources/Screens/") {
                    let pieces: [(String, String)] = [
                        (#"\.buttonStyle\(\.(borderedProminent|bordered|glassProminent)\)"#, "botón armado a mano: dsPrimaryButton, dsSolidPrimaryButton o dsSecondaryButton"),
                        (#"\.pickerStyle\(\.segmented\)"#, "selector armado a mano: DSSegmented (o DSKindFilter para el tipo)"),
                        (#"ContentUnavailableView\("#, "vacío armado a mano: DSEmptyState"),
                        (#"\.recipe\(\.eyebrow, color: (?!DS\.eyebrow\))"#, "porqué de otro color: el porqué va en turquesa (Eyebrow(reason: true) o DS.eyebrow)"),
                        (#"ProgressView\(\)\.frame\(maxWidth: \.infinity"#, "área cargando armada a mano: DSLoadingState (o el esqueleto de su forma)"),
                        (#"format: \.dateTime|\.formatted\(\)|DateFormatter\(\)|NumberFormatter\(\)"#, "número o fecha con el formato del teléfono: Strings.count / Strings.date (en el idioma de la app)"),
                        // Un nombre por cosa (glosario en docs/sistema-de-diseno.md).
                        (#"(?i)"[^"]*\btu watchlist\b[^"]*""#, "«tu watchlist»: en el iPhone se llama «Mi lista»"),
                        (#""¿Qué vemos\?""#, "«¿Qué vemos?»: el sorteo es «Decide por mí» (y el mazo, «¿Qué vemos hoy?»)"),
                        (#""Intentar de nuevo""#, "«Intentar de nuevo»: el botón es «Reintentar»"),
                        (#"(?i)"[^"]*\btu repisa\b[^"]*""#, "«tu repisa»: la pantalla se llama «Colecciones»"),
                    ]
                    for (pattern, what) in pieces where line.range(of: pattern, options: .regularExpression) != nil {
                        problems.append("\(relative):\(index + 1): \(what): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
                // Los colores fijos no cambian con el modo claro u oscuro: van los papeles (`DS.text`, `DS.bg`…).
                if relative.hasPrefix("Sources/Screens/"), line.range(of: #"Color\.(white|black)|\.foregroundStyle\(\.(white|black)\)"#, options: .regularExpression) != nil {
                    problems.append("\(relative):\(index + 1): color fijo (no cambia con el modo): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(problems.isEmpty, "Valores sueltos en las pantallas (usa un token o márcalo con «ds-exception: motivo»):\n" + problems.joined(separator: "\n"))
    }

    /// Toda hoja que arma su propio encabezado (sin barra de navegación) arranca a la misma distancia del asa:
    /// `dsSheetContent()` (`DS.Space.sheetTop`), en su archivo o donde se presenta (Fernando, 30 oct 2026: el calendario
    /// tenía el título pegado arriba y cada hoja usaba otro aire).
    /// Los avisos de abajo (`Toast`, la pastilla de calificar) se colocan con `dsNoticePlacement(lift:)`: siempre a
    /// `DS.Toast.gap` de lo que tengan debajo, nunca con un margen a ojo (antes uno quedaba a 28 pt de la barra y otro a 9).
    /// El reproductor pone los suyos arriba, sobre el video, y no cuenta.
    func testBottomNoticesKeepTheSameGap() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" && !$0.lastPathComponent.hasPrefix("PlayerScreen") }
        var problems: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let places = text.components(separatedBy: "\n").filter {
                ($0.contains("Toast(tone:") || $0.contains("RatingReminderHost()")) && !$0.contains("struct ")
            }
            if !places.isEmpty, !text.contains("dsNoticePlacement(") { problems.append(file.lastPathComponent) }
            for line in text.components(separatedBy: "\n") where line.contains("RatingReminderHost()") && line.contains(".padding(") {
                problems.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(problems.isEmpty, "Un aviso de abajo va con dsNoticePlacement (DS.Toast.gap de lo que tenga debajo):\n" + problems.joined(separator: "\n"))
    }

    func testSheetsWithTheirOwnHeaderUseTheSameTop() throws {
        let root = repo.appendingPathComponent("ios/App/Sources")
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        let texts = try Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) })
        let declared = { (name: String) in texts.first { $0.value.range(of: "struct \(name)\\b", options: .regularExpression) != nil } }
        var problems: [String] = []
        var checked = Set<String>()
        for (file, text) in texts {
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains(".sheet(") {
                // La vista que se presenta: la primera `Nombre(` en ese renglón o los dos de abajo.
                let window = lines[i..<min(lines.count, i + 3)].joined(separator: "\n")
                let after = window[window.range(of: ".sheet(")!.upperBound...]
                guard let match = after.range(of: #"\{[^A-Z]*([A-Z][A-Za-z]+)\("#, options: .regularExpression) else { continue }
                let name = String(after[match].drop { $0 != "{" }.dropFirst().drop { !$0.isUppercase }.prefix { $0.isLetter })
                guard let (home, body) = declared(name), !checked.contains(name) else { continue }
                if body.contains("NavigationStack") || body.contains("navigationTitle") { continue }   // la barra pone su aire
                if body.contains("dsSheetContent") || window.contains("dsSheetContent") || body.contains("ds-exception: sheet") { checked.insert(name); continue }
                problems.append("\(name) (\(home), presentada en \(file)): hoja sin barra y sin dsSheetContent()")
                checked.insert(name)
            }
        }
        XCTAssertTrue(problems.isEmpty, "El aire de arriba de una hoja es uno solo (dsSheetContent / DS.Space.sheetTop):\n" + problems.joined(separator: "\n"))
    }

    /// Los premios del iPhone son los de design/awards.json (los mismos que lee la TV): si cambia uno, se regenera con
    /// scripts/ios_awards.py.
    func testAwardsMatchTheSharedJSON() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent("design/awards.json"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let awards = try XCTUnwrap(json["awards"] as? [[String: Any]])
        XCTAssertEqual(awards.map { $0["id"] as? String }, Awards.all.map(\.id), "corre python3 scripts/ios_awards.py")
        for (shared, mine) in zip(awards, Awards.all) {
            let winners = (shared["winners"] as? [[String: Any]]) ?? []
            XCTAssertEqual(winners.map { $0["imdb"] as? String }, mine.winners.map(\.imdb), "\(mine.id): corre python3 scripts/ios_awards.py")
            XCTAssertEqual(winners.map { $0["award_year"] as? Int }, mine.winners.map(\.awardYear), mine.id)
        }
    }
}
