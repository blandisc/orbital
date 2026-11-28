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

    /// TK-L2 (18 nov 2026): Trakt te reconoce con tres números: lo visto, lo de Mi lista y las series con algo visto. Lo que
    /// ocultaste no cuenta, y una cuenta nueva sale vacía (la pantalla no enseña ceros).
    func testTraktCountsWatchedListedAndShowsYouFollow() {
        var show = LibraryEntry(metaID: "tt1", kind: "series", name: "Shōgun"); show.seen = ["tt1:1:1", "tt1:1:2"]
        var movie = LibraryEntry(metaID: "tt2", kind: "movie", name: "Duna"); movie.seen = ["tt2"]; movie.inList = true
        var listed = LibraryEntry(metaID: "tt3", kind: "series", name: "Severance"); listed.inList = true
        var hidden = LibraryEntry(metaID: "tt4", kind: "series", name: "Oculta"); hidden.seen = ["tt4:1:1"]; hidden.hiddenAt = 1
        let got = OnboardingModel.count([show, movie, listed, hidden])
        XCTAssertEqual(got, .init(watched: 3, listed: 2, shows: 1))
        XCTAssertTrue(OnboardingModel.count([]).isEmpty)
    }

    /// v3 (18 nov 2026): el camino sale de la versión, sin preguntar qué tienes. En Ultra, la TV va antes de Trakt; con
    /// nube se explica tu nube; en la de la tienda, tus plataformas. Nada detiene la guía.
    func testTheRouteFollowsTheEdition() throws {
        let ultra = OnboardingModel(try ServicesRig(signedIn: false, traktClientID: "CID").services)
        XCTAssertEqual(ultra.plan, [.welcome, .tv, .trakt, .debrid, .done])
        XCTAssertTrue(OnboardingModel.Step.allCases.allSatisfy(ultra.canContinue), "ningún paso es obligatorio")
        XCTAssertEqual(ultra.next(after: .trakt), .debrid)
        XCTAssertNil(ultra.next(after: .done))
        let plus = OnboardingModel(try ServicesRig(signedIn: false, traktClientID: "CID", edition: .plus).services)
        XCTAssertEqual(plus.plan, [.welcome, .trakt, .debrid, .done], "Plus no tiene TV")
        let store = OnboardingModel(try ServicesRig(signedIn: false, traktClientID: "CID", edition: .orbital).services)
        XCTAssertEqual(store.plan, [.welcome, .trakt, .platforms, .done], "la de la tienda no reproduce: tus plataformas")
        let mac = OnboardingModel(try ServicesRig(signedIn: false, traktClientID: "CID", allowsOrbital: false).services)
        XCTAssertFalse(mac.plan.contains(.tv), "la Mac no habla con la TV")
    }

    /// «Trajimos lo tuyo» (K4-B) sale solo si Trakt trajo algo; los puntos del arco ya lo contaban, así que no cambian.
    func testWhatTraktBroughtGetsItsStep() throws {
        let rig = try ServicesRig(signedIn: false, traktClientID: "CID", edition: .plus)
        let guide = OnboardingModel(rig.services)
        XCTAssertEqual(guide.position(.debrid).total, 5, "bienvenida, Trakt, lo tuyo, nube y listo")
        XCTAssertFalse(guide.plan.contains(.win), "sin Trakt no hay nada que enseñar")
        XCTAssertEqual(guide.position(.debrid).current, 3)
    }

    /// El mosaico de «Trajimos lo tuyo»: lo tuyo con póster, lo más reciente primero; lo oculto y lo que no viste ni guardaste, no.
    func testTheWinMosaicIsYourRecentStuff() {
        func entry(_ id: String, at: Double, seen: Bool = true, listed: Bool = false, poster: String? = "p", hidden: Bool = false) -> LibraryEntry {
            var e = LibraryEntry(metaID: id, kind: "movie", name: id); e.poster = poster; e.updatedAt = at
            if seen { e.seen = [id] }; e.inList = listed; if hidden { e.hiddenAt = 1 }; return e
        }
        let tiles = OnboardingModel.tiles([entry("old", at: 1), entry("new", at: 3, listed: true), entry("hidden", at: 4, hidden: true),
                                           entry("noposter", at: 5, poster: nil), entry("nothing", at: 6, seen: false)])
        XCTAssertEqual(tiles.map(\.id), ["new", "old"])
        XCTAssertEqual(tiles.first?.listed, true, "lo de tu lista lleva su marcador")
    }

    /// Conectar tu nube (o Trakt) en su propio paso no reacomoda la guía: el paso sigue y la luna no regresa al principio
    /// (18 nov 2026, se vio con toques en la hoja «Tu nube»).
    func testConnectingOnItsStepKeepsThePlace() async throws {
        let rig = try ServicesRig(signedIn: false, traktClientID: "CID")
        let guide = OnboardingModel(rig.services)
        guide.reached(.debrid)
        let before = guide.position(.debrid)
        await rig.services.debrid.save(token: token, status: DebridStatus(service: "Real-Debrid", username: "fer", isPremium: true,
                                                                            expires: nil, checkedAt: Date(), userID: "1"), share: false)
        XCTAssertTrue(guide.isConnected(.debrid))
        XCTAssertEqual(guide.position(.debrid).current, before.current, "el paso donde estás no se mueve al conectar")
        XCTAssertEqual(guide.next(after: .debrid), .done)
        let fresh = OnboardingModel(rig.services)
        XCTAssertFalse(fresh.plan.contains(.debrid), "si ya estaba conectada antes de llegar, no se explica")
    }

    /// Si cierras la app a medias: antes de 24 h sigues donde ibas; después, Inicio lo dice sin obligar.
    func testResumesWithinADayAndThenOnlySuggests() throws {
        let rig = try ServicesRig(signedIn: false)
        let guide = OnboardingModel(rig.services)
        guide.reached(.trakt)
        XCTAssertEqual(OnboardingModel(rig.services).resumeStep, .trakt)
        XCTAssertFalse(OnboardingModel.unfinished(rig.services))
        XCTAssertTrue(OnboardingModel.shouldShow(rig.services), "antes de 24 h sigue donde ibas")
        rig.clock.now = rig.clock.now.addingTimeInterval(25 * 3600)
        XCTAssertNil(OnboardingModel(rig.services).resumeStep)
        XCTAssertTrue(OnboardingModel.unfinished(rig.services), "«Termina de preparar Orbital»")
        XCTAssertFalse(OnboardingModel.shouldShow(rig.services), "después, ya no sale entera en cada arranque")
        guide.finish()
        XCTAssertFalse(OnboardingModel.unfinished(rig.services))
    }

    /// Tus plataformas (A1-B) solo se guardan en Orbital y filtran «Nuevo en tus plataformas»; nada se marca visto.
    func testPlatformsAreSavedAndNothingIsMarkedWatched() throws {
        let rig = try ServicesRig(signedIn: false)
        let guide = OnboardingModel(rig.services)
        guide.togglePlatform("netflix")
        XCTAssertEqual(Taste.platforms(rig.kv), ["netflix"])
        guide.togglePlatform("netflix")
        XCTAssertTrue(Taste.platforms(rig.kv).isEmpty)
        XCTAssertTrue(rig.services.library.all.isEmpty, "nada se marca visto")
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
