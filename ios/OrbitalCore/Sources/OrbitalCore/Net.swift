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
    public init(status: Int, data: Data) { self.status = status; self.data = data }
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
    /// Sesión efímera: no guarda en disco las respuestas (las direcciones de los complementos llevan tu clave de Real-Debrid).
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue("Orbital", forHTTPHeaderField: "User-Agent")
        for (key, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: key) }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            return HTTPResponse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
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
