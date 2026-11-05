import XCTest
@testable import OrbitalCore

/// Tu Orbital de mentiras con la regla de `/api/companion/resume` (tests/test_resume_choice.py la prueba del lado de la TV):
/// por título, gana lo de la hora más reciente.
final class FakeResumeOrbital: HTTPClient, @unchecked Sendable {
    let lock = NSLock()
    var saved: [String: JSON] = [:]

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body = JSON.parse(request.body ?? Data())
        return lock.withLock {
            for (id, c) in body?["changes"]?.object ?? [:] where (c["at"]?.doubleValue ?? 0) > (saved[id]?["at"]?.doubleValue ?? 0) { saved[id] = c }
            var out: [String: JSON] = [:]
            for id in body?["want"]?.array?.compactMap(\.string) ?? [] { if let v = saved[id] { out[id] = v } }
            return HTTPResponse(status: 200, data: JSON.object(["resume": .object(out)]).serialized())
        }
    }
}

final class ResumeSyncTests: XCTestCase {
    func device(_ tv: FakeResumeOrbital) -> TitlePreferences {
        let prefs = TitlePreferences(InMemoryKeyValueStore()), remote = OrbitalRemote(http: tv, address: "tv.example", token: "x")
        prefs.exchangeResume = { changes, want in try? await remote.syncResume(changes, want: want) }
        return prefs
    }

    func testContinuarSigueConLoDelUltimoAparatoDondeLoViste() async {
        let tv = FakeResumeOrbital(), phone = device(tv), mac = device(tv)
        let latino = ResumeChoice.Track(language: "spa", title: "Latino"), inglés = ResumeChoice.Track(language: "eng", title: "English")
        mac.remember(metaID: "tt1", choice: ResumeChoice(videoID: "tt1", source: "A", audio: inglés, subtitle: .init(off: true)),
                     now: Date(timeIntervalSince1970: 1000))
        phone.remember(metaID: "tt1", choice: ResumeChoice(videoID: "tt1", source: "B", audio: latino, subtitle: .init(language: "eng", title: "Forced")),
                       now: Date(timeIntervalSince1970: 2000))
        await mac.syncResume()
        await phone.syncResume()
        await mac.syncResume(want: ["tt1"])   // «Continuar» en la Mac: lo del iPhone, que es más reciente
        let got = mac.resumeChoice(metaID: "tt1", videoID: "tt1")
        XCTAssertEqual(got?.source, "B")
        XCTAssertEqual(got?.audio, latino)
        XCTAssertEqual(got?.subtitle?.language, "eng")
        await phone.syncResume(want: ["tt1"])   // el iPhone ya lo tenía: no cambia
        XCTAssertEqual(phone.resumeChoice(metaID: "tt1", videoID: "tt1")?.source, "B")
    }

    func testSinTuOrbitalSeSigueConLoDeAqui() async {
        let prefs = TitlePreferences(InMemoryKeyValueStore())
        prefs.exchangeResume = { _, _ in try? await Task.sleep(for: .seconds(5)); return nil }
        prefs.remember(metaID: "tt1", choice: ResumeChoice(videoID: "tt1", source: "A"))
        let started = Date()
        await prefs.syncResume(want: ["tt1"], timeout: 0.2)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertEqual(prefs.resumeChoice(metaID: "tt1", videoID: "tt1")?.source, "A")
    }
}
