import XCTest

/// Las 13 reglas del sistema de diseño que salieron de la auditoría del 31 oct 2026 (docs/producto/auditoria-ios-2026-10-31/,
/// sección D). Revisan `ios/App/Sources/Design/` y `Screens/` completas (con sus subcarpetas, como `Screens/Onboarding/`).
/// Una excepción legítima se marca en su renglón con `ds-exception: <motivo>`; las que valen para un archivo entero
/// (el reproductor sobre el video, la tele de Los Simpson, la marca, el iPod, el mosaico y el cielo) están en cada regla.
final class DesignRulesTests: XCTestCase {
    var repo: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }

    /// Un archivo de la app: su ruta desde `ios/App/Sources/` y sus renglones.
    struct Source { let path: String; let lines: [String]; var name: String { (path as NSString).lastPathComponent } }

    func sources(_ folders: [String] = ["Design", "Screens"]) throws -> [Source] {
        let root = repo.appendingPathComponent("ios/App/Sources")
        var out: [Source] = []
        for folder in folders {
            let base = root.appendingPathComponent(folder)
            let files = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)).allObjects
            for case let file as URL in files where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                out.append(Source(path: file.path.replacingOccurrences(of: root.path + "/", with: ""), lines: text.components(separatedBy: "\n")))
            }
        }
        XCTAssertFalse(out.isEmpty, "faltan ios/App/Sources/Design y Screens")
        return out.sorted { $0.path < $1.path }
    }

    /// Los renglones de código (sin comentarios de renglón completo ni excepciones marcadas) que cumplen `pattern`.
    func hits(_ pattern: String, in files: [Source], skip: (Source) -> Bool = { _ in false }, unless: String? = nil) -> [String] {
        var out: [String] = []
        for file in files where !skip(file) {
            for (i, line) in file.lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || code.hasPrefix("///") || line.contains("ds-exception:") { continue }
                guard line.range(of: pattern, options: .regularExpression) != nil else { continue }
                if let unless, line.range(of: unless, options: .regularExpression) != nil { continue }
                out.append("\(file.path):\(i + 1): \(code.prefix(140))")
            }
        }
        return out
    }

    func isTokens(_ f: Source) -> Bool { f.name.hasPrefix("Tokens") }
    /// El reproductor dibuja sobre el video (siempre oscuro, sus propios controles): sus excepciones están documentadas.
    func isPlayer(_ f: Source) -> Bool {
        ["PlayerScreen", "PlayerControls", "PlayerIndicators", "PlayerFailureView", "SubtitlePanel", "SubtitleSync", "IPod", "PlayerEngines"]
            .contains { f.name.hasPrefix($0) }
    }
    /// Arte con reglas propias: la marca y la bienvenida, la tele de Los Simpson, el mosaico y el cielo.
    func isArt(_ f: Source) -> Bool {
        ["Brand", "Splash", "SimpsonsRoulette", "Mosaic", "Sky"].contains { f.name.hasPrefix($0) }
    }

    func check(_ problems: [String], _ rule: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(problems.isEmpty, "\(rule) (\(problems.count)):\n" + problems.joined(separator: "\n"), file: file, line: line)
    }

    // MARK: 1 · Tokens de pieza en la escala

    /// Los radios y los espacios de una pieza (`Tokens+*.swift`) salen de la escala (`DS.Radius.*`, `DS.Space.*`): un número
    /// suelto es un valor inventado. Lo que de verdad no es de la escala (el arte, una medida física) va en `allowedOffScale`
    /// con su motivo, o con `ds-exception:` en su renglón.
    static let allowedOffScale: [String: String] = [
        "Brand.planetRadius": "la marca se dibuja en su caja de 32 (geometría del logo, no una esquina)",
        "Ribbon.center": "dónde cruza la banda del listón: geometría del giro de 45°",
        "Backdrop.lowGlowRadius": "el radio del brillo del fondo (un degradado, no una esquina)",
        "Backdrop.immersiveGlowRadius": "el radio del brillo de la ficha inmersiva (un degradado)",
    ]

    func testPieceTokensStayOnTheScale() throws {
        let tokens = try sources(["Design"]).filter(isTokens)
        let decl = try NSRegularExpression(pattern: #"(\w+)\s*(?::\s*CGFloat)?\s*=\s*(-?[0-9][0-9.]*)\b(?!\s*[*/+])"#)
        let scaled = #"(?i)(radius|gap|padding|inset|spacing)$"#
        var problems: [String] = []
        for file in tokens {
            var scope: [String] = []
            for (i, line) in file.lines.enumerated() {
                if let m = line.range(of: #"^\s*(?:enum|struct)\s+(\w+)"#, options: .regularExpression) {
                    let name = line[m].split(separator: " ").last.map(String.init) ?? ""
                    scope.append(name.trimmingCharacters(in: .punctuationCharacters))
                }
                if line.contains("ds-exception:") || !line.contains("static let") { continue }
                let ns = line as NSString
                for match in decl.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let name = ns.substring(with: match.range(at: 1))
                    guard name.range(of: scaled, options: .regularExpression) != nil else { continue }
                    let key = "\(scope.last ?? "DS").\(name)"
                    if Self.allowedOffScale[key] != nil { continue }
                    problems.append("\(file.path):\(i + 1): \(key) = \(ns.substring(with: match.range(at: 2))) (usa DS.Radius.* o DS.Space.*)")
                }
                _ = i
            }
        }
        check(problems, "Tokens de pieza fuera de la escala")
    }

    // MARK: 2 · Sin cuentas que inventan valores

    func testNoArithmeticThatInventsValues() throws {
        let files = try sources()
        var problems: [String] = []
        problems += hits(#"DS\.Size\.hairline\s*\*\s*[0-9]"#, in: files)
        problems += hits(#"cornerRadius:\s*DS\.[A-Za-z.]+\s*[*/]\s*[0-9]"#, in: files, unless: #"/\s*2\b"#)
        problems += hits(#"tracking\(\s*-?DS\.[A-Za-z.]*(Radius|radius)"#, in: files)
        problems += hits(#"lineWidth:\s*DS\.Space\."#, in: files)
        check(problems, "Cuentas que inventan un valor (usa DS.Stroke, DS.Radius o un token con nombre)")
    }

    // MARK: 3 · Recetas sin torcer

    func testRecipesAreNotTwisted() throws {
        let files = try sources()
        let skip = { (f: Source) in ["PlayerControls", "IPod", "Brand", "SimpsonsRoulette"].contains { f.name.hasPrefix($0) } || self.isTokens(f) }
        var problems = hits(#"TextRecipe\.\w+\.font\.weight\("#, in: files, skip: skip)
        problems += hits(#"\.recipe\([^)]*\)\.fontWeight\("#, in: files, skip: skip)
        problems += hits(#"TextRecipe\.\w+\.font\)\.fontWeight\("#, in: files, skip: skip)
        check(problems, "Receta torcida con .weight: usa label, labelLarge, badge, groupLabel o stat")
    }

    // MARK: 4 · Sombras solo con DS.Elevation o DS.Glow

    func testShadowsComeFromElevationOrGlow() throws {
        let files = try sources()
        let problems = hits(#"\.shadow\(color:"#, in: files, skip: { self.isTokens($0) || $0.name == "Surfaces.swift" || self.isArt($0) || self.isPlayer($0) })
        check(problems, "Sombra a mano: usa .shadow(DS.Elevation.…) o .glow(color, .soft/.strong)")
    }

    // MARK: 5 · Botones nativos

    func testButtonsAreNative() throws {
        let files = try sources()
        let own = { (f: Source) in f.name == "Buttons.swift" || f.name == "Surfaces.swift" || self.isPlayer(f) || f.name.hasPrefix("Remote") || self.isArt(f) }
        var problems = hits(#"\.buttonStyle\(\.glass\)"#, in: files, skip: own)
        problems += hits(#"buttonBorderShape\(\.circle\)"#, in: files, skip: own)
        // Un `.plain` que pinta su propia cápsula de color: eso es un botón nativo armado a mano.
        for file in files where !own(file) {
            for (i, line) in file.lines.enumerated() where line.contains(".buttonStyle(.plain)") && !line.contains("ds-exception:") {
                let window = file.lines[max(0, i - 8)...i].joined(separator: "\n")
                if window.range(of: #"\.background\([^)]*, in: Capsule\(\)\)"#, options: .regularExpression) != nil {
                    problems.append("\(file.path):\(i + 1): botón .plain con cápsula de color")
                }
            }
        }
        check(problems, "Botón armado a mano: DSIconButton, dsPrimaryButton(size:), dsSecondaryButton, dsGlassButton")
    }

    // MARK: 6 · Una caja, una pieza

    func testBoxesUseDSCard() throws {
        let files = try sources()
        let problems = hits(#"\.background\(DS\.(fill|surface|surfaceRaised), in: RoundedRectangle"#, in: files, skip: { $0.name == "Surfaces.swift" || self.isTokens($0) })
        check(problems, "Caja armada a mano: .dsCard(.row / .card)")
    }

    // MARK: 7 · RoundedRectangle siempre continua

    func testRoundedRectanglesAreContinuous() throws {
        let files = try sources()
        let problems = hits(#"RoundedRectangle\(cornerRadius:"#, in: files, skip: isPlayer, unless: #"style:\s*\.continuous"#)
        check(problems, "RoundedRectangle sin style: .continuous")
    }

    // MARK: 8 · Movimiento con tokens

    func testMotionUsesTokens() throws {
        let files = try sources()
        var problems = hits(#"DS\.Motion\.\w+\(false\)"#, in: files)
        problems += hits(#"(?<!Motion)\.(spring|snappy|bouncy|smooth|easeIn|easeOut|easeInOut|linear)\("#, in: files,
                         skip: { self.isTokens($0) || self.isArt($0) })
        check(problems, "Movimiento a mano: DS.Motion.fade (también con «Reducir movimiento»), .snap, .reveal, .appear o los de siempre")
    }

    // MARK: 9 · Vacíos y cargas con su pieza

    func testEmptyAndLoadingStatesUsePieces() throws {
        let files = try sources()
        let own = { (f: Source) in ["Feedback.swift", "Surfaces.swift"].contains(f.name) || self.isPlayer(f) }
        var problems = hits(#"ProgressView\(\)"#, in: files, skip: own)
        problems += hits(#"ContentUnavailableView"#, in: files, skip: own)
        check(problems, "Carga o vacío a mano: DSLoadingState, DSInlineProgress, DSEmptyState o el esqueleto de su forma")
    }

    // MARK: 10 · Papel solo sobre arte

    /// El verde de «listo» se lee en los dos modos (`DesignTests.testBothAppearancesHaveReadableContrast`); el papel fijo
    /// (`DS.paper`, que no cambia con el modo) solo como fondo de algo que va sobre arte.
    func testPaperOnlyOverArt() throws {
        let files = try sources()
        let problems = hits(#"background\(DS\.paper"#, in: files, skip: { self.isTokens($0) || self.isArt($0) || self.isPlayer($0) })
        check(problems, "Fondo en papel fijo fuera del arte (no cambia con el modo): usa un papel (DS.primary, DS.surface…)")
    }

    // MARK: 11 · Ritmo de pantalla con DS.Layout

    /// El primer contenedor de cada pantalla que se desplaza (Screens/) separa lo suyo con `DS.Layout` (del título a lo suyo,
    /// entre subsecciones, entre secciones), como promete `DS.Layout` en Tokens.swift.
    func testScreensKeepTheLayoutRhythm() throws {
        let files = try sources(["Screens"])
        var problems: [String] = []
        for file in files where !isPlayer(file) && !isArt(file) {
            for (i, line) in file.lines.enumerated() where line.range(of: #"ScrollView(\(\.vertical[^)]*\)|\(\))?\s*\{"#, options: .regularExpression) != nil {
                guard !line.contains("ds-exception:"), !line.contains(".horizontal") else { continue }
                // El primer stack de adentro (en los renglones que siguen).
                for next in file.lines[(i + 1)..<min(file.lines.count, i + 4)] {
                    guard next.range(of: #"^\s*(Lazy)?VStack\("#, options: .regularExpression) != nil else { continue }
                    if next.contains("ds-exception:") { break }
                    if !next.contains("DS.Layout.") { problems.append("\(file.path):\(i + 1): \(next.trimmingCharacters(in: .whitespaces).prefix(110))") }
                    break
                }
            }
        }
        check(problems, "Primer stack de una pantalla sin DS.Layout (titleToContent, betweenSubsections, betweenSections)")
    }

    // MARK: 12 · Hojas, cerrar y mayúsculas

    /// Toda hoja con encabezado propio usa `DSSheetHeader`; el ✕ de cerrar solo vive en `DSIconButton`; ningún texto se
    /// escribe en MAYÚSCULAS (las pone la pieza con `.textCase`, y así se traduce bien).
    func testSheetsCloseAndCase() throws {
        let files = try sources()
        var problems: [String] = []
        for file in files where file.lines.contains(where: { $0.contains(".dsSheetContent(") }) && !isPlayer(file) {
            problems += hits(#"\.recipe\(\.(title|section)\b"#, in: [file]).map { $0 + " (título de hoja: DSSheetHeader)" }
        }
        problems += hits(#"Image\(systemName:\s*"xmark"\)"#, in: files, skip: { ["Buttons.swift", "Surfaces.swift"].contains($0.name) || self.isPlayer($0) || $0.name.hasPrefix("Remote") })
        let acronyms = #"\b(IMDb|HDR|SDR|TMDB|IMDB|DTS|AAC|URL|PIN|VPN|API|MKV|HEVC|OK|DV|IPTV|UHD|FHD|LG|USB|QR|NYT|AFI|BAFTA|AI|HBO|ID|MB|GB|KB|FPS|DNS|IP)\b"#
        problems += hits(#"Text\("[^"\\]*[A-ZÁÉÍÓÚÑ]{3,}"#, in: files, unless: nil).filter { hit in
            // Las siglas sí van en mayúsculas.
            let quoted = hit.components(separatedBy: "Text(\"").dropFirst().map { $0.components(separatedBy: "\"").first ?? "" }
            return quoted.contains { q in q.replacingOccurrences(of: acronyms, with: "", options: .regularExpression).range(of: "[A-ZÁÉÍÓÚÑ]{3,}", options: .regularExpression) != nil }
        }
        check(problems, "Hojas, cerrar y mayúsculas")
    }

    // MARK: 13 · Tokens sin uso

    /// Todo token de `Tokens*.swift` se usa en algún lado (la app, el widget o otro token). Uno sin uso se borra.
    func testEveryTokenIsUsed() throws {
        let root = repo.appendingPathComponent("ios/App")
        let all = try ["Sources", "Widgets"].flatMap { folder -> [(String, String)] in
            let files = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)).allObjects
            return try files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
        }
        let corpus = all.map(\.1).joined(separator: "\n")
        let decl = try NSRegularExpression(pattern: #"static (?:let|var|func)\s+(\w+)|,\s*(\w+)\s*(?::\s*[A-Za-z]+\s*)?=\s*(?![=])"#)
        var problems: [String] = []
        for (name, text) in all where name.hasPrefix("Tokens") {
            var scope: [String] = []
            var depth = 0, scopeDepth: [Int] = []
            for (i, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if let m = line.range(of: #"^\s*(?:enum|struct)\s+\w+"#, options: .regularExpression) {
                    scope.append(String(line[m].split(separator: " ").last ?? "")); scopeDepth.append(depth)
                }
                depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
                while let last = scopeDepth.last, depth <= last { scopeDepth.removeLast(); scope.removeLast() }
                guard code.hasPrefix("static"), !line.contains("ds-exception:"), let owner = scope.last else { continue }
                let ns = line as NSString
                for match in decl.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let range = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
                    guard range.location != NSNotFound else { continue }
                    let token = ns.substring(with: range)
                    // Usado como `Dueño.token`, o por su nombre en otro renglón del mismo archivo de tokens.
                    let qualified = corpus.contains("\(owner).\(token)") ? 1 : 0
                    let bare = (try? NSRegularExpression(pattern: "(?<![\\w.])\(token)\\b"))
                        .map { $0.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) > 1 } ?? false
                    if qualified == 0 && !bare { problems.append("\(name):\(i + 1): \(owner).\(token)") }
                }
            }
        }
        check(problems, "Tokens sin uso (bórralos)")
    }
}
