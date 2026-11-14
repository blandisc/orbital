import XCTest
@testable import OrbitalModels
import OrbitalCore

/// El mapa de «Lo que ves»: los días que ves más se ven más fuertes y el «No sé cuándo» de Trakt no estira ni apaga el mapa
/// (Fernando, 14 nov 2026).
final class WatchingHeatTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func play(_ day: Int, minutes: Int, at base: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> TraktPlay {
        TraktPlay(at: base.addingTimeInterval(Double(day) * 86_400), kind: "movie", imdb: "tt\(day)", title: "x", minutes: minutes, genres: [])
    }

    func testUnknownDatesStayOutOfTheMap() {
        let unknown = TraktPlay(at: Date(timeIntervalSince1970: 0), kind: "movie", imdb: "tt1", title: "x", minutes: 9_000, genres: [])
        let m = WatchingHeat.minutes([unknown, play(0, minutes: 100)], since: .distantPast, calendar: calendar)
        XCTAssertEqual(m.count, 1, "«No sé cuándo» (1970) no es un día del mapa")
    }

    func testBusierDaysAreStronger() {
        let plays = [play(0, minutes: 30), play(1, minutes: 90), play(2, minutes: 200), play(3, minutes: 5_000)]
        let m = WatchingHeat.minutes(plays, since: .distantPast, calendar: calendar)
        let levels = WatchingHeat.levels(m)
        let byMinutes = m.sorted { $0.value < $1.value }.map { levels[$0.key] ?? 0 }
        XCTAssertEqual(byMinutes, byMinutes.sorted(), "más minutos, nunca más pálido")
        XCTAssertEqual(Set(byMinutes), [1, 2, 3], "un maratón no deja a los demás días del mismo tono: se ven los tres niveles")
    }

    func testPlaysWithoutRuntimeStillCount() {
        let m = WatchingHeat.minutes([play(0, minutes: 0)], since: .distantPast, calendar: calendar)
        XCTAssertEqual(m.values.first, WatchingHeat.fallbackMinutes)
    }
}
