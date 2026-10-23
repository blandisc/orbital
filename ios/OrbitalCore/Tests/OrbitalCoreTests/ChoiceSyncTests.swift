import XCTest
@testable import OrbitalCore

/// Tu Orbital de mentiras con las reglas de `state.apply_choice` / `choices_since` (tests/test_choices_sync.py las prueba
/// del lado de la TV): revisión por título, gana la TV si cambió después de lo que vio el iPhone.
final class FakeOrbital: HTTPClient, @unchecked Sendable {
    let lock = NSLock()
    var rev = 0
    var titles: [String: [String: String]] = [:]
    var revs: [String: Int] = [:]
    var calls = 0
    var offline = false

    func tvSets(_ id: String, _ key: String, _ value: String) { lock.withLock { rev += 1; titles[id, default: [:]][key] = value; revs[id] = rev } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if offline { throw URLError(.notConnectedToInternet) }
        let body = JSON.parse(request.body ?? Data())
        return lock.withLock {
            calls += 1
            var rejected: [JSON] = []
            for (id, c) in body?["changes"]?.object ?? [:] {
                if (revs[id] ?? 0) > (c["base_rev"]?.intValue ?? 0) { rejected.append(.string(id)); continue }
                var fields = titles[id] ?? [:]
                for k in ["audio", "spanish", "subtitles"] { if let v = c[k]?.string { fields[k] = v } }
                for k in c["forget"]?.array?.compactMap(\.string) ?? [] { fields[k] = nil }
                rev += 1; titles[id] = fields; revs[id] = rev
            }
            let since = body?["since"]?.intValue ?? 0
            var changed: [String: JSON] = [:]
            for (id, fields) in titles where (since == 0 && !fields.isEmpty) || (since > 0 && (revs[id] ?? 0) > since)
                || rejected.contains(.string(id)) {
                var o = fields.mapValues { JSON.string($0) }; o["rev"] = .int(revs[id] ?? 0); changed[id] = .object(o)
            }
            let reply = JSON.object(["rev": .int(rev), "changed": .object(changed), "rejected": .array(rejected)])
            return HTTPResponse(status: 200, data: reply.serialized())
        }
    }
}

final class ChoiceSyncTests: XCTestCase {
    func rig() -> (TitlePreferences, FakeOrbital, OrbitalRemote, InMemoryKeyValueStore) {
        let kv = InMemoryKeyValueStore(), tv = FakeOrbital()
        return (TitlePreferences(kv), tv, OrbitalRemote(http: tv, address: "tv.example", token: "x"), kv)
    }

    func testLaPrimeraVezSoloSumaYSiChocanGanaLaTV() async {
        let (prefs, tv, remote, _) = rig()
        prefs.remember(metaID: "tt0096697", audioTrack: "es-419")          // Los Simpson en latino, aquí
        prefs.remember(metaID: "tt0386676", subtitleTrack: "en")           // The Office con subtítulos en inglés, aquí
        tv.tvSets("tt0096697", "audio", "es"); tv.tvSets("tt0096697", "spanish", "es-ES")   // la TV lo tenía en castellano
        tv.tvSets("tt0903747", "audio", "en")                              // Breaking Bad solo en la TV
        await prefs.syncChoices(with: remote)
        let settings = AppSettings()
        XCTAssertEqual(prefs.languages(for: "tt0096697", settings: settings).prefs.spanish, "es-ES", "chocan: gana la TV")
        XCTAssertEqual(prefs.languages(for: "tt0903747", settings: settings).prefs.audio, "en", "lo de la TV llega")
        XCTAssertEqual(tv.titles["tt0386676"]?["subtitles"], "en", "lo del iPhone llega")
        XCTAssertTrue(prefs.pendingChoices.isEmpty)
    }

    func testLoQueEligesAquiLlegaALaTVYLoDeLaTVAqui() async {
        let (prefs, tv, remote, _) = rig()
        await prefs.syncChoices(with: remote)
        prefs.remember(metaID: "tt1", audioTrack: "es-ES")
        XCTAssertEqual(prefs.pendingChoices["tt1"]?.spanish, "es-ES")
        await prefs.syncChoices(with: remote)
        XCTAssertEqual(tv.titles["tt1"], ["audio": "es", "spanish": "es-ES"])
        tv.tvSets("tt1", "subtitles", "en")
        await prefs.syncChoices(with: remote)
        XCTAssertEqual(prefs.languages(for: "tt1", settings: AppSettings()).subtitles, "en")
    }

    func testSiLaTVCambioDespuesGanaLaTVYNadaQuedaColgado() async {
        let (prefs, tv, remote, _) = rig()
        prefs.remember(metaID: "tt1", audioTrack: "en")
        await prefs.syncChoices(with: remote)
        prefs.remember(metaID: "tt1", audioTrack: "es-419")    // aquí, sin que la TV se entere aún…
        tv.tvSets("tt1", "audio", "fr")                         // …y en la TV, otra cosa
        await prefs.syncChoices(with: remote)
        XCTAssertEqual(prefs.languages(for: "tt1", settings: AppSettings()).prefs.audio, "fr")
        XCTAssertTrue(prefs.pendingChoices.isEmpty)
    }

    func testSinConexionLoPendienteEsperaYSobreviveAlReinicio() async {
        let (prefs, tv, remote, kv) = rig()
        tv.offline = true
        prefs.remember(metaID: "tt1", subtitleTrack: "")
        await prefs.syncChoices(with: remote)
        let again = TitlePreferences(kv)
        XCTAssertEqual(again.pendingChoices["tt1"]?.subtitles, "", "sigue pendiente después de cerrar la app")
        tv.offline = false
        await again.syncChoices(with: remote)
        XCTAssertEqual(tv.titles["tt1"]?["subtitles"], "")
        XCTAssertTrue(again.pendingChoices.isEmpty)
    }

    func testOlvidarTambienLlega() async {
        let (prefs, tv, remote, _) = rig()
        prefs.remember(metaID: "tt1", audioTrack: "en")
        await prefs.syncChoices(with: remote)
        prefs.forget(metaID: "tt1")
        XCTAssertNil(prefs.remembered()["tt1"])
        await prefs.syncChoices(with: remote)
        XCTAssertEqual(tv.titles["tt1"], [:])
        tv.tvSets("tt2", "audio", "es"); await prefs.syncChoices(with: remote)
        XCTAssertNotNil(prefs.remembered()["tt2"])
    }
}
