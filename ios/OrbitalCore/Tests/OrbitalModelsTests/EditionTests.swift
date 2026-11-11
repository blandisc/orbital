import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// D1-B (revisión del 10 nov 2026): cada versión dice qué trae, y los modelos lo respetan. En Orbital (App Store) no queda a la
/// vista nada de Real-Debrid ni de la consola en Ajustes, la ficha, Biblioteca, la guía ni Aprende, aunque haya una clave o una
/// TV guardadas de antes. En Ultra (la de Fernando, la de siempre) todo sigue igual.
@MainActor
final class EditionTests: XCTestCase {
    func testTheBuildSettingPicksTheEditionAndUltraIsTheDefault() {
        XCTAssertEqual(Edition(parsing: nil), .ultra)
        XCTAssertEqual(Edition(parsing: ""), .ultra)
        XCTAssertEqual(Edition(parsing: "$(ORBITAL_EDITION)"), .ultra, "sin sustituir en el Info.plist: la de siempre")
        XCTAssertEqual(Edition(parsing: " Plus "), .plus)
        XCTAssertEqual(Edition(parsing: "orbital"), .orbital)
        XCTAssertEqual(Edition.bundled(Bundle(for: Self.self)), .ultra, "un paquete sin la clave es Ultra")
    }

    func testWhatEachEditionTurnsOnAndOff() {
        let ultra = Capabilities(edition: .ultra), plus = Capabilities(edition: .plus), orbital = Capabilities(edition: .orbital)
        XCTAssertEqual(ultra, Capabilities(console: true, instantStreams: true, downloads: true, emulation: true, personal: true))
        XCTAssertEqual(plus, Capabilities(console: false, instantStreams: true, downloads: true, emulation: false, personal: false))
        XCTAssertEqual(orbital, Capabilities(console: false, instantStreams: false, downloads: true, emulation: false, personal: false))
        XCTAssertFalse(Capabilities(edition: .ultra, talksToOrbital: false).console, "Ultra en la Mac: sin consola")
        XCTAssertTrue(Capabilities(edition: .ultra, talksToOrbital: false).instantStreams)
        XCTAssertEqual(Capabilities.ultra, ultra)
    }

    /// Una cuenta de Real-Debrid, un pedido en la libreta y una TV emparejada de antes: lo que un iPhone con Ultra tendría.
    private func rig(_ edition: Edition) throws -> ServicesRig {
        let rig = try ServicesRig(edition: edition)
        rig.secrets.set(AddonKeys.realDebridToken, "RDKEY")
        rig.secrets.set(SecretKey.orbitalToken, "secreto")
        rig.services.settings.update { $0.orbitalEnabled = true; $0.orbitalAddress = "tv.example" }
        rig.services.debridRequests.requester.book.put(DebridRequest(hash: String(repeating: "a", count: 40), title: "Interstellar", kind: "movie",
                                                                     metaID: "tt0816692", videoIDs: ["tt0816692"], device: "iPhone",
                                                                     createdAt: rig.clock.now, state: .downloading))
        rig.services.debridRequests.reload()
        return rig
    }

    func testOrbitalShowsNothingOfRealDebridNorTheConsole() throws {
        let services = try rig(.orbital).services
        XCTAssertEqual(services.settingsEntries, SettingsEntries(realDebrid: false, addons: false, orbital: false, simpsons: false), "Ajustes")
        XCTAssertFalse(services.showsCloudDownloads, "Biblioteca › Descargas: sin «Real-Debrid · bajando para ti»")
        XCTAssertFalse(services.debridRequests.canRequest, "la ficha no ofrece «Pedir a la nube»")
        let title = TitleModel(services, kind: "movie", metaID: "tt0816692")
        XCTAssertFalse(title.offersInstant, "la ficha sin pedidos ni nube")
        XCTAssertFalse(services.orbitalOn, "la TV guardada de antes no se usa")
        XCTAssertFalse(services.orbital.isConfigured)
        XCTAssertFalse(TVNowModel(services).isConfigured, "sin control ni «En la TV»")
        let guide = OnboardingModel(services)
        XCTAssertEqual(guide.pieces, [.trakt].filter { _ in guide.offersTrakt }, "«¿Qué ya tienes?» sin Real-Debrid ni la TV")
        guide.answer(.debrid, .has); guide.answer(.tv, .has)
        XCTAssertFalse(guide.plan.contains(.debrid)); XCTAssertFalse(guide.plan.contains(.tv))
        let stories = LearnModel(services).stories.map(\.id)
        XCTAssertFalse(stories.contains(LearnContent.instant.id), "Aprende sin «Ver al instante»")
        XCTAssertFalse(stories.contains(LearnContent.tv.id), "Aprende sin «Tu TV»")
    }

    func testPlusKeepsRealDebridButNotTheConsole() throws {
        let services = try rig(.plus).services
        XCTAssertEqual(services.settingsEntries, SettingsEntries(realDebrid: true, addons: true, orbital: false, simpsons: false))
        XCTAssertTrue(services.showsCloudDownloads)
        XCTAssertFalse(services.orbitalOn)
        XCTAssertTrue(TitleModel(services, kind: "movie", metaID: "tt0816692").offersInstant)
        XCTAssertFalse(OnboardingModel(services).pieces.contains(.tv))
    }

    func testUltraKeepsEverything() throws {
        let services = try rig(.ultra).services
        XCTAssertEqual(services.settingsEntries, SettingsEntries(realDebrid: true, addons: true, orbital: true, simpsons: true))
        XCTAssertTrue(services.showsCloudDownloads)
        XCTAssertTrue(services.debridRequests.canRequest, "con tu clave y Torrentio de fábrica se puede pedir")
        XCTAssertTrue(TitleModel(services, kind: "movie", metaID: "tt0816692").offersInstant)
        XCTAssertTrue(services.orbitalOn)
        XCTAssertTrue(services.orbital.isConfigured)
        let guide = OnboardingModel(services)
        XCTAssertTrue(guide.pieces.contains(.debrid)); XCTAssertTrue(guide.pieces.contains(.tv))
        let stories = LearnModel(services).stories.map(\.id)
        XCTAssertTrue(stories.contains(LearnContent.instant.id)); XCTAssertTrue(stories.contains(LearnContent.tv.id))
    }
}
