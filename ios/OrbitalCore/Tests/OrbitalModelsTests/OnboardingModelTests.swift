import XCTest
@testable import OrbitalCore
@testable import OrbitalModels
import OrbitalAddons

/// Corte C: la guía de la primera vez y Ajustes › Cuentas y Complementos (sin interfaz).
@MainActor
final class OnboardingModelTests: XCTestCase {
    let user = "https://api.real-debrid.com/rest/1.0/user"
    let token = String(repeating: "QX7MZ2K9PL", count: 5) + "AB"

    func testTheGuideShowsOnceAndNotToSomeoneWhoAlreadyUsesTheApp() throws {
        let rig = try ServicesRig(signedIn: false)
        XCTAssertTrue(OnboardingModel.shouldShow(rig.services))
        OnboardingModel(rig.services).finish()
        XCTAssertFalse(OnboardingModel.shouldShow(rig.services), "una sola vez; se reabre desde Ajustes")
        let trakt = try ServicesRig(signedIn: false, traktLinked: true, traktClientID: "CID")
        XCTAssertFalse(OnboardingModel.shouldShow(trakt.services), "quien ya usaba la app (Trakt conectado) no la ve")
    }

    /// C1 y Q1: lo que no tienes no se marca. Real-Debrid se explica siempre que no esté conectado; Trakt y la TV, solo si
    /// los marcas; con los dos, una sola pantalla de «tus aparatos» (Q3). Nada detiene la guía.
    func testTheAnswersShapeThePlanAndNothingBlocks() throws {
        let rig = try ServicesRig(signedIn: false, traktClientID: "CID")
        let guide = OnboardingModel(rig.services)
        XCTAssertEqual(guide.plan, [.welcome, .likes, .have, .debrid, .done], "sin marcar nada: solo se explica Real-Debrid")
        XCTAssertTrue(OnboardingModel.Step.allCases.allSatisfy(guide.canContinue), "ningún paso es obligatorio")
        guide.toggle(.tv)
        XCTAssertEqual(guide.plan, [.welcome, .likes, .have, .debrid, .tv, .done])
        guide.toggle(.trakt)
        XCTAssertEqual(guide.plan, [.welcome, .likes, .have, .debrid, .trakt, .done], "Trakt y la TV juntos")
        XCTAssertTrue(guide.traktWithTV)
        guide.toggle(.trakt)
        XCTAssertEqual(guide.next(after: .debrid), .tv)
        XCTAssertEqual(guide.next(after: .tv), .done)
        XCTAssertNil(guide.next(after: .done))
    }

    func testTheTVStepOnlyWhereThereIsTV() throws {
        let rig = try ServicesRig(signedIn: false, traktClientID: "CID", allowsOrbital: false)
        let guide = OnboardingModel(rig.services)
        guide.answer(.tv, .has)
        XCTAssertFalse(guide.plan.contains(.tv), "la Mac no habla con la TV")
        XCTAssertFalse(guide.pieces.contains(.tv))
    }

    /// Si cierras la app a medias: antes de 24 h sigues donde ibas; después, Inicio lo dice sin obligar.
    func testResumesWithinADayAndThenOnlySuggests() throws {
        let rig = try ServicesRig(signedIn: false)
        let guide = OnboardingModel(rig.services)
        guide.reached(.have)
        XCTAssertEqual(OnboardingModel(rig.services).resumeStep, .have)
        XCTAssertFalse(OnboardingModel.unfinished(rig.services))
        rig.clock.now = rig.clock.now.addingTimeInterval(25 * 3600)
        XCTAssertNil(OnboardingModel(rig.services).resumeStep)
        XCTAssertTrue(OnboardingModel.unfinished(rig.services), "«Termina de preparar Orbital»")
        guide.finish()
        XCTAssertFalse(OnboardingModel.unfinished(rig.services))
    }

    /// H1: son gustos (semillas de «Porque viste»), no vistos; las plataformas filtran «Nuevo en tus plataformas».
    func testLikesAreTasteNotHistory() async throws {
        let rig = try ServicesRig(signedIn: false)
        let guide = OnboardingModel(rig.services)
        let item = Suggestion(kind: "movie", imdb: "tt0816692", title: "Interestelar", year: 2014, runtime: nil, overview: "", poster: "p", wide: "", reason: .trending)
        await guide.loadCandidates()
        guide.toggleLike(item)
        XCTAssertTrue(Taste.likes(rig.kv).isEmpty, "solo cuenta lo que se ofreció en la cuadrícula")
        XCTAssertTrue(rig.services.library.all.isEmpty, "nada se marca visto")
        guide.togglePlatform("netflix")
        XCTAssertEqual(Taste.platforms(rig.kv), ["netflix"])
        guide.togglePlatform("netflix")
        XCTAssertTrue(Taste.platforms(rig.kv).isEmpty)
        let seeds = await rig.services.forYou.recentSeeds()
        XCTAssertTrue(seeds.isEmpty)
        Taste.setLikes([.init(kind: "movie", imdb: "tt0816692", title: "Interestelar", year: 2014)], rig.kv)
        let liked = await rig.services.forYou.recentSeeds()
        XCTAssertEqual(liked.map(\.imdb), ["tt0816692"], "sin historial, tus gustos son las semillas")
    }

    /// Lo que se explicó en la guía cuenta como visto (también la tarjeta «Así funciona» de la sesión de Real-Debrid).
    func testWhatTheGuideExplainedIsSeen() throws {
        let rig = try ServicesRig(signedIn: false)
        OnboardingModel(rig.services).finish(explained: [.debrid])
        let learn = LearnModel(rig.services)
        XCTAssertTrue(learn.seen("instant"))
        XCTAssertNotNil(rig.kv.data("learn.seen.debrid-flow"))
        XCTAssertFalse(learn.seen("thread"))
    }

    func testAddonsCanBeReorderedAndSwitchedOff() async throws {
        let rig = try ServicesRig(signedIn: false)
        let addons = AddonsModel(rig.services)
        await addons.prepare()
        XCTAssertEqual(Array(addons.items.map(\.id).prefix(2)), ["torrentio", "comet"], "los recomendados primero (OpenSubtitles ya no sale: vive en Ajustes)")
        XCTAssertEqual(addons.items.last?.origin, .imported, "y lo que tenías pegado, importado una vez")
        let last = try XCTUnwrap(addons.items.last?.name)
        await addons.move(fromOffsets: [addons.items.count - 1], toOffset: 0)
        XCTAssertEqual(addons.items.first?.name, last, "se pregunta primero")
        await addons.setEnabled("comet", false)
        XCTAssertEqual(addons.items.first { $0.id == "comet" }?.enabled, false)
        XCTAssertTrue(addons.missingRecommended.isEmpty)
        let removedBuiltIn = await addons.remove("torrentio")
        XCTAssertFalse(removedBuiltIn, "Torrentio viene con Orbital: solo se apaga")
        let imported = try XCTUnwrap(addons.items.first { !$0.isBuiltIn })
        XCTAssertTrue(addons.canRemove(imported))
        let removed = await addons.remove(imported.id)
        XCTAssertTrue(removed)
        XCTAssertFalse(addons.items.contains { $0.id == imported.id })
        let undone = await addons.undoRemove(imported.id)
        XCTAssertTrue(undone, "«Deshacer» lo regresa")
        XCTAssertTrue(addons.items.contains { $0.id == imported.id })
    }

    func testDebridSummaryInWords() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        func status(_ days: Double, premium: Bool = true) -> DebridStatus {
            DebridStatus(service: "Real-Debrid", username: "f", isPremium: premium, expires: now.addingTimeInterval(days * 86400 + 3600), checkedAt: now)
        }
        XCTAssertEqual(DebridModel.summary(status(143), now: now).state, .active(daysLeft: 143))
        XCTAssertEqual(DebridModel.summary(status(3), now: now).state, .expiringSoon(daysLeft: 3))
        XCTAssertEqual(DebridModel.summary(status(-2), now: now).state, .expired(daysAgo: 2))
    }
}
