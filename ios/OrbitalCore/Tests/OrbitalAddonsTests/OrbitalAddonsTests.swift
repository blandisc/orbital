import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OrbitalAddons

/// Corte B de «Desacoplar Stremio»: tus complementos y tu Real-Debrid viven en el teléfono.
final class AddonListTests: XCTestCase {
    let token = String(repeating: "A1B2", count: 13)   // 52 letras y números, como una clave de Real-Debrid

    func testTheTemplateCarriesYourKeyAndTheKeyIsHiddenInLogs() throws {
        let url = try XCTUnwrap(AddonCatalog.torrentio.manifestURL(token: token))
        XCTAssertEqual(url, "https://torrentio.strem.fun/qualityfilter=cam,scr,unknown|language=latino,spanish|realdebrid=\(token)/manifest.json")
        XCTAssertNil(AddonCatalog.torrentio.manifestURL(token: nil), "sin clave no se arma")
        XCTAssertNotNil(AddonCatalog.openSubtitles.manifestURL(token: nil), "el que no usa Real-Debrid no la pide")
        let log = "No contestó \(url)"
        XCTAssertFalse(AddonRedaction.redact(log, secrets: [token]).contains(token))
        XCTAssertTrue(AddonRedaction.redact(log, secrets: [token]).contains("realdebrid=\(AddonRedaction.mask)"))
        let custom = AddonOptions(excludedQualities: [], languages: ["Spanish!"])
        XCTAssertEqual(AddonCatalog.torrentio.manifestURL(token: token, options: custom),
                       "https://torrentio.strem.fun/language=spanish|realdebrid=\(token)/manifest.json", "las opciones van limpias")
    }

    /// Comet lleva su configuración (con tu clave) como JSON en base64 en la ruta, como la arma su página; sin «/» ni «+»
    /// que rompan la ruta, y la clave se tapa en los textos aunque vaya en base64.
    func testCometCarriesYourKeyInsideItsBase64ConfigAndItIsHiddenInLogs() throws {
        let url = try XCTUnwrap(AddonCatalog.comet.manifestURL(token: token))
        XCTAssertTrue(url.hasPrefix("https://comet.elfhosted.com/") && url.hasSuffix("/manifest.json"))
        let segment = String(url.dropFirst("https://comet.elfhosted.com/".count).dropLast("/manifest.json".count))
        XCTAssertFalse(segment.contains("/") || segment.contains("+"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(Data(base64Encoded: segment))) as? [String: Any])
        let services = try XCTUnwrap(config["debridServices"] as? [[String: String]])
        XCTAssertEqual(services, [["service": "realdebrid", "apiKey": token]])
        XCTAssertEqual(config["cachedOnly"] as? Bool, true)
        XCTAssertNil(AddonCatalog.comet.manifestURL(token: nil), "sin clave no se arma")
        XCTAssertFalse(AddonCatalog.comet.onByDefault, "apagado hasta probarlo con una cuenta real")
        XCTAssertFalse(AddonRedaction.redact("No contestó \(url)", secrets: [token]).contains(segment))
        XCTAssertEqual(AddonCatalog.recommended.map(\.id), ["torrentio", "comet", "opensubtitles"])
    }

    /// D2: la clave de un Torrentio importado (no la tuya del llavero) también se tapa en los errores.
    func testTheKeyInsideAnImportedAddonIsHiddenToo() {
        let vault = InMemoryAddonVault()
        let list = AddonList(vault: vault)
        let imported = "ZZ88YY77XX66WW55VV44UU33TT22SS11RR00QQ99PP88OO77NN66"
        list.importOnce([AddonList.Imported(name: "Torrentio", url: "https://torrentio.strem.fun/sort=seeders|realdebrid=\(imported)/manifest.json", resources: ["stream"])])
        XCTAssertEqual(list.secretsToRedact(), [imported])
        let message = "No contestó https://torrentio.strem.fun/sort=seeders|realdebrid=\(imported)/stream/movie/tt1.json"
        XCTAssertFalse(AddonRedaction.redact(message, secrets: list.secretsToRedact()).contains(imported))
        XCTAssertFalse(AddonRedaction.redact(message, secrets: []).contains(imported), "aunque no se sepa cuál es")
        XCTAssertTrue(AddonSecrets.mayCarrySecret("https://torrentio.strem.fun/realdebrid=\(imported)/manifest.json"))
        XCTAssertFalse(AddonSecrets.mayCarrySecret("https://opensubtitles-v3.strem.io/manifest.json"))
    }

    func testOrderAndOffAreRespected() {
        let vault = InMemoryAddonVault()
        vault.setSecret(AddonKeys.realDebridToken, token)
        let list = AddonList(vault: vault)
        XCTAssertFalse(list.isConfigured)
        list.startWithRecommended([AddonCatalog.torrentio, AddonCatalog.openSubtitles])   // un pegado se llama como Comet
        XCTAssertTrue(list.isConfigured)
        let comet = list.add(url: "https://comet.example/abc/manifest.json", name: "Comet", resources: ["stream"])
        XCTAssertEqual(list.installed.map(\.name), ["Torrentio", "OpenSubtitles", "Comet"])
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(list.installed.map(\.name), ["Comet", "Torrentio", "OpenSubtitles"], "Comet se pregunta primero")
        list.setEnabled(list.installed[1].id, false)
        XCTAssertEqual(list.enabledURLs(), ["https://comet.example/abc/manifest.json", "https://opensubtitles-v3.strem.io/manifest.json"], "apagado no se pregunta")
        XCTAssertEqual(AddonList(vault: vault).installed.map(\.name), ["Comet", "Torrentio", "OpenSubtitles"], "se guarda")
        XCTAssertNil(String(data: vault.data("addons-installed") ?? Data(), encoding: .utf8)?.range(of: "comet.example"), "la URL va al llavero, no a los ajustes")
        list.remove(comet)
        XCTAssertNil(vault.secret(AddonKeys.addonURL(comet)))
        XCTAssertEqual(list.installed.count, 2)
    }

    func testChangingTheKeyRegeneratesTheRecommended() {
        let vault = InMemoryAddonVault()
        vault.setSecret(AddonKeys.realDebridToken, token)
        let list = AddonList(vault: vault)
        list.startWithRecommended()
        let before = list.fingerprint()
        let other = String(repeating: "Z9", count: 26)
        vault.setSecret(AddonKeys.realDebridToken, other)
        XCTAssertTrue(list.enabledURLs()[0].contains("realdebrid=\(other)"))
        XCTAssertNotEqual(list.fingerprint(), before, "la caché de manifiestos sabe que cambió")
        vault.setSecret(AddonKeys.realDebridToken, nil)
        XCTAssertEqual(list.enabledURLs(), ["https://opensubtitles-v3.strem.io/manifest.json"], "sin clave, Torrentio se salta")
    }

    func testImportFromStremioOnlyOnce() {
        let list = AddonList(vault: InMemoryAddonVault())
        let fromStremio = [AddonList.Imported(name: "Torrentio", url: "https://torrentio.strem.fun/realdebrid=OLD/manifest.json", resources: ["stream"]),
                           AddonList.Imported(name: "Torrentio", url: "https://torrentio.strem.fun/realdebrid=OLD/manifest.json", resources: ["stream"]),
                           AddonList.Imported(name: "Listas", url: "https://listas.example/manifest.json", resources: ["catalog"])]
        XCTAssertEqual(list.importOnce(fromStremio), 2, "sin repetir")
        XCTAssertTrue(list.isConfigured)
        XCTAssertEqual(list.installed.map(\.origin), [.imported, .imported])
        XCTAssertEqual(list.installed.map(\.usesDebrid), [true, false], "la de Torrentio trae tu clave")
        XCTAssertEqual(list.importOnce(fromStremio + [AddonList.Imported(name: "Otro", url: "https://otro.example/manifest.json", resources: [])]), 0, "una sola vez")
        XCTAssertEqual(list.importOnce([AddonList.Imported(name: "Otro", url: "https://otro.example/manifest.json", resources: [])], again: true), 1)
    }
}

/// T10: tus complementos nunca se borran en silencio por un cambio de formato.
final class AddonStorageTests: XCTestCase {
    /// Lo que guardaba la app hasta noviembre de 2026: el arreglo solo, con el origen como lo codificaba Swift.
    let today = #"[{"id":"torrentio","name":"Torrentio","resources":["stream"],"enabled":true,"origin":{"recommended":{"_0":"torrentio"}},"usesDebrid":true},"#
        + #"{"id":"a1x","name":"Listas","resources":["catalog"],"enabled":false,"origin":{"imported":{}},"usesDebrid":false},"#
        + #"{"id":"a2y","name":"Pegado","resources":["stream"],"enabled":true,"origin":{"pasted":{}},"usesDebrid":false}]"#

    func testTodaysSavedListIsReadBackedUpAndItsDefaultsWritten() throws {
        let vault = InMemoryAddonVault()
        vault.setData("addons-installed", Data(today.utf8))
        let list = AddonList(vault: vault)
        XCTAssertTrue(list.isConfigured)
        XCTAssertEqual(list.installed.map(\.origin), [.recommended("torrentio"), .imported, .pasted])
        XCTAssertEqual(list.installed.map(\.enabled), [true, false, true])
        XCTAssertEqual(vault.data("addons-installed.backup-v1"), Data(today.utf8), "antes de migrar, una copia tal cual")
        XCTAssertEqual(list.installed[0].options, AddonOptions(), "las opciones de hoy quedan escritas")
        let saved = try XCTUnwrap(String(data: XCTUnwrap(vault.data("addons-installed")), encoding: .utf8))
        XCTAssertTrue(saved.contains(#""version":2"#))
        XCTAssertTrue(saved.contains(#""qualityfilter""#) == false && saved.contains("unknown"), "los valores, no «los de la app»")
        // Leído otra vez (ya en el formato nuevo): lo mismo, y la copia no se toca.
        let again = AddonList(vault: vault)
        XCTAssertEqual(again.installed, list.installed)
        XCTAssertEqual(vault.data("addons-installed.backup-v1"), Data(today.utf8))
    }

    func testUnknownKeysAndEntriesSurviveAndMissingKeysTakeTheirDefault() throws {
        let vault = InMemoryAddonVault()
        let newer = #"{"version":3,"items":[{"id":"torrentio","origin":{"kind":"recommended","template":"torrentio"},"syncRevision":7,"#
            + #""options":{"languages":["latino"],"sort":"seeders"}},{"id":"x","origin":{"kind":"satellite"}}]}"#
        vault.setData("addons-installed", Data(newer.utf8))
        let list = AddonList(vault: vault)
        let torrentio = try XCTUnwrap(list.installed.first)
        XCTAssertEqual(list.installed.count, 1)
        XCTAssertEqual(torrentio.name, "torrentio", "sin nombre: el id")
        XCTAssertTrue(torrentio.enabled, "sin «enabled»: prendido")
        XCTAssertEqual(torrentio.options?.languages, ["latino"])
        XCTAssertEqual(torrentio.options?.excludedQualities, AddonOptions.defaultExcludedQualities)
        XCTAssertEqual(torrentio.options?.extra["sort"], .string("seeders"))
        XCTAssertEqual(torrentio.extra["syncRevision"], .number(7))
        list.setEnabled("torrentio", false)
        let saved = try XCTUnwrap(String(data: XCTUnwrap(vault.data("addons-installed")), encoding: .utf8))
        XCTAssertTrue(saved.contains("syncRevision") && saved.contains("seeders") && saved.contains("satellite"), "lo que no se entiende se vuelve a escribir")
        XCTAssertNil(vault.data("addons-installed.backup-v1"), "no era una migración")
    }

    func testAListThatCannotBeReadIsNeverOverwritten() {
        let vault = InMemoryAddonVault()
        let garbage = Data("{esto no es json".utf8)
        vault.setData("addons-installed", garbage)
        let list = AddonList(vault: vault)
        XCTAssertTrue(list.readFailed)
        XCTAssertFalse(list.isConfigured, "la app sigue con Stremio")
        list.startWithRecommended()
        list.setEnabled("torrentio", false)
        XCTAssertEqual(vault.data("addons-installed"), garbage, "no se escribe encima")
        XCTAssertEqual(vault.data("addons-installed.unreadable"), garbage, "y queda una copia aparte")
    }

    func testANewListWritesItsOptions() throws {
        let vault = InMemoryAddonVault()
        let list = AddonList(vault: vault)
        list.startWithRecommended()
        XCTAssertEqual(list.installed.first { $0.id == "torrentio" }?.options, AddonOptions())
        XCTAssertNil(list.installed.first { $0.id == "opensubtitles" }?.options, "OpenSubtitles no tiene opciones")
    }
}

final class RealDebridTests: XCTestCase {
    let token = String(repeating: "A1B2", count: 13)
    let now = Date(timeIntervalSince1970: 1_793_000_000)   // 2026-10-26, 07:33 UTC

    private func provider(_ status: Int, _ body: String, seen: (@Sendable (URLRequest) -> Void)? = nil) -> RealDebrid {
        RealDebrid(fetch: { request in seen?(request); return (status, Data(body.utf8)) }, clock: { [now] in now })
    }

    func testPremiumAccountWithDaysLeft() async throws {
        let box = RequestBox()
        let rd = provider(200, #"{"id":1,"username":"fernando","type":"premium","premium":12355200,"expiration":"2027-03-21T12:00:00.000Z"}"#) { box.request = $0 }
        let status = try await rd.status(token: " \(token)\n")
        XCTAssertEqual(box.request?.url?.absoluteString, "https://api.real-debrid.com/rest/1.0/user")
        XCTAssertEqual(box.request?.httpMethod ?? "GET", "GET", "solo lectura")
        XCTAssertEqual(box.request?.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertEqual(status.username, "fernando")
        XCTAssertTrue(status.isPremium)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(status.daysLeft(now: now, calendar: calendar), 146)
        XCTAssertEqual(status.state(now: now, calendar: calendar), .active(daysLeft: 146))
    }

    func testFreeExpiredAndInvalidAccounts() async throws {
        let free = try await provider(200, #"{"username":"x","type":"free","premium":0,"expiration":"2026-10-24T00:00:00.000Z"}"#).status(token: token)
        XCTAssertFalse(free.isPremium)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(free.state(now: now, calendar: calendar), .expired(daysAgo: 2), "venció hace 2 días")
        let never = try await provider(200, #"{"username":"x","type":"free","premium":0}"#).status(token: token)
        XCTAssertEqual(never.state(now: now), .free)
        do { _ = try await provider(401, #"{"error":"bad_token","error_code":8}"#).status(token: token); XCTFail() } catch { XCTAssertEqual(error as? DebridError, .invalidToken) }
        do { _ = try await provider(200, "{}").status(token: "ABC123"); XCTFail() } catch { XCTAssertEqual(error as? DebridError, .malformedToken, "incompleta: ni se pregunta") }
        do { _ = try await provider(503, "").status(token: token); XCTFail() } catch { XCTAssertEqual(error as? DebridError, .network("HTTP 503")) }
    }

    func testSoonAndTodayStates() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        func status(_ days: Double) -> DebridStatus { DebridStatus(service: "Real-Debrid", username: "x", isPremium: true, expires: now.addingTimeInterval(days * 86_400), checkedAt: now) }
        XCTAssertEqual(status(3).state(now: now, calendar: calendar), .expiringSoon(daysLeft: 3))
        XCTAssertEqual(status(14).state(now: now, calendar: calendar), .expiringSoon(daysLeft: 14))
        XCTAssertEqual(status(15).state(now: now, calendar: calendar), .active(daysLeft: 15))
    }

    func testTheAccountKeepsItsStatusADayAndFallsBackToTheSavedOne() async throws {
        let vault = InMemoryAddonVault(), calls = Counter()
        let clock = MutableClock(now)
        let rd = RealDebrid(fetch: { _ in calls.add(); return (200, Data(#"{"username":"fernando","type":"premium","premium":864000}"#.utf8)) }, clock: { clock.now })
        let account = DebridAccount(provider: rd, vault: vault, clock: { clock.now })
        let none = await account.status()
        XCTAssertNil(none, "sin clave no se pregunta nada")
        let checked = try await account.verify(token)
        XCTAssertEqual(calls.value, 1)
        XCTAssertNil(vault.secret(AddonKeys.realDebridToken), "comprobar no guarda")
        await account.save(token: token, status: checked)
        _ = await account.status()
        XCTAssertEqual(calls.value, 1, "el de hoy, guardado")
        clock.now = now.addingTimeInterval(DebridAccount.statusTTL + 1)
        _ = await account.status()
        XCTAssertEqual(calls.value, 2, "pasado un día se vuelve a preguntar")
        await account.remove()
        XCTAssertFalse(account.hasToken)
        XCTAssertNil(account.saved)
    }

    /// B-P1-1: el día que vence (21 nov, a las 15:00 UTC) a las 9:00 aún vence hoy; a las 23:00 ya venció, aunque
    /// Real-Debrid ya diga «free» (antes: «sin Premium» todo el día).
    func testTheExpiryDayIsExpiredOnceTheHourPasses() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let expires = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 15))!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9))!
        let night = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 23))!
        let premium = DebridStatus(service: "Real-Debrid", username: "x", isPremium: true, expires: expires, checkedAt: morning)
        XCTAssertEqual(premium.state(now: morning, calendar: calendar), .expiringSoon(daysLeft: 0))
        XCTAssertEqual(premium.state(now: night, calendar: calendar), .expired(daysAgo: 0), "lo guardado en la mañana ya venció en la noche")
        var free = premium; free.isPremium = false
        XCTAssertEqual(free.state(now: night, calendar: calendar), .expired(daysAgo: 0), "«free» con fecha pasada es «venció», no «sin Premium»")
        XCTAssertEqual(free.state(now: calendar.date(byAdding: .day, value: 2, to: night)!, calendar: calendar), .expired(daysAgo: 2))
    }

    /// B-P1-1: cuando falla al reproducir se le pregunta ya a Real-Debrid (no lo guardado de hace horas), una vez cada 5 min.
    func testTroubleAsksRealDebridRightAwayOncePerWindow() async {
        let vault = InMemoryAddonVault(), calls = Counter(), clock = MutableClock(now)
        let body = BodyBox(#"{"username":"fernando","type":"premium","premium":864000}"#)
        let rd = RealDebrid(fetch: { _ in calls.add(); return (body.status, Data(body.text.utf8)) }, clock: { clock.now })
        let account = DebridAccount(provider: rd, vault: vault, clock: { clock.now })
        let noKey = await account.refreshAfterTrouble()
        XCTAssertEqual(noKey, .noKey)
        await account.save(token: token, status: DebridStatus(service: "Real-Debrid", username: "fernando", isPremium: true, expires: nil, checkedAt: now))
        body.text = #"{"username":"fernando","type":"free","premium":0,"expiration":"2026-10-26T00:00:00.000Z"}"#
        let first = await account.refreshAfterTrouble()
        guard case .status(let fresh) = first else { return XCTFail("\(first)") }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(fresh.state(now: now, calendar: utc), .expired(daysAgo: 0))
        XCTAssertEqual(account.saved?.isPremium, false, "lo guardado se pone al día")
        _ = await account.refreshAfterTrouble()
        XCTAssertEqual(calls.value, 1, "dentro de 5 min: la misma respuesta")
        clock.now = now.addingTimeInterval(DebridAccount.troubleEvery + 1)
        body.status = 401
        let invalid = await account.refreshAfterTrouble()
        XCTAssertEqual(invalid, .invalidToken, "«Vuelve a conectar Real-Debrid»")
    }

    /// B-P1-2: sin clave en la app, se toma la de tu Torrentio importado (comprobada), se anota de dónde salió y, si la
    /// quitas, no vuelve sola.
    func testTheKeyIsTakenFromTheImportedTorrentio() async {
        let vault = InMemoryAddonVault(), seen = RequestBox()
        let rd = RealDebrid(fetch: { request in seen.request = request; return (200, Data(#"{"username":"fernando","type":"premium","premium":864000}"#.utf8)) }, clock: { [now] in now })
        let account = DebridAccount(provider: rd, vault: vault, clock: { [now] in now })
        let urls = ["https://listas.example/manifest.json", "https://torrentio.strem.fun/sort=seeders|qualityfilter=brremux,cam,scr|realdebrid=\(token)/manifest.json"]
        let took = await account.adoptKey(fromAddonURLs: urls)
        XCTAssertTrue(took)
        XCTAssertEqual(vault.secret(AddonKeys.realDebridToken), token)
        XCTAssertEqual(seen.request?.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)", "se comprobó antes de guardarla")
        XCTAssertTrue(account.keyCameFromImport)
        XCTAssertNotNil(account.saved)
        let again = await account.adoptKey(fromAddonURLs: urls)
        XCTAssertFalse(again, "ya hay clave")
        await account.remove()
        let afterRemoving = await account.adoptKey(fromAddonURLs: urls)
        XCTAssertFalse(afterRemoving, "la quitaste tú: no vuelve sola")
        await account.save(token: token, status: DebridStatus(service: "Real-Debrid", username: "x", isPremium: true, expires: nil, checkedAt: now))
        XCTAssertFalse(account.keyCameFromImport, "pegada por ti")
    }

    func testABadKeyInsideTheImportedTorrentioIsNotSaved() async {
        let vault = InMemoryAddonVault()
        let rd = RealDebrid(fetch: { _ in (401, Data()) }, clock: { [now] in now })
        let account = DebridAccount(provider: rd, vault: vault, clock: { [now] in now })
        let took = await account.adoptKey(fromAddonURLs: ["https://torrentio.strem.fun/realdebrid=\(token)/manifest.json"])
        XCTAssertFalse(took)
        XCTAssertNil(vault.secret(AddonKeys.realDebridToken))
    }

    func testRemindersAreScheduledOnceAt14And3DaysAndOnTheDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
        let expires = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15))!
        let status = DebridStatus(service: "Real-Debrid", username: "x", isPremium: true, expires: expires, checkedAt: now)
        let book = DebridReminderBook(vault: InMemoryAddonVault())
        let first = book.toSchedule(status, now: now, calendar: calendar)
        XCTAssertEqual(first.map(\.daysLeft), [14, 3, 0])
        XCTAssertEqual(first.map { calendar.component(.day, from: $0.fireAt) }, [6, 17, 20])
        XCTAssertTrue(first.allSatisfy { calendar.component(.hour, from: $0.fireAt) == DebridReminders.hour })
        XCTAssertTrue(book.toSchedule(status, now: now, calendar: calendar).isEmpty, "una sola vez")
        var renewed = status; renewed.expires = expires.addingTimeInterval(30 * 86_400)
        XCTAssertEqual(book.toSchedule(renewed, now: now, calendar: calendar).count, 3, "si renuevas, tocan los de la fecha nueva")
        let late = book.toSchedule(status, now: calendar.date(byAdding: .day, value: 20, to: now)!, calendar: calendar)
        XCTAssertTrue(late.allSatisfy { $0.daysLeft < 14 }, "los que ya pasaron no se programan")
        var free = status; free.isPremium = false
        XCTAssertTrue(DebridReminders.upcoming(free, now: now).isEmpty)
    }
}

final class RequestBox: @unchecked Sendable { var request: URLRequest? }
final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func add() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock(); private var _now: Date
    init(_ now: Date) { _now = now }
    var now: Date { get { lock.withLock { _now } } set { lock.withLock { _now = newValue } } }
}
final class BodyBox: @unchecked Sendable {
    private let lock = NSLock(); private var _text: String; private var _status = 200
    init(_ text: String) { _text = text }
    var text: String { get { lock.withLock { _text } } set { lock.withLock { _text = newValue } } }
    var status: Int { get { lock.withLock { _status } } set { lock.withLock { _status = newValue } } }
}
