import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// El calendario de «Sale hoy»: el mes se pide a Trakt en dos mitades y se pinta por día; la cuadrícula empieza el día de la
/// semana que toca; sin red el mes queda vacío (sin quedarse cargando); al cambiar de mes se elige su primer día (o hoy).
@MainActor
final class ReleaseCalendarModelTests: XCTestCase {
    /// El reloj del rig es el 9 de octubre de 2025, 08:53 en hora universal.
    func utc(firstWeekday: Int = 1) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = firstWeekday
        return c
    }

    func day(_ text: String, _ cal: Calendar) -> Date {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: text)!
    }

    func row(_ imdb: String, _ title: String, season: Int = 1, episode: Int, aired: String) -> JSON {
        ["first_aired": .string(aired), "episode": ["season": .int(season), "number": .int(episode), "title": "Capítulo"],
         "show": ["title": .string(title), "ids": ["imdb": .string(imdb), "trakt": 1]]]
    }

    let calendarAPI = "https://api.trakt.tv/calendars/my/shows/"

    func testElMesSePideEnDosMitadesYSePintaPorDia() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let cal = utc()
        // Primera mitad: del 1 al 16 de octubre (se pide desde el día anterior por la hora universal); segunda: del 17 al 31.
        rig.http.json["\(calendarAPI)2025-09-30/18?extended=full"] = [
            row("tt11280740", "Severance", episode: 3, aired: "2025-10-03T20:00:00Z"),
            row("tt11280740", "Severance", episode: 4, aired: "2025-10-03T21:00:00Z"),
        ]
        rig.http.json["\(calendarAPI)2025-10-16/17?extended=full"] = [row("tt0903747", "Breaking Bad", season: 5, episode: 1, aired: "2025-10-20T02:00:00Z")]
        let model = ReleaseCalendarModel(rig.services, calendar: cal)
        XCTAssertEqual(model.month, day("2025-10-01", cal), "se abre en el mes de hoy")
        XCTAssertEqual(model.selected, day("2025-10-09", cal), "con hoy elegido")
        await model.load()
        XCTAssertFalse(model.loading)
        let third = model.airings(on: day("2025-10-03", cal))
        XCTAssertEqual(third.count, 1, "dos episodios de la misma serie el mismo día van juntos")
        XCTAssertEqual(third.first?.first, 3)
        XCTAssertEqual(third.first?.last, 4)
        XCTAssertEqual(model.airings(on: day("2025-10-20", cal).addingTimeInterval(3600)).map(\.series.imdb), ["tt0903747"], "cualquier hora del día cuenta")
        XCTAssertTrue(model.airings(on: day("2025-10-09", cal)).isEmpty)
        XCTAssertEqual(model.days.count, 2)
        XCTAssertNil(model.problem)
    }

    func testLaCuadriculaEmpiezaElDiaDeLaSemanaQueToca() throws {
        let rig = try ServicesRig()
        // El 1 de octubre de 2025 fue miércoles.
        let sunday = ReleaseCalendarModel(rig.services, calendar: utc(firstWeekday: 1)).grid
        XCTAssertEqual(sunday.prefix(3).filter { $0 == nil }.count, 3, "semana desde el domingo: tres casillas vacías")
        XCTAssertNotNil(sunday[3])
        XCTAssertEqual(sunday.compactMap { $0 }.count, 31)
        let monday = ReleaseCalendarModel(rig.services, calendar: utc(firstWeekday: 2)).grid
        XCTAssertEqual(monday.prefix(while: { $0 == nil }).count, 2, "semana desde el lunes: dos")
        XCTAssertEqual(monday.compactMap { $0 }.last, day("2025-10-31", utc()))
    }

    func testSinConexionElMesQuedaVacioSinQuedarseCargando() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.offline = true
        let model = ReleaseCalendarModel(rig.services, calendar: utc())
        await model.load()
        XCTAssertFalse(model.loading)
        XCTAssertTrue(model.days.isEmpty)
        XCTAssertTrue(model.airings(on: model.today).isEmpty)
        XCTAssertEqual(model.problem, .offline, "se dice que no hay internet (antes parecía un mes sin estrenos)")
    }

    func testTraktCaidoSeDiceYAlVolverSeQuita() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        rig.http.statuses["\(calendarAPI)2025-09-30/18?extended=full"] = 503
        let model = ReleaseCalendarModel(rig.services, calendar: utc())
        await model.load()
        XCTAssertEqual(model.problem, .down(.trakt))
        rig.http.statuses["\(calendarAPI)2025-09-30/18?extended=full"] = nil
        rig.http.json["\(calendarAPI)2025-09-30/18?extended=full"] = []
        rig.http.json["\(calendarAPI)2025-10-16/17?extended=full"] = []
        await model.load()
        XCTAssertNil(model.problem, "llegó todo: sin aviso")
    }

    func testSinTraktNoSePideNada() async throws {
        let rig = try ServicesRig()
        let model = ReleaseCalendarModel(rig.services, calendar: utc())
        await model.load()
        XCTAssertTrue(model.days.isEmpty)
        XCTAssertFalse(rig.http.calls.contains { $0.contains("api.trakt.tv") }, "\(rig.http.calls)")
    }

    func testOtroMesEligeSuPrimerDiaYVolverEligeHoy() async throws {
        let rig = try ServicesRig(traktLinked: true, traktClientID: "CID")
        let cal = utc()
        rig.http.prefix[calendarAPI] = [row("tt11280740", "Severance", episode: 5, aired: "2025-11-07T20:00:00Z")]
        let model = ReleaseCalendarModel(rig.services, calendar: cal)
        await model.move(1)
        XCTAssertEqual(model.month, day("2025-11-01", cal))
        XCTAssertEqual(model.selected, day("2025-11-01", cal), "otro mes: su primer día")
        XCTAssertEqual(model.airings(on: day("2025-11-07", cal)).map(\.series.imdb), ["tt11280740"])
        XCTAssertEqual(model.grid.compactMap { $0 }.count, 30)
        await model.move(-1)
        XCTAssertEqual(model.month, day("2025-10-01", cal))
        XCTAssertEqual(model.selected, model.today, "de vuelta en este mes: hoy")
        XCTAssertTrue(model.airings(on: day("2025-11-07", cal)).isEmpty, "lo del otro mes no se queda")
    }
}
