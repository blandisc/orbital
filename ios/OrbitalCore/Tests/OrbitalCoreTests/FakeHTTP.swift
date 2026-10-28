import Foundation
@testable import OrbitalCore

/// Responde con JSON guardado por URL (sin red). Apunta las URLs que se pidieron.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _json: [String: JSON] = [:]
    private var _calls: [String] = []
    private var _bodies: [String: [Data]] = [:]
    var fail = false
    private var _delays: [String: Int] = [:]
    /// Milisegundos de demora por URL (para que dos peticiones se crucen).
    var delays: [String: Int] {
        get { lock.withLock { _delays } }
        set { lock.withLock { _delays = newValue } }
    }
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
    private var _raw: [String: Data] = [:]
    /// Respuestas que no son JSON (el HTML de la página del Top 10 de Netflix).
    var raw: [String: Data] {
        get { lock.withLock { _raw } }
        set { lock.withLock { _raw = newValue } }
    }
    var calls: [String] { lock.withLock { _calls } }
    private var _headers: [[String: String]] = []
    /// Los encabezados de cada petición, en orden.
    var headers: [[String: String]] { lock.withLock { _headers } }
    func bodies(for url: String) -> [Data] { lock.withLock { _bodies[url] ?? [] } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let key = request.url.absoluteString
        lock.withLock {
            _calls.append(key)
            _headers.append(request.headers)
            if let body = request.body { _bodies[key, default: []].append(body) }
        }
        if let ms = lock.withLock({ _delays[key] }) { try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000) }
        if fail || lock.withLock({ _failing.contains(key) }) { throw NetworkError("sin conexión") }
        let forced = lock.withLock { _statuses[key] }
        if let data = lock.withLock({ _raw[key] }) { return HTTPResponse(status: forced ?? status, data: data) }
        guard let body = lock.withLock({ _json[key] }) else { return HTTPResponse(status: forced ?? 404, data: Data()) }
        return HTTPResponse(status: forced ?? status, data: body.serialized())
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date(timeIntervalSince1970: 1_760_000_000)
    var now: Date { get { lock.withLock { _now } } set { lock.withLock { _now = newValue } } }
}
