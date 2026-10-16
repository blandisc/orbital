import Foundation

/// Lo que el widget «Lo siguiente para ti» necesita para pintarse sin red: hasta 3 elementos de «Seguir viendo» ya con sus
/// textos en el idioma de la app. La app lo escribe en el App Group cada vez que Inicio se actualiza o se cierra el reproductor;
/// el widget solo lo lee (nunca llama a la red). Las imágenes viven junto al archivo, ya reducidas (`imageFile`).
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        public var id: String { metaID }
        public var kind: String
        public var metaID: String
        public var videoID: String?
        public var title: String
        /// «T2 · E6» (vacío en una película).
        public var episodeLabel: String
        /// «quedan 20 min» o «Sigue: T3 · E1».
        public var status: String
        /// Avance 0…1 (nil: nada que mostrar, p. ej. el siguiente episodio sin empezar).
        public var progress: Double?
        /// El póster remoto de donde salió la imagen (la app lo baja y lo reduce; el widget no lo usa).
        public var poster: String?
        /// Nombre del archivo de la imagen reducida (JPEG, máx. `DesignTokens.Widget.maxImagePixels`), junto al snapshot.
        public var imageFile: String?
        /// Tono medio del arte, ya oscurecido como el fondo de las pantallas («#rrggbb»).
        public var tint: String?

        public init(kind: String, metaID: String, videoID: String? = nil, title: String, episodeLabel: String = "", status: String = "",
                    progress: Double? = nil, poster: String? = nil, imageFile: String? = nil, tint: String? = nil) {
            self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.title = title; self.episodeLabel = episodeLabel
            self.status = status; self.progress = progress; self.poster = poster; self.imageFile = imageFile; self.tint = tint
        }

        /// «T2 · E6 · quedan 20 min» (lo que hay, unido con « · »).
        public var detail: String { Vocabulary.factLine([episodeLabel, status]) }
        /// A dónde lleva tocarlo: reproduce donde ibas; sin episodio conocido, abre la ficha.
        public var link: URL? { videoID == nil ? WidgetLink.title(kind: kind, id: metaID) : WidgetLink.play(kind: kind, id: metaID, video: videoID) }
    }

    /// Lo que viene en el calendario (aún vacío: lo llena el calendario cuando exista, CEN-22). El widget mediano lo enseñará
    /// como «Próximo estreno» en el segundo renglón.
    public struct UpcomingEpisode: Codable, Equatable, Sendable {
        public var title: String
        /// «T3 E4».
        public var episodeLabel: String
        public var date: Date
        public init(title: String, episodeLabel: String, date: Date) { self.title = title; self.episodeLabel = episodeLabel; self.date = date }
    }

    public var generatedAt: Date
    /// Idioma de los textos del snapshot («es» | «en»): el widget lo usa también para sus propios textos.
    public var language: String
    public var items: [Item]
    public var upcoming: [UpcomingEpisode]?

    public static let maxItems = 3

    public init(generatedAt: Date = Date(), language: String = "es", items: [Item] = [], upcoming: [UpcomingEpisode]? = nil) {
        self.generatedAt = generatedAt; self.language = language; self.items = Array(items.prefix(Self.maxItems)); self.upcoming = upcoming
    }

    public static let empty = WidgetSnapshot()

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Un nombre de archivo seguro para la imagen de un título (los ids de Stremio traen «:»).
    public static func imageFileName(for metaID: String) -> String {
        let safe = metaID.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return "\(safe).jpg"
    }

    /// El tono del fondo a partir del color medio del arte (0…1): se mezcla con el grafito más profundo igual que el fondo de las
    /// pantallas (`ArtTint`), para que el widget y la app se vean del mismo tono.
    public static func tintHex(r: Double, g: Double, b: Double) -> String {
        let deep = rgb(hex: DesignTokens.palette["ink-1000"] ?? "#000000") ?? (r: 0, g: 0, b: 0)
        let by = DesignTokens.Widget.tintMix
        func mix(_ a: Double, _ d: Double) -> Int { Int(((a * (1 - by) + d * by) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", mix(r, deep.r), mix(g, deep.g), mix(b, deep.b))
    }
}

/// Los textos que lleva el snapshot, en el idioma de la app (la app los trae de su catálogo; por omisión, español).
public struct WidgetLabels: Sendable {
    public var episode: @Sendable (_ season: Int?, _ episode: Int) -> String
    public var timeLeft: @Sendable (_ minutes: Int) -> String
    public var nextUp: @Sendable (_ episodeLabel: String) -> String
    public init(episode: @escaping @Sendable (Int?, Int) -> String, timeLeft: @escaping @Sendable (Int) -> String, nextUp: @escaping @Sendable (String) -> String) {
        self.episode = episode; self.timeLeft = timeLeft; self.nextUp = nextUp
    }

    public static let spanish = WidgetLabels(
        episode: { season, episode in season.map { "T\($0) · E\(episode)" } ?? "E\(episode)" },
        timeLeft: { minutes in
            let (h, m) = Vocabulary.hoursAndMinutes(minutes)
            return h > 0 && m > 0 ? "quedan \(h) h \(m) min" : h > 0 ? "quedan \(h) h" : "quedan \(m) min"
        },
        nextUp: { "Sigue: \($0)" })
}

/// Los enlaces que abre el widget (esquema de la app, `orbital-ios://`): reproducir donde ibas o abrir la ficha.
public enum WidgetLink: Equatable, Sendable {
    case play(kind: String, id: String, video: String?)
    case title(kind: String, id: String)

    public static let scheme = "orbital-ios"

    public static func play(kind: String, id: String, video: String?) -> URL? {
        var items = [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "id", value: id)]
        if let video { items.append(URLQueryItem(name: "video", value: video)) }
        return url(host: "play", items)
    }

    public static func title(kind: String, id: String) -> URL? {
        url(host: "title", [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "id", value: id)])
    }

    private static func url(host: String, _ items: [URLQueryItem]) -> URL? {
        var parts = URLComponents(); parts.scheme = scheme; parts.host = host; parts.queryItems = items
        return parts.url
    }

    /// `orbital-ios://play?kind=&id=&video=` o `orbital-ios://title?kind=&id=`; cualquier otra cosa (el QR de la TV, Infuse) es nil.
    public static func parse(_ url: URL) -> WidgetLink? {
        guard url.scheme == scheme, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func value(_ name: String) -> String? { parts.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        guard let kind = value("kind"), let id = value("id") else { return nil }
        switch parts.host {
        case "play": return .play(kind: kind, id: id, video: value("video"))
        case "title": return .title(kind: kind, id: id)
        default: return nil
        }
    }
}
