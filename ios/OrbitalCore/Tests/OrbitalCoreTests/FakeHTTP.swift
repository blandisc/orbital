import Foundation
@testable import OrbitalCore

/// Responde con JSON guardado por URL (sin red). Apunta las URLs que se pidieron.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _json: [String: JSON] = [:]
    private var _calls: [String] = []
    private var _bodies: [String: [Data]] = [:]
    var fail = false
    private var _failing: Set<String> = []
    /// URLs que fallan como si no hubiera red (solo esas).
    var failing: Set<String> {
        get { lock.withLock { _failing } }
        set { lock.withLock { _failing = newValue } }
    }
    var status = 200
    private var _statuses: [String: Int] = [:]
    var statuses: [String: Int] {
        get { lock.withLock { _statuses } }
        set { lock.withLock { _statuses = newValue } }
    }

    var json: [String: JSON] {
        get { lock.withLock { _json } }
        set { lock.withLock { _json = newValue } }
    }
    var calls: [String] { lock.withLock { _calls } }
    func bodies(for url: String) -> [Data] { lock.withLock { _bodies[url] ?? [] } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let key = request.url.absoluteString
        lock.withLock {
            _calls.append(key)
            if let body = request.body { _bodies[key, default: []].append(body) }
        }
        if fail || lock.withLock({ _failing.contains(key) }) { throw NetworkError("sin conexión") }
        let forced = lock.withLock { _statuses[key] }
        guard let body = lock.withLock({ _json[key] }) else { return HTTPResponse(status: forced ?? 404, data: Data()) }
        return HTTPResponse(status: forced ?? status, data: body.serialized())
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_760_000_000)
    var now: Date { get { lock.withLock { _now } } set { lock.withLock { _now = newValue } } }
}
