import Foundation

// La ficha rica (como Infuse): elenco con foto, dirección y guion, clasificación por edad, calificación de TMDB, tráiler y
// extras, «Más como esto», la saga, dónde verlo y la cadena o el estudio. Todo sale de TMDB en una sola petición
// (`append_to_response`), más la saga si la hay.

/// Un título de TMDB (recomendación, parte de una saga, crédito de una persona): se abre resolviendo su id de IMDb al tocarlo.
public struct TmdbTitle: Sendable, Equatable, Identifiable, Hashable {
    public var tmdbID: Int
    public var kind: String          // «movie» o «series»
    public var title: String
    public var poster: String?
    public var year: Int?
    public var role: String?         // en la filmografía de una persona: su personaje o su trabajo
    public var id: String { "\(kind):\(tmdbID)" }
    public init(tmdbID: Int, kind: String, title: String, poster: String? = nil, year: Int? = nil, role: String? = nil) {
        self.tmdbID = tmdbID; self.kind = kind; self.title = title; self.poster = poster; self.year = year; self.role = role
    }
}

public struct CastMember: Sendable, Equatable, Identifiable, Hashable {
    public var personID: Int
    public var name: String
    public var role: String          // personaje (reparto) o trabajo (dirección, guion)
    public var photo: String?
    public var id: String { "\(personID):\(role)" }
    public init(personID: Int, name: String, role: String, photo: String?) { self.personID = personID; self.name = name; self.role = role; self.photo = photo }
}

/// Un video de YouTube: tráiler, avance, detrás de cámaras…
public struct VideoClip: Sendable, Equatable, Identifiable {
    public var key: String
    public var name: String
    public var type: String          // «Trailer», «Teaser», «Featurette», «Behind the Scenes», «Clip»
    public var id: String { key }
    public var url: URL? { URL(string: "https://www.youtube.com/watch?v=\(key)") }
    public var thumbnail: String { "https://img.youtube.com/vi/\(key)/hqdefault.jpg" }
}

public struct Brand: Sendable, Equatable, Identifiable, Hashable {
    public var name: String
    public var logo: String?
    public var id: String { name }
}

public struct TitleExtras: Sendable, Equatable {
    public var tmdbID: Int
    public var cast: [CastMember] = []
    public var crew: [CastMember] = []          // dirección, creación y guion
    public var certification: String?           // «B15», «PG-13», «TV-MA»
    public var rating: Double?                  // TMDB, de 0 a 10
    public var votes = 0
    public var trailer: VideoClip?
    public var extras: [VideoClip] = []
    public var recommendations: [TmdbTitle] = []
    public var collection: (name: String, parts: [TmdbTitle])?
    public var providers: [Brand] = []          // dónde verlo en tu país (suscripción)
    public var studios: [Brand] = []            // la cadena (series) o el estudio (películas)
    /// La frase de la película («Long live the fighters.»), en tu idioma si TMDB la tiene.
    public var tagline: String?
    /// El estreno (película) o el primer episodio (serie), «2024-03-01».
    public var releaseDate: String?
    /// Los idiomas que se hablan (códigos ISO 639-1: «en», «es»).
    public var languages: [String] = []

    public static func == (a: TitleExtras, b: TitleExtras) -> Bool {
        a.tmdbID == b.tmdbID && a.cast == b.cast && a.crew == b.crew && a.certification == b.certification && a.rating == b.rating
            && a.trailer == b.trailer && a.extras == b.extras && a.recommendations == b.recommendations && a.collection?.name == b.collection?.name
            && a.collection?.parts == b.collection?.parts && a.providers == b.providers && a.studios == b.studios
            && a.tagline == b.tagline && a.releaseDate == b.releaseDate && a.languages == b.languages
    }
}

/// Una persona (al tocar su foto): foto, biografía y su trabajo, lo más conocido primero.
public struct PersonDetails: Sendable, Equatable {
    public var id: Int
    public var name: String
    public var photo: String?
    public var biography: String
    public var born: String?
    public var place: String?
    public var credits: [TmdbTitle]
}

extension Tmdb {
    /// Todo lo de la ficha rica, en una petición (y la saga, si la hay, en otra).
    public func extras(kind: String, tmdbID: Int, region: String) async throws -> TitleExtras {
        let path = "/\(Tmdb.kinds[kind] ?? "movie")/\(tmdbID)"
        let rating = kind == "movie" ? "release_dates" : "content_ratings"
        let raw = try await get(path, [("append_to_response", "credits,\(rating),videos,recommendations,watch/providers"),
                                       ("include_video_language", "es,en,null")])
        var out = Tmdb.parseExtras(raw, kind: kind, region: region)
        if let id = raw["belongs_to_collection"]?["id"]?.intValue, let collection = try? await get("/collection/\(id)") {
            let parts = (collection["parts"]?.array ?? []).compactMap { Tmdb.title($0, kind: "movie") }
                .sorted { ($0.year ?? .max) < ($1.year ?? .max) }
            if parts.count > 1 { out.collection = (collection["name"]?.string ?? "", parts) }
        }
        return out
    }

    /// Una persona y lo que ha hecho (películas y series), lo más popular primero y sin repetir.
    public func person(_ id: Int) async throws -> PersonDetails {
        let raw = try await get("/person/\(id)", [("append_to_response", "combined_credits")])
        return Tmdb.parsePerson(raw)
    }

    static func title(_ j: JSON, kind fixed: String? = nil) -> TmdbTitle? {
        guard let id = j["id"]?.intValue else { return nil }
        let media = j["media_type"]?.string
        let kind = fixed ?? (media == "tv" ? "series" : media == "movie" ? "movie" : nil)
        guard let kind else { return nil }
        let name = (j["title"]?.nonEmptyString ?? j["name"]?.nonEmptyString ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let date = j["release_date"]?.string ?? j["first_air_date"]?.string ?? ""
        return TmdbTitle(tmdbID: id, kind: kind, title: name, poster: image(j["poster_path"], size: "w342"), year: date.count >= 4 ? Int(date.prefix(4)) : nil)
    }

    /// La clasificación de tu país; si no la tiene, la de EE. UU.
    static func certification(_ raw: JSON, kind: String, region: String) -> String? {
        func pick(_ country: String) -> String? {
            if kind == "movie" {
                let rows = raw["release_dates"]?["results"]?.array?.first { $0["iso_3166_1"]?.string == country }?["release_dates"]?.array ?? []
                return rows.compactMap { $0["certification"]?.nonEmptyString }.first
            }
            return raw["content_ratings"]?["results"]?.array?.first { $0["iso_3166_1"]?.string == country }?["rating"]?.nonEmptyString
        }
        return pick(region) ?? pick("US")
    }

    static func parseExtras(_ raw: JSON, kind: String, region: String) -> TitleExtras {
        var out = TitleExtras(tmdbID: raw["id"]?.intValue ?? 0)
        out.cast = (raw["credits"]?["cast"]?.array ?? []).prefix(20).compactMap { c in
            guard let id = c["id"]?.intValue, let name = c["name"]?.nonEmptyString else { return nil }
            return CastMember(personID: id, name: name, role: c["character"]?.string ?? "", photo: image(c["profile_path"], size: "w185"))
        }
        // Dirección y guion (películas); en series, quien la creó primero.
        var crew: [CastMember] = (raw["created_by"]?.array ?? []).compactMap { c in
            guard let id = c["id"]?.intValue, let name = c["name"]?.nonEmptyString else { return nil }
            return CastMember(personID: id, name: name, role: "Creator", photo: image(c["profile_path"], size: "w185"))
        }
        let jobs = ["Director", "Screenplay", "Writer", "Novel"]
        for job in jobs {
            for c in raw["credits"]?["crew"]?.array ?? [] where c["job"]?.string == job {
                guard let id = c["id"]?.intValue, let name = c["name"]?.nonEmptyString, !crew.contains(where: { $0.personID == id }) else { continue }
                crew.append(CastMember(personID: id, name: name, role: job, photo: image(c["profile_path"], size: "w185")))
            }
        }
        out.crew = Array(crew.prefix(6))
        out.certification = certification(raw, kind: kind, region: region)
        if let v = raw["vote_average"]?.doubleValue, v > 0 { out.rating = v }
        out.votes = raw["vote_count"]?.intValue ?? 0
        let clips: [VideoClip] = (raw["videos"]?["results"]?.array ?? []).compactMap { v in
            guard v["site"]?.string == "YouTube", let key = v["key"]?.nonEmptyString else { return nil }
            return VideoClip(key: key, name: v["name"]?.string ?? "", type: v["type"]?.string ?? "")
        }
        // El tráiler oficial primero (en tu idioma si lo hay: TMDB los manda en el orden pedido); los demás, extras.
        out.trailer = clips.first { $0.type == "Trailer" } ?? clips.first { $0.type == "Teaser" }
        out.extras = clips.filter { $0 != out.trailer && ["Teaser", "Trailer", "Featurette", "Behind the Scenes", "Clip"].contains($0.type) }.prefix(10).map { $0 }
        out.recommendations = (raw["recommendations"]?["results"]?.array ?? []).compactMap { title($0, kind: kind) }.prefix(15).map { $0 }
        let providers = raw["watch/providers"]?["results"]?[region]?["flatrate"]?.array ?? []
        out.providers = providers.compactMap { p in p["provider_name"]?.nonEmptyString.map { Brand(name: $0, logo: image(p["logo_path"], size: "w154")) } }
        let studios = raw["networks"]?.array ?? raw["production_companies"]?.array ?? []
        out.studios = studios.prefix(3).compactMap { s in s["name"]?.nonEmptyString.map { Brand(name: $0, logo: image(s["logo_path"], size: "w154")) } }
        out.tagline = raw["tagline"]?.nonEmptyString?.trimmingCharacters(in: .whitespacesAndNewlines)
        out.releaseDate = (raw["release_date"]?.nonEmptyString ?? raw["first_air_date"]?.nonEmptyString)
        out.languages = (raw["spoken_languages"]?.array ?? []).compactMap { $0["iso_639_1"]?.nonEmptyString }
        return out
    }

    static func parsePerson(_ raw: JSON) -> PersonDetails {
        var seen = Set<String>()
        let cast = (raw["combined_credits"]?["cast"]?.array ?? []).map { ($0, $0["character"]?.string) }
        let crew = (raw["combined_credits"]?["crew"]?.array ?? []).map { ($0, $0["job"]?.string) }
        let ranked = (cast + crew).sorted { ($0.0["popularity"]?.doubleValue ?? 0) > ($1.0["popularity"]?.doubleValue ?? 0) }
        let credits: [TmdbTitle] = ranked.compactMap { pair in
            guard var t = title(pair.0), t.poster != nil, seen.insert(t.id).inserted else { return nil }
            t.role = pair.1.flatMap { $0.isEmpty ? nil : $0 }
            return t
        }
        return PersonDetails(id: raw["id"]?.intValue ?? 0, name: raw["name"]?.string ?? "", photo: image(raw["profile_path"], size: "h632"),
                             biography: (raw["biography"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                             born: raw["birthday"]?.nonEmptyString, place: raw["place_of_birth"]?.nonEmptyString, credits: Array(credits.prefix(40)))
    }
}
