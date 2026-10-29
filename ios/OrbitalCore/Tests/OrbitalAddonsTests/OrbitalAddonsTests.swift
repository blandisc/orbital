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
