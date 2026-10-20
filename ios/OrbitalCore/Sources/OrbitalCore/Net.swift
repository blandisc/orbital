import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Una petición HTTP mínima. Todo el paquete habla con la red a través de `HTTPClient`, así las pruebas
/// responden con datos guardados y la app usa `URLSession`.
public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: String = "GET"
    public var headers: [String: String] = [:]
    public var body: Data?
    public var timeout: TimeInterval = 15

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 15) {
        self.url = url; self.method = method; self.headers = headers; self.body = body; self.timeout = timeout
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var data: Data
    /// Encabezados, con el nombre en minúsculas («content-range»).
    public var headers: [String: String]
    public init(status: Int, data: Data, headers: [String: String] = [:]) { self.status = status; self.data = data; self.headers = headers }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Fallo de red (sin conexión, tiempo agotado, servidor caído): no es que tus datos estén mal.
public struct NetworkError: Error, Sendable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    static let maxBody = 16 * 1024 * 1024      // como Orbital: 16 MB
    /// Sesión efímera: no guarda en disco las respuestas (las direcciones de los complementos llevan tu clave de Real-Debrid).
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    /// Para servicios públicos sin claves en la dirección (Cinemeta): respeta lo que el servidor deja guardar, en disco.
    public static func publicCache(_ name: String, megabytes: Int = 40) -> URLSessionHTTPClient {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: megabytes << 20, directory: FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent(name, isDirectory: true))
        config.requestCachePolicy = .useProtocolCachePolicy
        return URLSessionHTTPClient(session: URLSession(configuration: config))
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("Orbital", forHTTPHeaderField: "User-Agent")
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        do {
            // Plazo total (no solo de inactividad) y tope de tamaño: un complemento que gotea bytes o manda gigas no cuelga la app.
            let deadline = request.timeout * 2
            let session = self.session, urlRequest = urlRequest
            return try await withThrowingTaskGroup(of: HTTPResponse.self) { group in
                group.addTask {
                    // De un jalón (antes byte por byte: un `await` por byte hacía lenta cada respuesta grande, como la biblioteca
                    // de Stremio). El tope de tamaño se revisa con lo que anuncia el servidor y con lo que llegó; el plazo total
                    // de abajo sigue cortando a uno que gotea.
                    let (data, response) = try await session.data(for: urlRequest)
                    if response.expectedContentLength > Int64(URLSessionHTTPClient.maxBody) { throw NetworkError("La respuesta es demasiado grande") }
                    guard data.count <= URLSessionHTTPClient.maxBody else { throw NetworkError("La respuesta es demasiado grande") }
                    let http = response as? HTTPURLResponse
                    var headers: [String: String] = [:]
                    for (key, value) in http?.allHeaderFields ?? [:] { if let k = key as? String, let v = value as? String { headers[k.lowercased()] = v } }
                    return HTTPResponse(status: http?.statusCode ?? 0, data: data, headers: headers)
                }
                group.addTask { try await Task.sleep(nanoseconds: UInt64(deadline * 1e9)); throw NetworkError("Tiempo agotado") }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError("\(error.localizedDescription)")
        }
    }
}

extension HTTPClient {
    /// GET que devuelve un JSON cualquiera (`nil` si no es JSON); lanza `NetworkError` si la red falla o hay HTTP ≥ 400.
    public func getJSON(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 15) async throws -> JSON? {
        let response = try await send(HTTPRequest(url: url, headers: headers, timeout: timeout))
        guard response.status < 400 else { throw NetworkError("HTTP \(response.status)") }
        return JSON.parse(response.data)
    }
}

/// Para los registros: solo el servidor. La ruta de un complemento lleva tus claves (Real-Debrid en Torrentio).
public func redact(_ url: String) -> String {
    var rest = url
    if let scheme = rest.range(of: "://") { rest = String(rest[scheme.upperBound...]) }       // solo después del PRIMER «://»
    rest = String(rest.prefix { !"/?#".contains($0) })                                          // sin ruta, consulta ni fragmento
    if let at = rest.lastIndex(of: "@") { rest = String(rest[rest.index(after: at)...]) }       // sin usuario:clave@
    return rest.isEmpty ? "?" : rest
}

/// Quita las direcciones (con sus claves) de un mensaje de error antes de mostrarlo.
public func stripURLs(_ message: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z0-9+.\-]*://\S+"#) else { return message }
    return regex.stringByReplacingMatches(in: message, range: NSRange(message.startIndex..., in: message), withTemplate: "(enlace oculto)")
}

/// `encodeURIComponent` de JavaScript: lo que acepta un segmento de ruta sin escapar.
public func uriComponent(_ text: String, safe extra: String = "") -> String {
    var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    allowed.insert(charactersIn: extra)
    return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
}
