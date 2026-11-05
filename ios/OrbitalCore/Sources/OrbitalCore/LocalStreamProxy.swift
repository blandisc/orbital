import Foundation
import Network

/// El intermediario de ST6: un servidor mínimo en el propio aparato (127.0.0.1) al que el reproductor le pide el video como
/// si fuera Real-Debrid; contesta con lo que `ParallelStream` ya bajó con varias conexiones. Entiende GET y HEAD con
/// `Range` (lo que usa el motor para leer y saltar) y cierra cada respuesta al terminar. Nada sale del aparato.
public final class LocalStreamProxy: @unchecked Sendable {
    public static let shared = LocalStreamProxy()

    private let queue = DispatchQueue(label: "orbital.stream-proxy")
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16?
    private var streams: [String: ParallelStream] = [:]
    private var nextReader = 0
    /// Lo último que hizo cortar una respuesta (diagnóstico y pruebas).
    public private(set) var lastError: String?

    public init() {}

    /// Sirve `stream` y da la dirección local que se le pasa al reproductor (nil si el servidor no pudo arrancar: se lee directo).
    public func serve(_ stream: ParallelStream, name: String = "video") -> URL? {
        guard let port = startIfNeeded() else { return nil }
        let id = UUID().uuidString
        lock.withLock { streams[id] = stream }
        let safe = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "video"
        return URL(string: "http://127.0.0.1:\(port)/s/\(id)/\(safe)")
    }

    /// Se dejó de ver: se suelta (y se borra lo bajado).
    public func release(_ url: URL) {
        guard let id = Self.id(url.path) else { return }
        let stream = lock.withLock { streams.removeValue(forKey: id) }
        if let stream { Task { await stream.close() } }
    }

    public func stream(for url: URL) -> ParallelStream? { Self.id(url.path).flatMap { id in lock.withLock { streams[id] } } }

    static func id(_ path: String) -> String? {
        let parts = path.split(separator: "/")
        return parts.count >= 2 && parts[0] == "s" ? String(parts[1]) : nil
    }

    private func startIfNeeded() -> UInt16? {
        if let port = lock.withLock({ port }) { return port }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: parameters) else { return nil }
        let ready = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var failed = false
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: ready.signal()
            case .failed, .cancelled:
                failed = true; ready.signal()
                // iOS puede apagarlo en segundo plano: el siguiente video arranca otro (lo de ahora lo reabre el reproductor).
                self?.lock.withLock { if self?.listener === listener { self?.listener = nil; self?.port = nil } }
                listener.cancel()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 2) == .success, !failed, let port = listener.port?.rawValue else { listener.cancel(); return nil }
        lock.withLock { self.listener = listener; self.port = port }
        return port
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(connection, buffer: Data())
    }

    private func receiveHead(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 << 10) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let reader = self.lock.withLock { self.nextReader += 1; return self.nextReader }
                Task { await self.respond(connection, head: head, reader: reader) }
            } else if error != nil || complete || buffer.count > 32 << 10 {
                connection.cancel()
            } else {
                self.receiveHead(connection, buffer: buffer)
            }
        }
    }

    /// Un pedido del reproductor: «GET /s/<id>/video HTTP/1.1» con, quizá, «Range: bytes=a-b».
    func respond(_ connection: NWConnection, head: String, reader: Int) async {
        let request = Self.parse(head)
        guard let request, let stream = lock.withLock({ Self.id(request.path).flatMap { streams[$0] } }) else {
            await send(connection, Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
            connection.cancel(); return
        }
        do {
            let total = try await stream.size()
            guard let range = Self.byteRange(request.range, total: total) else {
                await send(connection, Data("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(total)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
                connection.cancel(); return
            }
            var header = request.range == nil ? "HTTP/1.1 200 OK\r\n" : "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(range.lowerBound)-\(range.upperBound)/\(total)\r\n"
            header += "Accept-Ranges: bytes\r\nContent-Type: application/octet-stream\r\nContent-Length: \(range.count)\r\nConnection: close\r\n\r\n"
            guard await send(connection, Data(header.utf8)) else { connection.cancel(); return }
            if request.method != "HEAD" {
                var at = range.lowerBound
                while at <= range.upperBound {
                    let piece = try await stream.read(offset: at, maxLength: range.upperBound - at + 1, reader: reader)
                    guard !piece.isEmpty, await send(connection, piece) else { break }
                    at += piece.count
                }
            }
        } catch {
            // Sin respuesta de Real-Debrid: se corta; el motor lo ve como un error de red y lo trata como siempre.
            lock.withLock { lastError = "\(error)" }
        }
        await stream.finished(reader: reader)
        connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    @discardableResult
    private func send(_ connection: NWConnection, _ data: Data) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            connection.send(content: data, completion: .contentProcessed { error in c.resume(returning: error == nil) })
        }
    }

    struct Request: Equatable { var method: String; var path: String; var range: String? }

    static func parse(_ head: String) -> Request? {
        let lines = head.components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ") ?? []
        guard first.count >= 2 else { return nil }
        let range = lines.dropFirst().first { $0.lowercased().hasPrefix("range:") }
            .map { String($0.dropFirst("range:".count)).trimmingCharacters(in: .whitespaces) }
        return Request(method: String(first[0]).uppercased(), path: String(first[1]), range: range)
    }

    /// «bytes=a-b», «bytes=a-» o «bytes=-n» (los últimos n) dentro de `total`; sin `Range`, todo.
    static func byteRange(_ header: String?, total: Int) -> ClosedRange<Int>? {
        guard total > 0 else { return nil }
        guard let header else { return 0...(total - 1) }
        guard header.lowercased().hasPrefix("bytes="), let spec = header.dropFirst(6).split(separator: ",").first else { return nil }
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let n = Int(parts[1]), n > 0 { return max(0, total - n)...(total - 1) }
        guard let start = Int(parts[0]), start < total else { return nil }
        let end = Int(parts[1]).map { min($0, total - 1) } ?? (total - 1)
        return start <= end ? start...end : nil
    }
}

extension ParallelStream {
    /// Lo de verdad: cada pedazo con `URLSession` y su `Range` (tiene que contestar 206, si no el origen no deja saltar y se
    /// lee directo). Los mismos encabezados que el reproductor mandaría.
    public static func urlSessionFetch(headers: [String: String], session: URLSession = ParallelStream.session) -> Fetch {
        { url, range in
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
            request.setValue("bytes=\(range.lowerBound)-\(range.upperBound)", forHTTPHeaderField: "Range")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.empty }
            guard http.statusCode == 206 else { throw Failure.refused(http.statusCode) }
            let total = (http.value(forHTTPHeaderField: "Content-Range")?.split(separator: "/").last).flatMap { Int($0) }
            return Piece(data: data, total: total, finalURL: http.url)
        }
    }

    public static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()
}
