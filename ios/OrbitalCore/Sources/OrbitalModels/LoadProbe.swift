import Foundation

/// Para la bitácora: cuánto de una carga es del servidor y cuánto del motor. Mientras el motor abre el video, pide aparte el
/// primer byte del mismo enlace y anota cuándo redirigió cada salto (Torrentio → Real-Debrid) y cuándo llegó el primer byte.
/// Solo nombres de servidor, nunca la dirección completa (lleva tu clave de Real-Debrid). No corre en las pruebas.
enum LoadProbe {
    private final class Hops: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let start = Date()
        private let lock = NSLock()
        private var hops: [String] = []
        var summary: String { lock.withLock { hops.joined(separator: " → ") } }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            let hop = String(format: "%@ a los %.1f s", request.url?.host ?? "?", Date().timeIntervalSince(start))
            lock.withLock { hops.append(hop) }
            return request
        }
    }

    static func start(_ url: URL) {
        guard url.scheme == "https" || url.scheme == "http", NSClassFromString("XCTestCase") == nil else { return }
        Task.detached(priority: .utility) {
            let hops = Hops()
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            let session = URLSession(configuration: .ephemeral)
            defer { session.finishTasksAndInvalidate() }
            do {
                let (_, response) = try await session.data(for: request, delegate: hops)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let route = hops.summary.isEmpty ? (url.host ?? "?") : "\(url.host ?? "?") → \(hops.summary)"
                PlayerModel.note(String(format: "servidor: %@; primer byte a los %.1f s (%d)", route, Date().timeIntervalSince(hops.start), status))
            } catch {
                PlayerModel.note(String(format: "servidor: no contestó en %.0f s (%@)", Date().timeIntervalSince(hops.start), hops.summary))
            }
        }
    }
}
