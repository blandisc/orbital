import XCTest

/// La versión «Orbital» (App Store, D1-B) nunca dice «Real-Debrid», «Torrentio», «complemento», «consola» ni «controla la
/// TV» (revisión 2 del 11 nov 2026). Esta prueba lee los textos fijos de las vistas: esas palabras solo pueden estar en las
/// pantallas que esa versión no abre (`onlyWithCapability`, cada una con su porqué) o en un renglón marcado
/// `// edición: <por qué no sale en Orbital>`. Lo que todavía se cuela está en `stillLeaks`, que solo puede encogerse: una
/// palabra nueva en una pantalla compartida falla, y quitar una de la lista sin arreglarla también.
extension DesignRulesTests {
    static let editionWords = #""[^"]*(Real-Debrid|Torrentio|[Cc]omplemento|consola|controla la TV)[^"]*""#

    /// Pantallas que la versión Orbital no abre (sin `instantStreams` ni `console`).
    static let onlyWithCapability: [String: String] = [
        "AddonMark.swift": "marca de complemento en versiones (instantStreams)",
        "AddonPieces.swift": "Ajustes › Complementos (instantStreams)",
        "AddonDetail.swift": "Ajustes › Complementos (instantStreams)",
        "AddonsSettings.swift": "Ajustes › Complementos (instantStreams)",
        "Companion.swift": "el acompañante de los juegos de la consola (console)",
        "GameCompanionView.swift": "el acompañante de los juegos de la consola (console)",
        "DebridRedeem.swift": "canjear Real-Debrid (instantStreams)",
        "DebridRequests.swift": "pedidos a la nube (instantStreams)",
        "DebridReminderNotifier.swift": "avisos de Real-Debrid (instantStreams)",
        "DebridRequestNotifier.swift": "avisos de pedidos a la nube (instantStreams)",
        "DebridAccountView.swift": "Ajustes › Real-Debrid (instantStreams)",
        "DebridSharedSection.swift": "Ajustes › Real-Debrid (instantStreams)",
        "DebridTVSection.swift": "Ajustes › Real-Debrid de la TV (console)",
        "DownloadsCloud.swift": "Descargas › la nube (`showsCloudDownloads`)",
        "OnboardingDebrid.swift": "bienvenida de Real-Debrid (instantStreams)",
        "OrbitalDevicesSection.swift": "Ajustes › Orbital en la TV (console)",
        "OrbitalSetup.swift": "conectar con la TV (console)",
        "RemoteStatusCard.swift": "el control de la TV (console)",
        "SettingsView+Cuentas.swift": "la fila de Real-Debrid (`settingsEntries.realDebrid`)",
        "SettingsView+Orbital.swift": "Ajustes › Orbital en la TV (console)",
        "TitleView+RealDebrid.swift": "pedir a la nube desde la ficha (`offersInstant`)",
        "TorrentioSettings.swift": "Ajustes › Torrentio (instantStreams)",
        "TorrentioSettings+Opciones.swift": "Ajustes › Torrentio (instantStreams)",
        "VoiceGuideView.swift": "la voz de la TV (console)",
        "OrbitalIntents.swift": "atajos de Siri de la TV (console; las frases se compilan por versión)",
    ]

    /// Lo que todavía se cuela en pantallas compartidas (archivo y un pedazo del texto). Pendiente de D1-B: cada uno
    /// necesita su texto para la versión Orbital. Solo puede encogerse.
    static let stillLeaks: [(file: String, text: String)] = [
        ("Explainer.swift", "Real-Debrid"), ("Explainer.swift", "complementos"), ("Explainer.swift", "Torrentio"),
        ("Guide.swift", "Usa tu Real-Debrid"),
        ("PlayerFailureView.swift", "Tus complementos no contestan"), ("PlayerFailureView.swift", "Real-Debrid aún no tiene"),
        ("VersionList.swift", "Real-Debrid no lo dejó bajar"),
        ("OpenSubtitlesSettings.swift", "complemento de siempre"),
        ("ParaTiPieces.swift", "De tus complementos"),
        ("PlayerScreen.swift", "Real-Debrid aún no tiene esta versión"),
        ("SettingsView.swift", "la consola Orbital"), ("SettingsView.swift", "Real-Debrid"),
        ("SourcesSheet.swift", "Torrentio"),
        ("TitleView+Acciones.swift", "Tus complementos no contestan"),
        ("OnboardingChoose.swift", "Real-Debrid"),
        ("DownloadSpeedTest.swift", "Real-Debrid"), ("DownloadSpeedTestView.swift", "Real-Debrid"),
    ]

    func testOrbitalEditionNeverNamesTheCloudOrTheConsole() throws {
        let files = try sources([""])
        let regex = try NSRegularExpression(pattern: Self.editionWords)
        var leaks: [String] = []
        var seenKnown = Set<String>()
        var checked = Set<String>()
        for file in files where !file.path.contains("Support/") && Self.onlyWithCapability[file.name] == nil {
            guard checked.insert(file.path).inserted else { continue }
            for (i, line) in file.lines.enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") || line.contains("// edición:") { continue }
                let range = NSRange(line.startIndex..., in: line)
                guard regex.firstMatch(in: line, range: range) != nil else { continue }
                if let known = Self.stillLeaks.first(where: { file.name == $0.file && line.contains($0.text) }) {
                    seenKnown.insert("\(known.file)|\(known.text)")
                    continue
                }
                leaks.append("\(file.path):\(i + 1): \(code.prefix(140))")
            }
        }
        XCTAssertEqual(leaks, [], "Textos que la versión Orbital (App Store) mostraría con «Real-Debrid», «Torrentio», «complemento», «consola» o «controla la TV». Si la pantalla no sale en Orbital, agrégala a `onlyWithCapability`; si el renglón no sale, márcalo `// edición: <por qué>`:\n" + leaks.joined(separator: "\n"))
        let fixed = Self.stillLeaks.filter { !seenKnown.contains("\($0.file)|\($0.text)") }.map { "\($0.file): \($0.text)" }
        XCTAssertEqual(fixed, [], "Ya no se cuelan: quítalos de `stillLeaks` para que no vuelvan")
    }
}
