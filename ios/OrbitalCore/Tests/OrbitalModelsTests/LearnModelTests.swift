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
        XCTAssertEqual(rings.first?.id, "instant", "sin Real-Debrid, primero ver al instante")
        learn.markSeen("instant")
        XCTAssertFalse(learn.rings().contains { $0.id == "instant" }, "lo visto se va")
    }

    func testRingsLeaveInicioAfterTwoWeeksExceptWhenRealDebridExpired() throws {
        let rig = try ServicesRig(signedIn: false)
        done(rig)
        let learn = LearnModel(rig.services)
        XCTAssertFalse(learn.rings().isEmpty)
        rig.clock.now = rig.clock.now.addingTimeInterval(15 * 86400)
        XCTAssertTrue(learn.rings().isEmpty, "a los 14 días viven solo en Ajustes")
        learn.markSeen("instant")
        XCTAssertEqual(learn.rings(debridExpired: true).map(\.id), ["instant"], "si venció, «Ver al instante» vuelve sola")
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

    /// Las lecciones de Aprende (AF4-B, 19 nov 2026): las cinco en su orden; la de la TV solo con la consola.
    func testTheLessonsAndWhereEachOldStoryLands() throws {
        XCTAssertEqual(LearnModel(try ServicesRig().services).lessons, ["nube", "idioma", "hoy", "tuyo", "tv"])
        XCTAssertFalse(LearnModel(try ServicesRig(allowsOrbital: false).services).lessons.contains("tv"))
        XCTAssertEqual(LearnModel.lesson(forStory: "instant")?.id, "nube")
        XCTAssertEqual(LearnModel.lesson(forStory: "language")?.id, "idioma")
        XCTAssertEqual(LearnModel.lesson(forStory: "discover")?.id, "hoy")
        XCTAssertEqual(LearnModel.lesson(forStory: "thread")?.id, "tuyo")
        XCTAssertNil(LearnModel.lesson(forStory: "watch"), "los gestos del reproductor se enseñan con su aviso")
    }

    func testResetAlsoForgetsTheLessons() throws {
        let learn = LearnModel(try ServicesRig().services)
        learn.markSeen("lesson.hoy")
        XCTAssertTrue(learn.seen("lesson.hoy"))
        learn.reset()
        XCTAssertFalse(learn.seen("lesson.hoy"))
    }

    func testEveryStoryHasThreeToFiveCards() {
        for story in LearnContent.all {
            XCTAssertTrue((4...6).contains(story.cards.count), story.id)
            XCTAssertEqual(story.cards.filter { $0.mark == .trick }.count, 1, "\(story.id): un truco")
            XCTAssertEqual(Set(story.cards.map(\.seconds)).count > 1, true, "\(story.id): el ritmo cambia")
        }
        XCTAssertEqual(Set(LearnContent.all.map(\.id)).count, LearnContent.all.count)
    }
}
