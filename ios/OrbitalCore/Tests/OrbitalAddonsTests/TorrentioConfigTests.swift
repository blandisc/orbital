import XCTest
@testable import OrbitalAddons

/// T1–T10 y C5: la dirección de Torrentio se arma igual que en la TV (tests/fixtures/torrentio-config.json), se lee de vuelta
/// con lo que la app no conoce tal cual, y tu clave nunca va a las opciones.
final class TorrentioConfigTests: XCTestCase {
    let token = String(repeating: "A1B2", count: 13)

    private func fixture() throws -> [[String: Any]] {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("tests/fixtures/torrentio-config.json"))) as? [String: Any])
        return try XCTUnwrap(json["cases"] as? [[String: Any]])
    }

    /// Las opciones del archivo compartido, con lo que no dice vacío (como Torrentio sin opciones).
    private func options(_ raw: [String: Any]) -> AddonOptions {
        AddonOptions(excludedQualities: raw["qualityfilter"] as? [String] ?? [], languages: raw["language"] as? [String] ?? [],
                     sort: raw["sort"] as? String, limit: raw["limit"] as? Int, sizeFilter: raw["sizefilter"] as? String,
                     providers: raw["providers"] as? [String] ?? [], debridOptions: raw["debridoptions"] as? [String] ?? [])
    }

    func testTheSharedFixtureBuildsAndParsesTheSameAddressAsTheTV() throws {
        let cases = try fixture()
        XCTAssertGreaterThanOrEqual(cases.count, 6)
        for item in cases {
            let name = item["name"] as? String ?? ""
            let raw = try XCTUnwrap(item["options"] as? [String: Any])
            let expected = try XCTUnwrap(item["url"] as? String).replacingOccurrences(of: "{CLAVE}", with: token)
            XCTAssertEqual(TorrentioConfig.manifestURL(options: options(raw), token: token), expected, name)
            guard item["parse"] as? Bool == true else { continue }
            let parsed = try XCTUnwrap(TorrentioConfig.parse(expected), name)
            XCTAssertEqual(parsed.options, options(raw), "se lee de vuelta: \(name)")
            XCTAssertEqual(parsed.key, token, "la clave aparte: \(name)")
            XCTAssertEqual(TorrentioConfig.manifestURL(options: parsed.options, token: token), expected, "ida y vuelta: \(name)")
        }
    }

    func testUnknownOptionsAreKeptVerbatimAndOtherServicesKeysAreDropped() throws {
        let url = "https://torrentio.strem.fun/sort=seeders|futureoption=on|language=latino|alldebrid=SECRETOTROSERVICIO1|qualityfilter=brremux|nuevo=a,b|realdebrid=\(token)/manifest.json"
        let parsed = try XCTUnwrap(TorrentioConfig.parse(url))
        XCTAssertEqual(parsed.options.verbatim, ["futureoption=on", "nuevo=a,b"])
        XCTAssertEqual(parsed.key, token)
        let encoded = String(data: try JSONEncoder().encode(parsed.options), encoding: .utf8) ?? ""
        XCTAssertFalse(encoded.contains(token) || encoded.contains("SECRETOTROSERVICIO1"), "ninguna clave va a las opciones (se guardan fuera del llavero)")
        // Cambias algo (T3): lo desconocido sigue, después de lo conocido y antes de tu clave nueva.
        var changed = parsed.options
        changed.excludedQualities = ["cam"]
        XCTAssertEqual(TorrentioConfig.manifestURL(options: changed, token: "NUEVA1234567"),
                       "https://torrentio.strem.fun/sort=seeders|language=latino|qualityfilter=cam|futureoption=on|nuevo=a,b|realdebrid=NUEVA1234567/manifest.json")
        XCTAssertNil(TorrentioConfig.parse("https://comet.elfhosted.com/abc/manifest.json"), "solo Torrentio")
        XCTAssertNil(TorrentioConfig.manifestURL(options: AddonOptions(), token: nil), "sin clave no se arma")
    }

    func testSizesForMoviesAndEpisodesSeparately() {
        XCTAssertNil(TorrentioConfig.sizeFilter(movies: nil, episodes: nil))
        XCTAssertEqual(TorrentioConfig.sizeFilter(movies: "5GB", episodes: "5GB"), "5GB")
        XCTAssertEqual(TorrentioConfig.sizeFilter(movies: "10GB", episodes: "2GB"), "10GB,2GB")
        XCTAssertEqual(TorrentioConfig.sizeFilter(movies: nil, episodes: "2GB"), "1000GB,2GB", "sin límite en un solo lado")
        XCTAssertTrue(TorrentioConfig.sizes("10GB,2GB") == ("10GB", "2GB"))
        XCTAssertTrue(TorrentioConfig.sizes("5GB") == ("5GB", "5GB"))
        XCTAssertTrue(TorrentioConfig.sizes("1000GB,2GB") == (nil, "2GB"))
        XCTAssertTrue(TorrentioConfig.sizes(nil) == (nil, nil))
    }

    func testTheLanguageOrderIsThePlanB() {
        XCTAssertEqual(TorrentioConfig.fallbackCodes(AddonOptions(languages: ["latino", "spanish", "japanese"])), ["es-419", "es-ES", "ja"])
        XCTAssertEqual(TorrentioConfig.languages.count, 41)
        XCTAssertEqual(TorrentioConfig.providers.count, 25)
        XCTAssertEqual(TorrentioConfig.qualities.count, 14)
    }
}

/// C5: tu Torrentio de Stremio pasa al de Orbital con todas sus opciones y tu clave de Cuentas; con dos, se pregunta.
final class TorrentioImportTests: XCTestCase {
    let token = String(repeating: "A1B2", count: 13)
    let old = String(repeating: "Z9Y8", count: 13)

    private func list(withKey: Bool = true) -> (AddonList, InMemoryAddonVault) {
        let vault = InMemoryAddonVault()
        if withKey { vault.setSecret(AddonKeys.realDebridToken, token) }
        let list = AddonList(vault: vault)
        list.startWithRecommended()
        return (list, vault)
    }

    func testASingleStremioTorrentioBecomesOrbitalsWithItsOptionsAndYourKey() throws {
        let (list, vault) = list()
        let url = "https://torrentio.strem.fun/sort=seeders|language=latino|qualityfilter=brremux,cam,scr|extra=1|realdebrid=\(old)/manifest.json"
        list.importOnce([.init(name: "Listas", url: "https://listas.example/manifest.json", resources: ["catalog"]),
                         .init(name: "Torrentio RD", url: url, resources: ["stream"])])
        XCTAssertEqual(list.importedTorrentios.count, 1)
        XCTAssertTrue(list.adoptImportedTorrentio())
        XCTAssertTrue(list.importedTorrentios.isEmpty)
        let mine = try XCTUnwrap(list.torrentio)
        XCTAssertEqual(mine.options?.sort, "seeders", "tu orden por compartidas se respeta")
        XCTAssertEqual(mine.options?.excludedQualities, ["brremux", "cam", "scr"], "y tu filtro de Remux")
        XCTAssertEqual(mine.options?.verbatim, ["extra=1"])
        let built = try XCTUnwrap(list.resolvedURL(mine))
        XCTAssertTrue(built.contains("realdebrid=\(token)") && !built.contains(old), "con tu clave de Cuentas, no la vieja")
        XCTAssertFalse(list.secretsToRedact().contains(old), "la dirección vieja ya no está en el llavero")
        let id = AddonList.newID(url)
        XCTAssertNil(vault.secret(AddonKeys.addonURL(id)))
        XCTAssertEqual(list.importOnce([.init(name: "Torrentio RD", url: url, resources: ["stream"])], again: true), 0, "«Volver a traer» no lo regresa")
    }

    func testTwoTorrentiosAskAndYouChoose() throws {
        let (list, _) = list()
        list.setOptions("torrentio", AddonOptions(languages: ["japanese"]))   // el de Orbital ya lo cambiaste
        let url = "https://torrentio.strem.fun/sort=seeders|realdebrid=\(old)/manifest.json"
        list.importOnce([.init(name: "Torrentio", url: url, resources: ["stream"])])
        XCTAssertFalse(list.adoptImportedTorrentio(), "el de Orbital ya no es el de fábrica: se pregunta")
        XCTAssertTrue(list.needsTorrentioChoice)
        XCTAssertTrue(list.keepTorrentio(from: nil))
        XCTAssertEqual(list.torrentio?.options?.languages, ["japanese"], "te quedaste con el de Orbital")
        XCTAssertFalse(list.needsTorrentioChoice)
        XCTAssertEqual(list.installed.filter { $0.resources.contains("stream") }.count, 2, "Torrentio y Comet, sin el traído")
    }

    func testWithoutAKeyInCuentasTheImportedOneStays() {
        let (list, _) = list(withKey: false)
        list.importOnce([.init(name: "Torrentio", url: "https://torrentio.strem.fun/realdebrid=\(old)/manifest.json", resources: ["stream"])])
        XCTAssertFalse(list.adoptImportedTorrentio(), "sin clave en Cuentas se perdería la de su dirección")
        XCTAssertFalse(list.needsTorrentioChoice)
        XCTAssertEqual(list.importedTorrentios.count, 1)
    }

    /// M4: la página de un complemento devolvió su nueva dirección; se guarda en el mismo y solo del mismo servidor.
    func testConfiguringAnAddonSavesTheSameAddon() throws {
        let (list, vault) = list()
        let id = list.add(url: "https://comet.example/OLD/manifest.json", name: "Comet", resources: ["stream"], origin: .imported)
        let before = list.installed.count
        XCTAssertTrue(list.replaceURL(id, with: "stremio://comet.example/NEW/manifest.json"))
        XCTAssertEqual(vault.secret(AddonKeys.addonURL(id)), "https://comet.example/NEW/manifest.json")
        XCTAssertEqual(list.installed.count, before, "nunca agrega otro")
        XCTAssertFalse(list.replaceURL(id, with: "https://otro.example/manifest.json"), "otro servidor no es el mismo complemento")
        XCTAssertFalse(list.replaceURL("torrentio", with: "https://torrentio.strem.fun/manifest.json"), "los de Orbital se arman solos")
    }
}

/// C2: igual que `addons.Health` de la TV.
final class AddonHealthTests: XCTestCase {
    final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_793_000_000) }

    func testTwoFailuresSkipItWithGrowingWaitUpToAnHourAndItComesBackAlone() {
        let clock = Clock(), vault = InMemoryAddonVault()
        let health = AddonHealth(vault: vault, clock: { clock.now })
        let url = "https://pirata.example/manifest.json"
        XCTAssertEqual(health.status(url), .unknown)
        health.fail(url)
        XCTAssertFalse(health.skip(url), "un fallo no basta")
        let since = clock.now
        clock.now += 10
        health.fail(url)
        XCTAssertTrue(health.skip(url))
        XCTAssertEqual(health.status(url), .down(since: since, skipped: true))
        clock.now += 61
        XCTAssertFalse(health.skip(url), "al minuto le toca otra vez")
        var waits: [TimeInterval] = []
        for _ in 0..<8 {
            health.fail(url)
            var wait: TimeInterval = 0
            while health.skip(url) { clock.now += 30; wait += 30 }
            waits.append(wait)
        }
        XCTAssertEqual(waits.prefix(3).map { ($0 / 60).rounded() }, [2, 4, 8], "la espera se duplica")
        XCTAssertEqual(waits.last.map { ($0 / 60).rounded() }, 60, "hasta una hora")
        health.ok(url, seconds: 0.62)
        XCTAssertFalse(health.skip(url), "contestó: regresa solo")
        XCTAssertEqual(health.status(url), .ok(seconds: 0.62))
        health.ok(url, seconds: 4.2)
        XCTAssertEqual(health.status(url), .slow(seconds: 4.2), "lento desde 3 s")
        XCTAssertEqual(AddonHealth(vault: vault, clock: { clock.now }).status(url), .slow(seconds: 4.2), "se recuerda al volver a abrir")
        let stored = String(data: vault.data("addon-health") ?? Data(), encoding: .utf8) ?? ""
        XCTAssertFalse(stored.contains("pirata"), "nunca la dirección: puede llevar tu clave")
    }

    func testWords() {
        XCTAssertEqual(AddonHealthWords.seconds(0.62), "0,6")
        XCTAssertEqual(AddonHealthWords.seconds(4.2, english: true), "4.2")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let saturday = Date(timeIntervalSince1970: 1_793_404_800)   // sábado 31 oct 2026, 00:00 UTC
        XCTAssertEqual(AddonHealthWords.since(saturday, now: saturday + 3 * 86_400, calendar: cal), "el sábado")
        XCTAssertEqual(AddonHealthWords.since(saturday, now: saturday + 3600, calendar: cal), "hoy")
        XCTAssertEqual(AddonHealthWords.since(saturday, now: saturday + 86_400 + 60, calendar: cal), "ayer")
    }
}
