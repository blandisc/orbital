import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El modo voz del iPhone: las frases sugeridas, por qué no se llega a tu Orbital y poner una serie desde su episodio.
@MainActor
final class VoiceModeTests: XCTestCase {
    private func connected() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example"; $0.orbitalEnabled = true }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        return rig
    }

    func testHintsComeFromTheConsole() async throws {
        let rig = try connected()
        rig.http.json["https://tv.example/api/voice/hints"] = ["moment": "live", "hints": ["pon el canal 2", "sube el volumen", "cierra el video", "otra"]]
        let model = TVNowModel(rig.services)
        await model.loadHints()
        XCTAssertEqual(model.momentHints, .live)
        XCTAssertEqual(model.hints, ["pon el canal 2", "sube el volumen", "cierra el video"])
    }

    /// Una consola vieja (404) o que no contesta: las fijas según lo que suena.
    func testWithoutTheRouteTheFixedHintsFollowWhatIsPlaying() async throws {
        let rig = try connected()
        let model = TVNowModel(rig.services)
        await model.loadHints()
        XCTAssertEqual(model.momentHints, .home)
        XCTAssertEqual(model.hints, ["pon The Office", "sigue viendo", "qué sale hoy"])
        let playing: JSON = .object(["kind": .string("series"), "live": .bool(false), "title": .string("The Office"),
                                     "position": .int(10), "duration": .int(100), "paused": .bool(false)])
        rig.http.json["https://tv.example/api/companion/now"] = .object(["playing": playing])
        await model.refreshNow()
        await model.loadHints()
        XCTAssertEqual(model.momentHints, .series)
        XCTAssertEqual(model.hints, ["pausa", "siguiente episodio", "pon subtítulos"])
    }

    func testFixedHintsPerMoment() {
        XCTAssertEqual(VoiceMoment.movie.fallbackHints, ["pausa", "pon subtítulos", "sube el volumen"])
        XCTAssertEqual(VoiceMoment.live.fallbackHints, ["pon el canal ADN 40", "sube el volumen", "cierra el video"])
        XCTAssertTrue(VoiceMoment.allCases.allSatisfy { $0.fallbackHints.count == 3 })
    }

    func testAVoiceReplyBringsTheHintsAndTheGuide() async throws {
        let rig = try connected()
        rig.http.json["https://tv.example/api/voice"] = ["ok": true, "speech": "Puedes decir…", "guide": true, "hints": ["pausa", "siguiente episodio"]]
        let tvNow = TVNowModel(rig.services)
        let outcome = await VoiceAssistant(services: rig.services, tvNow: tvNow).handle("qué puedo decir")
        XCTAssertTrue(outcome.guide)
        XCTAssertEqual(outcome.hints, ["pausa", "siguiente episodio"])
        XCTAssertTrue(outcome.reply.guide)
        XCTAssertEqual(tvNow.hints, ["pausa", "siguiente episodio"])
    }

    func testPickedTravelsToTheOutcome() async throws {
        let rig = try connected()
        let dune: JSON = ["id": "b", "title": "Dune", "kind": "movie", "meta_id": "tt1160419"]
        rig.http.json["https://tv.example/api/voice"] = ["ok": true, "speech": "Poniendo Dune.", "choices": .array([dune]), "picked": "tt1160419"]
        let outcome = await VoiceAssistant(services: rig.services, tvNow: TVNowModel(rig.services)).handle("pon Dune")
        XCTAssertEqual(outcome.picked, "tt1160419")
        XCTAssertEqual(outcome.reply.picked, "tt1160419")
    }

    func testDiagnoseConnection() async throws {
        let rig = try connected()
        let model = TVNowModel(rig.services)
        rig.http.json["https://tv.example/api/ping"] = ["ok": true, "service": "orbital"]
        let fine = await model.diagnoseConnection()
        XCTAssertNil(fine)
        rig.http.statuses["https://tv.example/api/ping"] = 503
        let down = await model.diagnoseConnection()
        XCTAssertEqual(down, .orbitalDown)
        rig.http.offline = true
        let offline = await model.diagnoseConnection()
        XCTAssertEqual(offline, .noInternet)
        let unconfigured = await TVNowModel(try ServicesRig().services).diagnoseConnection()
        XCTAssertNil(unconfigured)
    }

    func testEpisodesSkipSpecialsAndWhatHasNotAired() async throws {
        let rig = try connected()
        func video(_ s: Int, _ e: Int, _ released: String) -> JSON {
            ["id": .string("tt9:\(s):\(e)"), "season": .int(s), "episode": .int(e), "name": .string("E\(e)"), "released": .string(released)]
        }
        let past = "2020-01-01T00:00:00.000Z", future = "2099-01-01T00:00:00.000Z"
        rig.http.json["https://v3-cinemeta.strem.io/meta/series/tt9.json"] = ["meta": ["id": "tt9", "name": "Serie", "type": "series",
            "videos": .array([video(0, 1, past), video(1, 2, past), video(1, 1, past), video(2, 1, future), video(1, 3, future)])]]
        let seasons = await VoiceAssistant(services: rig.services, tvNow: TVNowModel(rig.services)).episodes(seriesID: "tt9")
        XCTAssertEqual(seasons.map(\.season), [1], "sin especiales ni una temporada que aún no sale")
        XCTAssertEqual(seasons.first?.episodes.map(\.id), ["tt9:1:1", "tt9:1:2"])
    }

    /// Tocar una serie entre las opciones la pone desde su primer episodio (antes solo abría su ficha en la TV).
    func testChoosingASeriesPlaysItsFirstEpisode() async throws {
        let rig = try connected()
        rig.http.json["https://tv.example/api/stremio/play"] = ["ok": true]
        let office = OrbitalRemote.VoiceChoice(id: "a", title: "The Office", subtitle: "Serie", kind: "series", metaID: "tt0386676")
        let outcome = await VoiceAssistant(services: rig.services, tvNow: TVNowModel(rig.services)).choose(office)
        XCTAssertEqual(outcome, .init(ok: true, speech: "Poniendo The Office · T1 E1.", heard: "The Office · T1 E1"))
        let body = rig.http.bodies("https://tv.example/api/stremio/play").first.flatMap { JSON.parse($0) }
        XCTAssertEqual(body?["kind"]?.string, "series")
        XCTAssertEqual(body?["id"]?.string, "tt0386676")
        XCTAssertEqual(body?["video_id"]?.string, "tt0386676:1:1")
        XCTAssertEqual(body?["title"]?.string, "The Office · T1 E1")
    }

    /// Sin Cinemeta, la serie abre su ficha en la TV como antes.
    func testChoosingASeriesWithoutCinemetaOpensItOnTheTV() async throws {
        let rig = try connected()
        rig.http.json["https://tv.example/api/stremio/play"] = ["ok": true]
        let show = OrbitalRemote.VoiceChoice(id: "a", title: "Otra", subtitle: "Serie", kind: "series", metaID: "tt404")
        let outcome = await VoiceAssistant(services: rig.services, tvNow: TVNowModel(rig.services)).choose(show)
        XCTAssertEqual(outcome.speech, "Abriendo Otra en la TV.")
        let body = rig.http.bodies("https://tv.example/api/stremio/play").first.flatMap { JSON.parse($0) }
        XCTAssertNil(body?["video_id"])
    }

    func testPlayEpisodeSaysWhichOne() async throws {
        let rig = try connected()
        rig.http.json["https://tv.example/api/stremio/play"] = ["ok": true]
        let episode = Episode(id: "tt0386676:2:5", episode: 5, title: "Halloween", thumbnail: nil, overview: "", released: nil, hasTitle: true)
        let outcome = await VoiceAssistant(services: rig.services, tvNow: TVNowModel(rig.services))
            .playEpisode(seriesID: "tt0386676", episode: episode, season: 2, title: "The Office")
        XCTAssertEqual(outcome.speech, "Poniendo The Office · T2 E5.")
        let body = rig.http.bodies("https://tv.example/api/stremio/play").first.flatMap { JSON.parse($0) }
        XCTAssertEqual(body?["video_id"]?.string, "tt0386676:2:5")
    }
}
