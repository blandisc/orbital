import Foundation

/// Dónde están la intro, el resumen y los créditos de un episodio o película (en segundos), marcados por la comunidad.
public struct SkipSegments: Sendable, Equatable {
    public var intro: ClosedRange<Double>?
    public var recap: ClosedRange<Double>?
    public var credits: ClosedRange<Double>?
    public init(intro: ClosedRange<Double>? = nil, recap: ClosedRange<Double>? = nil, credits: ClosedRange<Double>? = nil) {
        self.intro = intro; self.recap = recap; self.credits = credits
    }
    public var isEmpty: Bool { intro == nil && recap == nil && credits == nil }
}

/// IntroDB (introdb.app, la misma que usa Infuse): marcas de la comunidad para saltar la intro y el resumen y llegar a los
/// créditos. Se lee sin clave, por id de IMDb (y temporada y episodio en series).
public struct IntroDB: Sendable {
    public static let api = "https://api.introdb.app"
    let http: HTTPClient
    public init(http: HTTPClient) { self.http = http }

    /// Las marcas de un video (`tt0944947:1:1` o `tt0133093`); nil sin id de IMDb, sin red o sin marcas.
    public func segments(videoID: String) async -> SkipSegments? {
        let parts = videoID.split(separator: ":").map(String.init)
        guard let imdb = parts.first, imdb.range(of: #"^tt[0-9]{7,9}$"#, options: .regularExpression) != nil else { return nil }
        var components = URLComponents(string: Self.api + "/segments")!
        components.queryItems = [URLQueryItem(name: "imdb_id", value: imdb)]
        if parts.count >= 3 { components.queryItems! += [URLQueryItem(name: "season", value: parts[1]), URLQueryItem(name: "episode", value: parts[2])] }
        else { components.queryItems!.append(URLQueryItem(name: "is_movie", value: "true")) }
        guard let url = components.url,
              let response = try? await http.send(HTTPRequest(url: url, timeout: 6)), response.status == 200,
              let json = JSON.parse(response.data) else { return nil }
        let found = Self.parse(json)
        return found.isEmpty ? nil : found
    }

    /// `{intro: {start_sec, end_sec}, recap: …, outro: …}`; un tramo vacío o al revés no cuenta.
    static func parse(_ json: JSON) -> SkipSegments {
        func range(_ key: String) -> ClosedRange<Double>? {
            guard let start = json[key]?["start_sec"]?.doubleValue, let end = json[key]?["end_sec"]?.doubleValue, end > start else { return nil }
            return start...end
        }
        return SkipSegments(intro: range("intro"), recap: range("recap"), credits: range("outro"))
    }
}
