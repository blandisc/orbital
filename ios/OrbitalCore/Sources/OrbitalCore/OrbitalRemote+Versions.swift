import Foundation

extension OrbitalRemote {
    /// Lo enfocado en la TV (CT-A, Fernando, 26 nov 2026): la tarjeta de arriba del pad en el control del iPhone.
    public struct Focus: Sendable, Equatable {
        public var title: String, image: String?, kind: String?, imdb: String?, detail: String?, watchable: Bool
        public init(title: String, image: String? = nil, kind: String? = nil, imdb: String? = nil, detail: String? = nil, watchable: Bool = false) {
            self.title = title; self.image = image; self.kind = kind; self.imdb = imdb; self.detail = detail; self.watchable = watchable
        }
        /// El póster: el de la TV o, si no manda uno, el de metahub por su IMDb.
        public var art: String? { image ?? imdb.map { String(format: ForYou.metahubPoster, $0) } }
        static func parse(_ json: JSON?, base: URL?) -> Focus? {
            guard let json, let title = json["title"]?.nonEmptyString else { return nil }
            var image = json["image"]?.nonEmptyString
            if let s = image, s.hasPrefix("/"), let base { image = URL(string: s, relativeTo: base)?.absoluteString ?? s }
            return Focus(title: title, image: image, kind: json["kind"]?.nonEmptyString, imdb: json["id"]?.nonEmptyString,
                         detail: json["detail"]?.nonEmptyString, watchable: json["watchable"]?.bool ?? false)
        }
    }

    /// Una versión que tiene la TV para lo que se ve (IV-A «Cómo lo ves»): sin URLs; `key` es su huella para pedirla.
    public struct Version: Sendable, Equatable, Identifiable {
        public var key: String, resolution: String, hdr: Bool, size: String, instant: Bool, languages: [String], audio: String, dub: Bool
        public var id: String { key }
        public init(key: String, resolution: String, hdr: Bool = false, size: String = "", instant: Bool = false, languages: [String] = [],
                    audio: String = "", dub: Bool = false) {
            self.key = key; self.resolution = resolution; self.hdr = hdr; self.size = size; self.instant = instant
            self.languages = languages; self.audio = audio; self.dub = dub
        }
        static func parse(_ json: JSON) -> Version? {
            guard let key = json["key"]?.nonEmptyString, json["requested"]?.bool != true else { return nil }
            let cached = json["cached"]?.bool ?? false, debrid = json["debrid"]?.bool ?? false
            return Version(key: key, resolution: json["resolution"]?.nonEmptyString ?? "", hdr: json["hdr"]?.bool ?? false,
                           size: json["size"]?.nonEmptyString ?? "", instant: cached || !debrid,
                           languages: (json["languages"]?.array ?? []).compactMap(\.nonEmptyString),
                           audio: json["audio"]?.nonEmptyString ?? "", dub: json["dub"]?.bool ?? false)
        }
    }

    /// Las versiones que encuentra la TV, en el orden de tus preferencias (la primera es la que pondría «Ver»). Solo las
    /// que arrancan sin pedirse (lo que hay que pedir no sirve a media película). Una TV de antes (sin `key`): lista vacía.
    public func versions(kind: String, metaID: String, videoID: String?) async throws -> [Version] {
        var query = [URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "id", value: metaID)]
        if let videoID, videoID != metaID { query.append(URLQueryItem(name: "video", value: videoID)) }
        let json = try await send("api/stremio/sources", method: "GET", query: query, body: nil, timeout: 45)
        var seen = Set<String>()
        return (json?["sources"]?.array ?? []).compactMap(Version.parse).filter { $0.instant && seen.insert($0.key).inserted }
    }

    /// Pone otra versión en la TV en el mismo minuto (IV-A).
    public func switchVersion(_ version: Version, now: NowPlaying, at position: Double) async throws {
        guard let meta = now.metaID else { return }
        let choice = ResumeChoice(videoID: now.videoID ?? meta, source: version.key)
        try await play(kind: now.kind, metaID: meta, videoID: now.videoID, title: now.title, position: position, choice: choice)
    }
}

/// IV-B (Fernando, 26 nov 2026): un toque en las teclas de idioma y subtítulos del control cambia a lo siguiente más
/// probable, sin abrir nada. Mantener abre la hoja «Cómo lo ves» con todo.
public enum TrackCycle {
    /// El audio que sigue al puesto (vuelve al primero al final). nil: no hay otro.
    public static func nextAudio(_ tracks: [OrbitalRemote.NowPlaying.Track]) -> String? {
        guard tracks.count > 1 else { return nil }
        let i = tracks.firstIndex(where: \.selected) ?? -1
        return tracks[(i + 1) % tracks.count].id
    }
    /// Con subtítulos puestos, «no»; sin ellos, los de tu idioma (español primero) o, si no hay, los primeros. nil: no hay.
    public static func toggleSubtitles(_ tracks: [OrbitalRemote.NowPlaying.Track], language: String = "es") -> String? {
        if tracks.contains(where: \.selected) { return "no" }
        let words = language == "en" ? ["english", "inglés", "eng", "en"] : ["español", "spanish", "spa", "es", "latino"]
        let mine = tracks.first { t in let l = t.label.lowercased(); return words.contains { l.hasPrefix($0) || l.contains(" \($0)") } }
        return (mine ?? tracks.first)?.id
    }

    /// El nombre de una pista en una palabra, para la tecla del control: así no se parte en dos renglones y los íconos de la
    /// fila quedan a la misma altura (26 nov 2026). «Español latino» → «Latino», «Español (España)» → «Castellano»,
    /// «Inglés 5.1 · SDH» → «Inglés». El nombre completo va en «Cómo lo ves».
    public static func short(_ label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("latino") || lower.contains("latin") { return "Latino" }
        if lower.contains("españa") || lower.contains("castellano") || lower.contains("spain") { return "Castellano" }
        let first = label.split(whereSeparator: { "·(,[-".contains($0) }).first.map(String.init) ?? label
        return (first.split(separator: " ").first.map(String.init) ?? first).trimmingCharacters(in: .whitespaces)
    }
}
