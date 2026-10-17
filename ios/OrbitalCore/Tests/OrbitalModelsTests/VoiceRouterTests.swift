import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// La voz del iPhone: qué atiende el teléfono y qué llega a la consola, contra el corpus compartido con la consola
/// (`tests/fixtures/voice/corpus.json`) y contra frases hechas para romperlo.
final class VoiceRouterTests: XCTestCase {
    func testEveryPhraseOfTheSharedCorpusGoesWhereItShould() throws {
        let corpus = try Fixtures.json("voice/corpus.json")
        let phrases = try XCTUnwrap(corpus["phrases"]?.array)
        XCTAssertGreaterThan(phrases.count, 100)
        for row in phrases {
            let text = try XCTUnwrap(row["text"]?.string)
            let route = VoiceRouter.route(text)
            switch row["phone"]?.string {
            case "download": XCTAssertEqual(route, .download(title: row["title"]?.string), text)
            case "continueHere": XCTAssertEqual(route, .continueHere, text)
            case "key":
                let key = try XCTUnwrap(row["key"]?.string)
                XCTAssertEqual(route, .key(try XCTUnwrap(OrbitalRemote.InputAction(rawValue: key))), text)
            case "console": XCTAssertEqual(route, .console(try XCTUnwrap(row["send"]?.string)), text)
            default:
                // Lo de la TV llega a la consola: sin el ruido del dictado, nunca vacío.
                guard case .console(let sent) = route else { return XCTFail("\(text) → \(route)") }
                XCTAssertFalse(sent.isEmpty, text)
                XCTAssertFalse(sent.lowercased().contains("por favor"), text)
                XCTAssertFalse(sent.lowercased().hasPrefix("orbital"), text)
            }
        }
    }

    func testDictationNoiseIsCleaned() {
        XCTAssertEqual(VoiceRouter.clean("Pon El Viaje De Chihiro, por favor."), "Pon El Viaje De Chihiro")
        XCTAssertEqual(VoiceRouter.clean("Orbital, pon Dune"), "pon Dune")
        XCTAssertEqual(VoiceRouter.clean("Oye Orbital pon Dune"), "pon Dune")
        XCTAssertEqual(VoiceRouter.clean("Por favor pon Dune."), "pon Dune")
        XCTAssertEqual(VoiceRouter.clean("¿Qué estoy viendo?"), "Qué estoy viendo")
        XCTAssertEqual(VoiceRouter.route("   "), .nothing)
        XCTAssertEqual(VoiceRouter.route("Por favor."), .nothing)
    }

    func testPhrasesThatLookLikePhoneOrKeysButAreForTheTV() {
        XCTAssertEqual(VoiceRouter.route("Baja el volumen"), .console("Baja el volumen"), "«baja» sin el teléfono es el volumen de la TV")
        XCTAssertEqual(VoiceRouter.route("Regresa 10 segundos"), .console("Regresa 10 segundos"), "con algo más ya no es la tecla Atrás")
        XCTAssertEqual(VoiceRouter.route("Sigue"), .console("Sigue"), "«sigue» a secas es quitar la pausa en la TV")
        XCTAssertEqual(VoiceRouter.route("Sigue viendo The Office"), .console("Sigue viendo The Office"))
        XCTAssertEqual(VoiceRouter.route("Pon Dune"), .console("Pon Dune"))
        XCTAssertEqual(VoiceRouter.route("Descarga la película de Dune"), .download(title: "dune"))
        XCTAssertEqual(VoiceRouter.route("Bájalo al teléfono"), .download(title: nil))
        XCTAssertEqual(VoiceRouter.route("Síguela en mi celular"), .continueHere)
    }

    func testBasicEnglishBecomesWhatTheConsoleUnderstands() {
        XCTAssertEqual(VoiceRouter.route("Play The Office"), .console("pon the office"))
        XCTAssertEqual(VoiceRouter.route("Pause."), .console("pausa"))
        XCTAssertEqual(VoiceRouter.route("What's playing?"), .console("que estoy viendo"))
        XCTAssertEqual(VoiceRouter.route("Subtitles in English"), .console("subtitulos en ingles"))
        XCTAssertEqual(VoiceRouter.route("Search for Dune"), .console("busca dune"))
    }
}

@MainActor
final class VoiceAssistantTests: XCTestCase {
    private func connected() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "tok")
        return rig
    }

    func testConsoleCommandsGoToVoiceAndKeysToInput() async throws {
        let rig = try connected()
        rig.http.json["https://tv.example/api/voice"] = ["ok": true, "speech": "Poniendo El viaje de Chihiro."]
        rig.http.json["https://tv.example/api/companion/input"] = ["ok": true]
        let assistant = VoiceAssistant(services: rig.services, tvNow: TVNowModel(rig.services))
        let played = await assistant.handle("Orbital, pon El viaje de Chihiro, por favor.")
        XCTAssertEqual(played, .init(ok: true, speech: "Poniendo El viaje de Chihiro."))
        XCTAssertEqual(rig.http.bodies("https://tv.example/api/voice").first.flatMap { JSON.parse($0)?["text"]?.string }, "pon El viaje de Chihiro",
                       "a la consola llega limpio")
        _ = await assistant.handle("Atrás")
        XCTAssertEqual(rig.http.bodies("https://tv.example/api/companion/input").first.flatMap { JSON.parse($0)?["action"]?.string }, "back")
    }

    func testPhoneOnlyCommandsWithNothingOnTheTVSaySo() async throws {
        let rig = try connected()
        let assistant = VoiceAssistant(services: rig.services, tvNow: TVNowModel(rig.services))
        let here = await assistant.handle("Ponlo aquí")
        XCTAssertFalse(here.ok); XCTAssertFalse(here.continueHere)
        let download = await assistant.handle("Descárgalo en el iPhone")
        XCTAssertEqual(download, .init(ok: false, speech: "No hay nada en la TV para descargar."))
    }

    func testAnUnreachableOrbitalIsSaidOutLoud() async throws {
        let rig = try connected()   // /api/voice no contesta (404 en el falso): la consola no está
        let assistant = VoiceAssistant(services: rig.services, tvNow: TVNowModel(rig.services))
        let outcome = await assistant.handle("pausa")
        XCTAssertFalse(outcome.ok)
        XCTAssertFalse(outcome.speech.isEmpty, "siempre se dice algo, nunca silencio")
    }
}
