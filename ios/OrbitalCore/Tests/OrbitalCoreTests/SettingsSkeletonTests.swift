import XCTest

/// PA1-A (Fernando, 23 nov 2026): Ajustes con el mismo esqueleto que la TV. Primero lo que vale en las dos apps, en el orden
/// de la TV (Idiomas · Reproducción · Avisos · Cuentas · Complementos); abajo «En este aparato» (Apariencia, Descargas, tu
/// Orbital, Diagnóstico y Aprende). OneDrive y la clave de TMDB viven en Cuentas, como en la TV; ya no hay «Avanzado».
/// PA6-A: Diagnóstico reúne qué falla y cómo se arregla.
final class SettingsSkeletonTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return try String(contentsOf: url.appendingPathComponent("ios/App/Sources/\(path)"), encoding: .utf8)
    }

    /// Las posiciones de cada pedazo en el texto, en orden; falla si falta alguno o si no van en ese orden.
    private func assertInOrder(_ pieces: [String], in text: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        var last = text.startIndex
        for piece in pieces {
            guard let range = text.range(of: piece, range: last..<text.endIndex) else {
                return XCTFail("\(message): falta «\(piece)» o va antes de lo que debe", file: file, line: line)
            }
            last = range.upperBound
        }
    }

    func testTheRootFollowsTheTV() throws {
        let settings = try source("Screens/SettingsView.swift")
        let form = try XCTUnwrap(settings.range(of: "private func settingsForm").map { String(settings[$0.lowerBound...]) })
        assertInOrder(["ProfileCard(", "sharedSection(model, s)", "deviceSection(model, s)", "orbitalSettings(model)", "moreSection(model)"],
                      in: form, "Ajustes: perfil, lo de las dos apps, «En este aparato», tu Orbital, Diagnóstico y Aprende")
        assertInOrder(["func sharedSection", "languagesRow(model)", "SettingsLink(.playback)", "SettingsLink(.alerts)", "SettingsLink(.accounts)",
                       "SettingsLink(.addons)", "func deviceSection", "SettingsLink(.appearance)", "SettingsLink(.downloads)",
                       "header: { Text(\"En este aparato\") }", "func moreSection", "SettingsLink(.diagnostics)", "SettingsLink(.learn)"],
                      in: settings, "el orden de la TV: Idiomas, Reproducción, Avisos, Cuentas, Complementos")
        let pages = try source("Design/SettingsParts.swift")
        XCTAssertFalse(pages.contains("case .advanced") || pages.contains("case .oneDrive"), "sin «Avanzado» ni OneDrive suelto en la raíz")
    }

    func testOneDriveAndTheTMDBKeyLiveInAccounts() throws {
        let accounts = try source("Screens/SettingsView+Cuentas.swift")
        XCTAssertTrue(accounts.contains("OneDriveSettings()"), "OneDrive, dentro de Cuentas (como la TV)")
        XCTAssertTrue(accounts.contains("header: { Text(\"Claves de Explorar\") }") && accounts.contains("setTMDBKey"),
                      "la clave de TMDB, en Cuentas › Claves de Explorar (así le dice la TV)")
    }

    func testDiagnosticsReusesWhatEachPageAlreadyHas() throws {
        let page = try source("Screens/SettingsView+Diagnostico.swift")
        for piece in ["scrobbleRow(model)", "traktDiscardsRow", "DebridAccountView(debrid:", "model.renewURL", "AddonHealthLine(",
                      "DownloadSpeedTestView()", "diagnoseConnection()", "ConnectionTrail.message"] {
            XCTAssertTrue(page.contains(piece), "Diagnóstico reúsa «\(piece)» en vez de repetir su lógica")
        }
        // Cada grupo, solo en la versión que lo trae.
        for gate in ["if entries.realDebrid { cloudDiagnosis }", "if entries.addons { DiagnosisAddons() }",
                     "if env.services.capabilities.instantStreams { speedDiagnosis }", "if entries.orbital, model.settings.orbitalEnabled"] {
            XCTAssertTrue(page.contains(gate), "Diagnóstico: falta la guardia «\(gate)»")
        }
    }
}

/// PA7-A: las pestañas de la ficha ancha (iPad, Mac) se llaman como las secciones del iPhone y la TV.
final class TitleTabNamesTests: XCTestCase {
    func testWideTabsUseTheSameNamesAsTheIPhone() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let tabs = try String(contentsOf: url.appendingPathComponent("ios/App/Sources/Screens/TitleView+WideTab.swift"), encoding: .utf8)
        let iphone = try String(contentsOf: url.appendingPathComponent("ios/App/Sources/Screens/TitleView+Detalles.swift"), encoding: .utf8)
        for name in ["Reparto y equipo", "Más como esto"] {
            XCTAssertTrue(tabs.contains("Text(\"\(name)\")") && iphone.contains("\"\(name)\""), "la pestaña y la sección dicen «\(name)»")
        }
        XCTAssertFalse(tabs.contains("Text(\"Reparto\")") || tabs.contains("Text(\"Parecidas\")"), "sin los nombres cortos")
    }
}
