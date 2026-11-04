import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Aprende Orbital» (G3) y los avisos sobre la pantalla (F3), sin interfaz.
@MainActor
final class LearnModelTests: XCTestCase {
    override func setUp() { LearnModel.coachShownThisLaunch = false }

    func done(_ rig: ServicesRig) { OnboardingModel(rig.services).finish(); LearnModel.coachShownThisLaunch = false }

    func testRingsPutWhatYouLackFirstAndStopAtFour() throws {
        let rig = try ServicesRig(signedIn: false)
        done(rig)
        let learn = LearnModel(rig.services)
        let rings = learn.rings()
        XCTAssertEqual(rings.count, LearnModel.ringLimit)
        XCTAssertEqual(rings.first?.id, "pay", "sin Real-Debrid, primero cómo pagarlo")
        learn.markSeen("pay")
        XCTAssertFalse(learn.rings().contains { $0.id == "pay" }, "lo visto se va")
    }

    func testRingsLeaveInicioAfterTwoWeeksExceptWhenRealDebridExpired() throws {
        let rig = try ServicesRig(signedIn: false)
        done(rig)
        let learn = LearnModel(rig.services)
        XCTAssertFalse(learn.rings().isEmpty)
        rig.clock.now = rig.clock.now.addingTimeInterval(15 * 86400)
        XCTAssertTrue(learn.rings().isEmpty, "a los 14 días viven solo en Ajustes")
        learn.markSeen("pay")
        XCTAssertEqual(learn.rings(debridExpired: true).map(\.id), ["pay"], "si venció, «Cómo pagar» vuelve sola")
    }

    func testNoRingsOrCoachWhileTheGuideIsPending() throws {
        let rig = try ServicesRig(signedIn: false)
        let learn = LearnModel(rig.services)
        XCTAssertTrue(learn.rings().isEmpty)
        XCTAssertFalse(learn.shouldCoach(LearnModel.CoachID.titlePlay.rawValue))
    }

    func testOneCoachPerLaunchNeverTheSameDayAsTheGuideAndSkipAll() throws {
        let rig = try ServicesRig(signedIn: false)
        OnboardingModel(rig.services).finish()
        let learn = LearnModel(rig.services)
        XCTAssertFalse(learn.shouldCoach("title-play"), "no el mismo día de la guía")
        LearnModel.coachShownThisLaunch = false   // abres la app otra vez
        XCTAssertTrue(learn.shouldCoach("title-play"))
        XCTAssertFalse(learn.shouldCoach("title-play", used: true), "si ya lo usaste, no")
        learn.coached("title-play")
        XCTAssertFalse(learn.shouldCoach("advanced-search"), "uno por vez que abres la app")
        LearnModel.coachShownThisLaunch = false
        XCTAssertFalse(learn.shouldCoach("title-play"), "no se repite")
        XCTAssertTrue(learn.shouldCoach("advanced-search"))
        learn.skipAllCoach()
        XCTAssertFalse(learn.shouldCoach("advanced-search"), "«Saltar avisos»")
        learn.reset()
        XCTAssertTrue(learn.shouldCoach("title-play"), "«Volver a ver los avisos»")
    }

    func testSomeoneWhoAlreadyUsedTheAppSeesRingsButNoCoach() throws {
        let rig = try ServicesRig(signedIn: false, traktLinked: true, traktClientID: "CID")
        let learn = LearnModel(rig.services)
        XCTAssertFalse(learn.rings().isEmpty, "los círculos sí")
        XCTAssertFalse(learn.shouldCoach("title-play"), "los avisos no, hasta que haga la guía")
    }

    func testTheTVStoryOnlyWhereThereIsTV() throws {
        XCTAssertFalse(LearnModel(try ServicesRig(allowsOrbital: false).services).stories.contains { $0.id == "tv" })
        XCTAssertTrue(LearnModel(try ServicesRig().services).stories.contains { $0.id == "tv" })
    }

    func testEveryStoryHasThreeToFiveCards() {
        for story in LearnContent.all {
            XCTAssertTrue((2...5).contains(story.cards.count), story.id)
            XCTAssertEqual(story.cards.first?.template, .cover, "\(story.id) empieza con su portada")
        }
        XCTAssertEqual(Set(LearnContent.all.map(\.id)).count, LearnContent.all.count)
    }
}
