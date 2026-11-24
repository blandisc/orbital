import XCTest
@testable import OrbitalCore

/// Arranque rápido (23 nov 2026): la dirección final de Torrentio se resuelve antes de «Ver» y se gasta una vez.
final class StreamLinksTests: XCTestCase {
    let torrentio = URL(string: "https://torrentio.example/resolve/realdebrid/K/\(String(repeating: "a", count: 40))/null/0/x.mkv")!
    let final = URL(string: "https://abc.download.example/d/ID/x.mkv")!

    final class Calls: @unchecked Sendable {
        let lock = NSLock(); var count = 0
        func add() { lock.withLock { count += 1 } }
        var value: Int { lock.withLock { count } }
    }

    func testOnlyAddonLinksThatRedirectAreResolved() {
        XCTAssertTrue(StreamLinks.worthResolving(torrentio, headers: [:]))
        XCTAssertTrue(StreamLinks.worthResolving(URL(string: "https://mediafusion.example/playback/abc/x.mkv")!, headers: [:]))
        XCTAssertFalse(StreamLinks.worthResolving(torrentio, headers: ["Referer": "x"]), "con datos extra: esos son solo para el complemento")
        XCTAssertFalse(StreamLinks.worthResolving(final, headers: [:]), "ya es el archivo: pedirlo sería otra conexión a la nube")
        XCTAssertFalse(StreamLinks.worthResolving(URL(string: "https://x.example/resolve/list.m3u8")!, headers: [:]))
        XCTAssertFalse(StreamLinks.worthResolving(URL(fileURLWithPath: "/tmp/resolve/x.mkv"), headers: [:]), "tus descargas, no")
    }

    func testOffUntilTheAppTurnsItOn() async {
        let links = StreamLinks()
        XCTAssertNil(links.start(torrentio), "las pruebas y la app sin prender: nunca a la red")
        let (url, how) = await links.playable(torrentio)
        XCTAssertEqual(url, torrentio); XCTAssertEqual(how, .none)
    }

    func testResolvedOnceIsUsedOnceThenTheAddonAgain() async {
        let calls = Calls(), final = self.final
        let links = StreamLinks(resolver: { _ in calls.add(); return final })
        _ = await links.start(torrentio)?.value
        _ = await links.start(torrentio)?.value
        XCTAssertEqual(calls.value, 1, "la ficha y el reproductor piden la misma: una sola vuelta a Torrentio")
        let first = await links.playable(torrentio)
        XCTAssertEqual(first.url, final); XCTAssertEqual(first.how, .ready)
        let again = await links.playable(torrentio)
        XCTAssertEqual(again.url, torrentio, "un reintento o volver a la app: por el complemento, como siempre")
    }

    func testPlayJoinsAResolutionAlreadyOnItsWay() async {
        let final = self.final
        let links = StreamLinks(resolver: { _ in try? await Task.sleep(nanoseconds: 50_000_000); return final })
        links.start(torrentio)
        let (url, how) = await links.playable(torrentio)
        XCTAssertEqual(url, final); XCTAssertEqual(how, .joined)
        let after = await links.playable(torrentio)
        XCTAssertEqual(after.url, torrentio, "también se gasta al unirse")
    }

    func testOldOrFailedResolutionsFallBackToTheAddonLink() async {
        final class Now: @unchecked Sendable { var date = Date(timeIntervalSince1970: 1_000) }
        let now = Now(), final = self.final
        let links = StreamLinks(resolver: { _ in final }, clock: { now.date })
        _ = await links.start(torrentio)?.value
        now.date = now.date.addingTimeInterval(StreamLinks.lifetime + 1)
        let stale = await links.playable(torrentio)
        XCTAssertEqual(stale.url, torrentio, "una dirección vieja no se abre")

        let failing = StreamLinks(resolver: { _ in nil })
        _ = await failing.start(torrentio)?.value
        let none = await failing.playable(torrentio)
        XCTAssertEqual(none.url, torrentio)

        let forgotten = StreamLinks(resolver: { _ in final })
        _ = await forgotten.start(torrentio)?.value
        forgotten.forget(torrentio)
        let after = await forgotten.playable(torrentio)
        XCTAssertEqual(after.url, torrentio, "no abrió: se olvida")
    }

    func testTheProbeOnlyAcceptsAnotherWebAddress() {
        XCTAssertEqual(RedirectProbe.target(final, from: torrentio), final)
        XCTAssertNil(RedirectProbe.target(torrentio, from: torrentio))
        XCTAssertNil(RedirectProbe.target(URL(string: "magnet:?xt=urn:btih:abc")!, from: torrentio))
    }

    func testTheTitlePageWarmsTheFinalAddress() async throws {
        let seen = StreamWarmupTests.Box(), final = self.final
        StreamWarmup.engineWarm = { url, _ in seen.add(url) }
        StreamWarmup.links = StreamLinks(resolver: { _ in final })
        defer { StreamWarmup.engineWarm = nil; StreamWarmup.links = .shared }
        let url = URL(string: "https://torrentio.example/resolve/realdebrid/K/\(UUID())/x.mkv")!
        XCTAssertTrue(StreamWarmup.warm(url))
        for _ in 0..<100 where seen.urls.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(seen.urls, [final], "el motor calienta la misma dirección que abrirá «Ver»")
    }
}
