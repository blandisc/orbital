import XCTest
@testable import OrbitalModels

/// Canales: el mismo episodio y el mismo minuto para todos a la misma hora, sin repetir el del turno anterior.
final class ChannelScheduleTests: XCTestCase {
    let episodes = (1...12).map { ChannelSchedule.Episode(season: 1, episode: $0, name: "E\($0)", still: "", videoID: "tt1:1:\($0)") }
    let length: TimeInterval = 22 * 60

    func testLaMismaHoraDaLoMismo() {
        let now = ChannelSchedule.epoch.addingTimeInterval(1_000_000)
        let a = ChannelSchedule.onAir(seriesID: "tt0096697", episodes: episodes, length: length, now: now)
        let b = ChannelSchedule.onAir(seriesID: "tt0096697", episodes: episodes, length: length, now: now)
        XCTAssertEqual(a, b)
    }

    func testCuantoLlevaYCuantoLeQueda() throws {
        let start = ChannelSchedule.epoch.addingTimeInterval(length * 100)
        let air = try XCTUnwrap(ChannelSchedule.onAir(seriesID: "tt1", episodes: episodes, length: length, now: start.addingTimeInterval(5 * 60)))
        XCTAssertEqual(air.elapsed, 5 * 60, accuracy: 0.001)
        XCTAssertEqual(air.minutesLeft, 17)
        XCTAssertEqual(air.progress, 5.0 / 22, accuracy: 0.0001)
    }

    func testElQueSigueEsElDelProximoTurno() throws {
        let now = ChannelSchedule.epoch.addingTimeInterval(length * 40 + 10)
        let air = try XCTUnwrap(ChannelSchedule.onAir(seriesID: "tt1", episodes: episodes, length: length, now: now))
        let later = try XCTUnwrap(ChannelSchedule.onAir(seriesID: "tt1", episodes: episodes, length: length, now: now.addingTimeInterval(length)))
        XCTAssertEqual(air.next, later.episode)
    }

    func testNuncaRepiteElDelTurnoAnterior() {
        for slot in 1..<500 {
            XCTAssertNotEqual(ChannelSchedule.index("tt2", slot: slot, count: 3), ChannelSchedule.index("tt2", slot: slot - 1, count: 3), "turno \(slot)")
        }
    }

    func testEnCadaVueltaPasanTodosSinRepetir() {
        let count = 7
        for lap in 0..<20 {
            let seen = (lap * count..<(lap + 1) * count).map { ChannelSchedule.index("tt9", slot: $0, count: count) }
            XCTAssertEqual(Set(seen).count, count, "vuelta \(lap)")
        }
        for slot in 1..<300 {
            XCTAssertNotEqual(ChannelSchedule.index("tt9", slot: slot, count: count), ChannelSchedule.index("tt9", slot: slot - 1, count: count))
        }
        for slot in 1..<50 {
            XCTAssertNotEqual(ChannelSchedule.index("tt9", slot: slot, count: 2), ChannelSchedule.index("tt9", slot: slot - 1, count: 2))
        }
    }

    func testCadaCanalVaPorSuLado() {
        let now = ChannelSchedule.epoch.addingTimeInterval(9_999_999)
        let picks = Set(["tt1", "tt2", "tt3", "tt4", "tt5", "tt6"].compactMap {
            ChannelSchedule.onAir(seriesID: $0, episodes: episodes, length: length, now: now)?.episode.episode
        })
        XCTAssertGreaterThan(picks.count, 1, "seis series no pueden estar todas en el mismo episodio")
    }

    func testSinEpisodiosNoHayCanal() {
        XCTAssertNil(ChannelSchedule.onAir(seriesID: "tt1", episodes: [], length: length, now: Date()))
    }
}
