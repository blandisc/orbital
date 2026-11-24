import Foundation

/// Arranque rápido (23 nov 2026): la dirección final de un enlace que redirige. El de Torrentio (con Real-Debrid o TorBox)
/// no es el video: al pedirlo, Torrentio le pregunta a la nube y contesta «está allá» (una redirección). Ese saludo (la
/// conexión segura con Torrentio más lo que tarda en preguntarle a la nube) se pagaba al dar «Ver», antes del primer byte.
///
/// Aquí se resuelve antes: al abrir la ficha (`StreamWarmup`) y, en el reproductor, en cuanto se elige la versión (a la par
/// de «dónde ibas»). Solo se lee la redirección: la petición se corta ahí y nunca abre el archivo en la nube (Real-Debrid
/// no aguanta dos conexiones al mismo archivo). El motor abre luego la dirección final directo.
///
/// Cada dirección resuelta sirve UNA vez y dura `lifetime`: un reintento, otra versión o volver de segundo plano pasan por
/// el complemento como siempre (si la nube cambió algo, el complemento lo sabe). Si la dirección final no abre, el
/// reproductor vuelve a la del complemento (`PlayerModel.loadVideo`).
public final class StreamLinks: @unchecked Sendable {
    public typealias Resolve = @Sendable (URL) async -> URL?
    /// La de la app: apagada hasta que la app la prende (`enable`), así las pruebas nunca salen a la red.
    public static let shared = StreamLinks()
    /// Lo que se confía en una dirección resuelta (los enlaces de la nube duran horas; la lista de versiones, 10 min).
    public static let lifetime: TimeInterval = StreamFinder.cacheSeconds
    /// Lo más que «Ver» espera una resolución que ya va en camino; más que eso, abre con el enlace del complemento.
    public static let joinWait: TimeInterval = 4
    static let most = 100

    private let lock = NSLock()
    private var resolver: Resolve?
    private let clock: @Sendable () -> Date
    private var resolved: [String: (url: URL, at: Date)] = [:]
    private var pending: [String: Task<URL?, Never>] = [:]

    public init(resolver: Resolve? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.resolver = resolver; self.clock = clock
    }

    /// La app la prende al arrancar (con la red de verdad).
    public func enable(_ resolver: @escaping Resolve = RedirectProbe.resolve) { lock.withLock { self.resolver = resolver } }

    /// Qué enlaces vale la pena resolver: los de un complemento que redirige a la nube (`/resolve/`, `/playback/`), por la
    /// red, sin datos extra (esos se mandan solo al servidor del complemento) y que no sean listas HLS.
    public static func worthResolving(_ url: URL, headers: [String: String]) -> Bool {
        guard url.scheme == "https" || url.scheme == "http", headers.isEmpty else { return false }
        let path = url.path.lowercased()
        guard !path.hasSuffix(".m3u8"), !path.hasSuffix(".m3u") else { return false }
        return path.contains("/resolve/") || path.contains("/playback/")
    }

    /// Empieza a resolver (o se une a lo que ya va en camino). nil: no se resuelve (apagada, no vale la pena).
    @discardableResult
    public func start(_ url: URL) -> Task<URL?, Never>? {
        guard Self.worthResolving(url, headers: PlaybackHeaders.headers(for: url)) else { return nil }
        let key = url.absoluteString, now = clock()
        return lock.withLock { () -> Task<URL?, Never>? in
            guard let resolver else { return nil }
            if let hit = resolved[key], now.timeIntervalSince(hit.at) < Self.lifetime { let found = hit.url; return Task { found } }
            if let running = pending[key] { return running }
            let task = Task<URL?, Never> { [weak self] in
                let found = await resolver(url)
                self?.finish(key, original: url, found: found)
                return found
            }
            pending[key] = task
            return task
        }
    }

    private func finish(_ key: String, original: URL, found: URL?) {
        let now = clock()
        lock.withLock {
            pending[key] = nil
            guard let found, found != original else { return }
            if resolved.count >= Self.most { resolved = resolved.filter { now.timeIntervalSince($0.value.at) < Self.lifetime } }
            if resolved.count >= Self.most { resolved.removeAll() }
            resolved[key] = (found, now)
        }
    }

    /// Lo que se abre al dar «Ver»: la dirección final si ya se sabe (y se gasta), si va en camino se espera hasta
    /// `joinWait`; si no, el mismo enlace. Nunca empieza una resolución nueva (eso es `start`).
    public func playable(_ url: URL) async -> (url: URL, how: Outcome) {
        let key = url.absoluteString, now = clock()
        let (hit, running): (URL?, Task<URL?, Never>?) = lock.withLock {
            if let hit = resolved.removeValue(forKey: key) { return (now.timeIntervalSince(hit.at) < Self.lifetime ? hit.url : nil, nil) }
            return (nil, pending[key])
        }
        if let hit { return (hit, .ready) }
        guard let running else { return (url, .none) }
        let found = await Deadline.within(Self.joinWait, or: nil) { await running.value }
        guard let found, found != url else { return (url, .none) }
        lock.withLock { _ = resolved.removeValue(forKey: key) }   // se gasta: la siguiente carga pasa por el complemento
        return (found, .joined)
    }

    /// Cómo se llegó a la dirección (para la bitácora del arranque).
    public enum Outcome: String, Sendable { case ready = "ya resuelta", joined = "resuelta al abrir", none = "la del complemento" }

    /// Lo resuelto de este enlace ya no sirve (no abrió).
    public func forget(_ url: URL) { lock.withLock { _ = resolved.removeValue(forKey: url.absoluteString) } }
}

/// Lee a dónde redirige un enlace sin seguirlo: un GET de un byte que se corta en la redirección (no abre el archivo).
public enum RedirectProbe {
    static let timeout: TimeInterval = 8
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    /// La red de verdad, como valor (un cierre asíncrono escrito como valor por omisión se compilaba mal en la CI).
    public static let resolve: StreamLinks.Resolve = { await location(of: $0) }

    public static func location(of url: URL) async -> URL? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let stop = StopAtRedirect()
        guard let (_, response) = try? await session.data(for: request, delegate: stop) else { return nil }
        if let next = stop.next { return target(next, from: url) }
        guard let http = response as? HTTPURLResponse, (300..<400).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location") else { return nil }
        return URL(string: location, relativeTo: url).flatMap { target($0.absoluteURL, from: url) }
    }

    /// Solo direcciones de la red, y no la misma.
    static func target(_ next: URL, from url: URL) -> URL? {
        guard next.scheme == "https" || next.scheme == "http", next != url else { return nil }
        return next
    }

    private final class StopAtRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var _next: URL?
        var next: URL? { lock.withLock { _next } }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            lock.withLock { _next = request.url }
            completionHandler(nil)   // no se sigue: la respuesta es la redirección, sin bytes del video
        }
    }
}
