import XCTest
@testable import OrbitalCore
@testable import OrbitalModels

/// «Desde la TV»: lo que la consola le deja al iPhone se atiende y solo entonces se le avisa (`ack`).
@MainActor
final class InboxModelTests: XCTestCase {
    let nowURL = "https://tv.example/api/companion/now"
    let ackURL = "https://tv.example/api/companion/inbox/ack"
    let streamURL = "https://a.example/stream/series/tt0386676%3A2%3A5.json"

    func connected() throws -> ServicesRig {
        let rig = try ServicesRig()
        rig.services.settings.update { $0.orbitalAddress = "tv.example" }
        rig.secrets.set(SecretKey.orbitalToken, "secreto")
        rig.http.json[ackURL] = .object(["removed": .int(1)])
        rig.http.json[streamURL] = ["streams": [
            ["name": "T\n1080p [RD+]", "title": "Show S02E05 1080p WEB-DL\n👤 100 💾 0.5 GB", "url": "https://rd.example/e5.mkv"]]]
        return rig
    }

    func item(_ id: String = "a1", action: OrbitalRemote.InboxItem.Action = .download) -> OrbitalRemote.InboxItem {
        OrbitalRemote.InboxItem(id: id, kind: "series", metaID: "tt0386676", videoID: "tt0386676:2:5", title: "The Office", episodeLabel: "T2 · E5", poster: nil, action: action)
    }

    func acked(_ rig: ServicesRig) throws -> [String] {
        try rig.http.bodies(ackURL).flatMap { body -> [String] in
            (try XCTUnwrap(JSON.parse(body))["ids"]?.array ?? []).compactMap(\.string)
        }
    }

    func testADownloadFromTheTVIsQueuedWithTheRecommendedSourceAndThenAcked() async throws {
        let rig = try connected()
        let inbox = InboxModel(rig.services)
        var events: [InboxModel.Event] = []
        inbox.onEvent = { events.append($0) }
        await inbox.process([item()])
        try await Task.sleep(nanoseconds: 50_000_000)
        let queued = await rig.services.downloads.all
        XCTAssertEqual(queued.map(\.videoID), ["tt0386676:2:5"])
        XCTAssertEqual(queued.first?.subtitle, "T2 · E5")
        XCTAssertEqual(rig.transport.starts, ["https://rd.example/e5.mkv"])
        XCTAssertEqual(events, [.downloading("The Office T2 · E5")])
        XCTAssertEqual(try acked(rig), ["a1"])
        XCTAssertTrue(inbox.fromTV.isEmpty, "una descarga no deja tarjeta")
    }

    func testOpenSavesAFromTVCardThatSurvivesARestartAndThenAcks() async throws {
        let rig = try connected()
        let inbox = InboxModel(rig.services)
        var events: [InboxModel.Event] = []
        inbox.onEvent = { events.append($0) }
        await inbox.process([item("o1", action: .open)])
        XCTAssertEqual(inbox.fromTV.map(\.id), ["o1"])
        XCTAssertEqual(events, [.received("The Office T2 · E5")])
        XCTAssertEqual(try acked(rig), ["o1"])
        XCTAssertTrue(rig.transport.starts.isEmpty, "abrir no descarga nada")
        XCTAssertEqual(InboxModel(rig.services).fromTV.map(\.id), ["o1"], "la tarjeta se queda aunque cierres la app")
        inbox.dismiss(item("o1", action: .open))
        XCTAssertTrue(InboxModel(rig.services).fromTV.isEmpty)
    }

    func testNothingIsAckedWhileItCouldNotBeActedOn() async throws {
        let rig = try connected()
        // Los complementos no contestan (sin red, no «no hay fuentes»): el pendiente se queda en la consola.
        rig.http.json["https://a.example/manifest.json"] = nil
        rig.http.statuses["https://a.example/manifest.json"] = 500
        let inbox = InboxModel(rig.services)
        await inbox.process([item()])
        XCTAssertEqual(rig.http.bodies(ackURL).count, 0)
        let none = await rig.services.downloads.all
        XCTAssertTrue(none.isEmpty)
    }

    func testWhenThereAreNoSourcesItSaysSoAndStopsInsisting() async throws {
        let rig = try connected()
        rig.http.json[streamURL] = ["streams": []]
        let inbox = InboxModel(rig.services)
        var events: [InboxModel.Event] = []
        inbox.onEvent = { events.append($0) }
        await inbox.process([item()])
        XCTAssertEqual(events, [.downloadFailed("The Office T2 · E5", reason: .noSources)])
        XCTAssertEqual(try acked(rig), ["a1"], "se avisó en palabras: no se reintenta cada 5 s")
    }

    func testTheSameItemRepeatedByTheConsoleIsNotDoneTwice() async throws {
        let rig = try connected()
        let inbox = InboxModel(rig.services)
        var events: [InboxModel.Event] = []
        inbox.onEvent = { events.append($0) }
        await inbox.process([item()])
        await inbox.process([item()])  // el aviso se perdió y la consola lo repite
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(events.count, 1)
        let all = await rig.services.downloads.all
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(try acked(rig), ["a1", "a1"], "se le vuelve a avisar, sin repetir la descarga")
        // Y dos «Abrir» del mismo título dejan una sola tarjeta.
        await inbox.process([item("o1", action: .open), item("o2", action: .open)])
        XCTAssertEqual(inbox.fromTV.map(\.id), ["o2"])
    }

    func testTheCardDownloadQueuesAndRemovesTheCard() async throws {
        let rig = try connected()
        let inbox = InboxModel(rig.services)
        await inbox.process([item("o1", action: .open)])
        await inbox.downloadFromCard(item("o1", action: .open))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(rig.transport.starts, ["https://rd.example/e5.mkv"])
        XCTAssertTrue(inbox.fromTV.isEmpty)
    }

    func testTheTVNowPollHandsTheInboxOverAndTheConsoleIsAckedOnlyAfterActing() async throws {
        let rig = try connected()
        rig.http.json[nowURL] = .object(["playing": .null, "inbox": .array([
            .object(["id": "p1", "kind": "series", "meta_id": "tt0386676", "video_id": "tt0386676:2:5", "title": "The Office",
                     "episode_label": "T2 · E5", "poster": .null, "action": "download", "at": .int(1_760_000_000)])])])
        let model = TVNowModel(rig.services, intervalSeconds: 0.01)
        model.inbox = InboxModel(rig.services)
        model.setActive(true)
        try await Task.sleep(nanoseconds: 150_000_000)
        model.setActive(false)
        let all = await rig.services.downloads.all
        XCTAssertEqual(all.map(\.videoID), ["tt0386676:2:5"])
        XCTAssertEqual(try Set(acked(rig)), ["p1"])
    }
}
