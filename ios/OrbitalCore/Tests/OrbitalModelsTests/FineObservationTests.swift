import Observation
import XCTest
@testable import OrbitalModels

/// V9 (repintado fino): Inicio, la ficha y los servicios avisan por propiedad. Lo que pinta una parte se vuelve a pintar
/// cuando cambia lo suyo (nada deja de actualizarse) y no cuando cambia otra cosa (no se pinta de más).
@MainActor
final class FineObservationTests: XCTestCase {
    final class Counter: @unchecked Sendable { var value = 0 }

    /// Cuántas veces se enteraría una vista que pintó `read`.
    func watch(_ read: @escaping () -> Void) -> Counter {
        let fired = Counter()
        withObservationTracking(read) { fired.value += 1 }
        return fired
    }

    func testHomeKindRepaintsWhoReadsItAndNotTheRows() throws {
        let rig = try ServicesRig()
        let home = HomeModel(rig.services)
        let kind = watch { _ = home.spotlightKind }
        let shown = watch { _ = home.spotlightShown }   // derivada: lee `spotlightKind`
        let rows = watch { _ = home.continueWatching; _ = home.myList; _ = home.upcoming }
        let whole = watch { home.track() }
        var heard = 0
        let subscription = home.onChange { heard += 1 }
        home.spotlightKind = "movie"
        XCTAssertEqual(kind.value, 1, "quien lee el tipo se entera")
        XCTAssertEqual(shown.value, 1, "lo que se filtra por tipo, también")
        XCTAssertEqual(rows.value, 0, "las filas que no leen el tipo no se vuelven a pintar")
        XCTAssertEqual(whole.value, 0, "`track()` ya no suscribe a todo Inicio")
        XCTAssertEqual(heard, 1, "quien escucha desde código se entera igual")
        home.spotlightKind = "movie"
        XCTAssertEqual(heard, 1, "el mismo valor no avisa (como antes)")
        subscription.cancel()
    }

    func testHomeFavoritesRowChangesOnlyItsReaders() throws {
        let rig = try ServicesRig()
        let home = HomeModel(rig.services)
        let favorites = watch { _ = home.favorites }
        let spotlight = watch { _ = home.spotlight }
        let dune = Suggestion(kind: "movie", imdb: "tt1160419", title: "Dune", poster: "p", wide: "", reason: .inList(ForYou.favoritesName))
        FavoriteChange.post(dune, add: true)
        XCTAssertEqual(favorites.value, 1)
        XCTAssertEqual(spotlight.value, 0)
    }

    func testTitleSeasonRepaintsTheEpisodesNotTheHeader() throws {
        let rig = try ServicesRig()
        let title = TitleModel(rig.services, kind: "series", metaID: "tt0386676", hint: ("The Office", nil))
        let header = watch { _ = title.title; _ = title.poster; _ = title.info }
        let season = watch { _ = title.selectedSeason }
        let rows = watch { _ = title.rows }
        title.select(season: 2)
        XCTAssertEqual(season.value, 1)
        XCTAssertEqual(rows.value, 1, "los episodios se vuelven a armar")
        XCTAssertEqual(header.value, 0, "el arte y el nombre no se vuelven a pintar")
    }

    func testTitleVersionStateRepaintsItsReaders() throws {
        let rig = try ServicesRig()
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        let check = watch { _ = title.sourceCheck }
        let cause = watch { _ = title.unavailableCause }
        let header = watch { _ = title.title }
        let whole = watch { title.track() }
        var heard = 0
        let subscription = title.onChange { heard += 1 }
        title.sourceCheck = .none
        XCTAssertEqual(check.value, 1, "«Ver» se entera de que no hay versiones")
        XCTAssertEqual(cause.value, 0)
        XCTAssertEqual(header.value, 0)
        XCTAssertEqual(whole.value, 0)
        XCTAssertEqual(heard, 1)
        title.sourceCheck = .none
        XCTAssertEqual(heard, 2, "`sourceCheck` avisaba siempre, aunque fuera el mismo: sigue igual")
        subscription.cancel()
    }

    func testTitleCoalescingStillTellsListenersOnce() throws {
        let rig = try ServicesRig()
        let title = TitleModel(rig.services, kind: "movie", metaID: "tt0816692")
        let check = watch { _ = title.sourceCheck }
        var heard = 0
        let subscription = title.onChange { heard += 1 }
        title.coalescing { title.sourceCheck = .available; title.unavailableCause = nil; title.sourceCheck = .none }
        XCTAssertEqual(heard, 1)
        XCTAssertEqual(check.value, 1)
        subscription.cancel()
    }

    func testTheTVLinkNoLongerRepaintsTheWholeApp() throws {
        let rig = try ServicesRig()
        let services = rig.services
        let whole = watch { services.track() }   // quien lee `env.services` (casi toda la app)
        let status = watch { _ = services.tvLinkNow }   // Ajustes › Tu Orbital
        var heard = 0
        let subscription = services.onChange { heard += 1 }
        services.tvLink = .checking
        XCTAssertEqual(whole.value, 0, "preguntarle a la TV ya no repinta toda la app")
        XCTAssertEqual(status.value, 1, "lo que dice si la TV contesta, sí")
        XCTAssertEqual(heard, 1, "el sondeo de «Viendo en la TV» y Ajustes se enteran desde código")
        let again = watch { services.track() }
        services.settingsDidChange()
        XCTAssertEqual(again.value, 1, "un ajuste (el idioma) sigue repintando a todos")
        subscription.cancel()
    }
}
