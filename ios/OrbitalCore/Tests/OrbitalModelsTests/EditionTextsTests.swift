import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// D1-B: en Orbital (App Store) ningún texto que arman los modelos habla de Real-Debrid, Torrentio, los complementos ni de
/// controlar la consola, aunque haya una clave o una TV guardadas de antes. Recorre lo que la app puede decir en la ficha
/// («Ver» sin versiones, «Versión» vacía), la guía, Aprende, Ajustes y Siri.
@MainActor
final class EditionTextsTests: XCTestCase {
    static let banned = ["Real-Debrid", "Torrentio", "complemento", "Complemento", "consola", "Consola", "controla la TV", "Conectar tu TV", "Ver en la TV"]

    private func rig(_ edition: Edition) throws -> ServicesRig {
        let rig = try ServicesRig(edition: edition)
        rig.secrets.set(SecretKey.orbitalToken, "secreto")
        rig.services.settings.update { $0.orbitalEnabled = true; $0.orbitalAddress = "tv.example" }
        return rig
    }

    private func texts(of cause: UnavailableCause) -> [String] {
        var out = [cause.title(), cause.detail() ?? ""]
        if let action = cause.action { out.append(UnavailableCause.label(action)) }
        return out
    }

    /// Todo lo que la app puede decir con esta versión, sin tu clave de Real-Debrid y con ella guardada de antes.
    private func everything(_ edition: Edition) async throws -> [String: [String]] {
        var said: [String: [String]] = [:]
        for withKey in [false, true] {
            let rig = try rig(edition)
            if withKey { rig.secrets.set(AddonKeys.realDebridToken, "RDKEY") }
            let services = rig.services
            let title = TitleModel(services, kind: "movie", metaID: "tt0816692")
            title.sourceCheck = .none
            if let why = await title.cause(videoID: "tt0816692", language: "es-419", offer: nil) { said["ficha.causa", default: []] += texts(of: why) }
            var fallbacks = [title.playFallback()]
            title.sourceCheck = .offline
            fallbacks.append(title.playFallback(online: true))
            for fallback in fallbacks {
                switch fallback {
                case .cause(let cause): said["ficha.ver", default: []] += texts(of: cause)
                case .story(let id): said["ficha.historia", default: []] += LearnContent.all.filter { $0.id == id }.flatMap(Self.texts)
                case .noInternet: break
                }
            }
            for thrown in [nil, StreamFinderError.unreachable] as [Error?] {
                for online in [true, false] {
                    let empty = SourcesModel.emptyCause(thrown: thrown, online: online, account: .unknown, hasToken: withKey, addonsOff: true,
                                                        notices: [], canRequest: true, language: "es-419", instant: services.capabilities.instantStreams)
                    said["versión", default: []] += texts(of: empty)
                }
            }
            said["aprende", default: []] += LearnModel(services).stories.flatMap(Self.texts)
            said["siri", default: []].append(Capabilities.noTVLine(edition: edition))
        }
        return said
    }

    static func texts(_ story: LearnStory) -> [String] {
        [story.title] + story.cards.flatMap { [$0.title, $0.line] } + [story.action?.title].compactMap { $0 }
    }

    func testOrbitalSaysNothingAboutRealDebridAddonsOrTheConsole() async throws {
        let said = try await everything(.orbital)
        XCTAssertFalse(said.isEmpty)
        for (place, lines) in said {
            for line in lines where !line.isEmpty {
                for word in Self.banned { XCTAssertFalse(line.contains(word), "«\(line)» (\(place)) dice «\(word)» en Orbital") }
            }
        }
    }

    /// La prueba de arriba de verdad mira: en Ultra los mismos lugares sí hablan de Real-Debrid (y Siri, de la Mac).
    func testUltraStillTalksAboutRealDebrid() async throws {
        let all = try await everything(.ultra).values.flatMap { $0 }
        XCTAssertTrue(all.contains { $0.contains("Real-Debrid") })
        XCTAssertTrue(all.contains { $0.contains("complementos") })
        XCTAssertEqual(Capabilities.noTVLine(edition: .ultra), "En la Mac, Orbital no controla la TV. Usa tu iPhone o tu iPad.")
        XCTAssertFalse(Capabilities.noTVLine(edition: .plus).contains("Mac"), "Plus no tiene consola en ningún aparato: no se culpa a la Mac")
    }

    /// «Ver» sin versiones en Orbital: no abre la historia de Real-Debrid ni pide conectarlo; sin red, no culpa a los complementos.
    func testPlayWithoutVersionsInOrbital() throws {
        let rig = try rig(.orbital)
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        title.sourceCheck = .none
        XCTAssertEqual(title.playFallback(), .cause(.nobodyHasIt))
        title.sourceCheck = .offline
        XCTAssertNotEqual(title.playFallback(online: true), .cause(.addonsOffline))
        let ultra = TitleModel(try self.rig(.ultra).services, kind: "movie", metaID: "tt0816692")
        ultra.sourceCheck = .none
        XCTAssertEqual(ultra.playFallback(), .story(LearnContent.instant.id), "Ultra sin clave: la historia de Real-Debrid, como siempre")
        ultra.sourceCheck = .offline
        XCTAssertEqual(ultra.playFallback(online: true), .cause(.addonsOffline))
    }

    /// Los enlaces de fuera: el QR de la TV y el control del Centro de control solo abren donde hay consola; los de los
    /// widgets de siempre (la ficha, Descargas) en todas.
    func testOutsideLinksFollowTheEdition() {
        let orbital = Capabilities(edition: .orbital), ultra = Capabilities.ultra
        XCTAssertFalse(orbital.opens(nil, pairing: true), "el QR de la TV no «conecta» nada en Orbital")
        XCTAssertFalse(orbital.opens(.remote))
        XCTAssertFalse(Capabilities(edition: .ultra, talksToOrbital: false).opens(.remote), "la Mac tampoco")
        XCTAssertTrue(orbital.opens(.title(kind: "movie", id: "tt0816692")))
        XCTAssertTrue(orbital.opens(.downloads))
        XCTAssertTrue(ultra.opens(nil, pairing: true)); XCTAssertTrue(ultra.opens(.remote))
    }
}
