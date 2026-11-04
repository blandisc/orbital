import Foundation

/// Lo que pediste para elegir versión: tu idioma (con su variante de español), «Tus idiomas» en orden, la calidad y este
/// aparato (qué se ve bien aquí).
public struct Preferences: Sendable, Equatable {
    public var audio: String      // idioma de audio preferido
    public var quality: String    // «4K», «1080p», «720p», «480p»
    /// Con audio en español: «es-419» (latino), «es-ES» (castellano) o "" (cualquiera).
    public var spanish: String
    /// El plan B en orden (T2 → R6): tus «Idiomas primero» de Torrentio como códigos («es-419», «es-ES», «ja»). Si no hay en
    /// el que quieres, se prueba el siguiente de esta lista antes que cualquier otro idioma.
    public var fallback: [String] = []
    /// «Tus idiomas» (N4-A, Fernando, 4 nov: «que sea fácil cambiar tus idiomas preferidos»): la lista entera de Ajustes, en
    /// orden, con «original» como un renglón más (`AppSettings.languages`). nil: el orden de siempre (con latino, latino →
    /// original → inglés → castellano; con otro idioma, solo el tuyo).
    public var languages: [String]?
    /// Este aparato (N5-A): lo que aquí no se ve bien pierde «Ver» contra lo que sí. Por omisión sin límites (la puntuación
    /// de la TV, `streams.score`); la app pone el suyo (`TitlePreferences.device`, `.apple`).
    public var device: PlaybackDevice = .anything
    public init(audio: String = "en", quality: String = "1080p", spanish: String = "") { self.audio = audio; self.quality = quality; self.spanish = spanish }
    /// El idioma que se busca, con su variante («es-419» si quieres latino).
    public var wanted: String { audio == "es" && !spanish.isEmpty ? spanish : audio }
    /// Lo que sigue después del que quieres, en orden. Fernando, 3 nov: latino → el idioma original de la obra («natal») →
    /// inglés → castellano: el orden por omisión con latino (es-MX). `original` es un renglón: el idioma original de cada
    /// título. Con «Tus idiomas», tu lista sin el que quieres (si en un título elegiste otro, el primero de tu lista queda
    /// en su lugar). Tus «Idiomas primero» de Torrentio (T2) se suman al final, sin repetir. Igual en la TV.
    public var order: [String] {
        let base = languages ?? (audio == "es" && spanish == "es-419" ? Self.latinOrder : [])
        var out: [String] = []
        for code in base + fallback where code != wanted && !out.contains(code) { out.append(code) }
        return out
    }
    public static let latinOrder = ["original", "en", "es-ES"]
}

/// N5-A (Fernando, 4 nov: «ve con tus sugerencias»): qué se ve bien en ESTE aparato. Una versión que aquí no se ve bien (muy
/// pesada para transmitirla o en un formato que el motor no abre) pierde «Ver» contra una que sí, aunque su idioma vaya antes
/// en tu orden; la ficha dice por qué en una línea. La regla es la misma en las dos apps (README de los escenarios comunes);
/// cada una pone lo que su aparato aguanta.
public struct PlaybackDevice: Sendable, Equatable {
    /// Lo más pesado que se ve bien, en GB, por resolución («4K», «1080p»…; "" para las demás), de una película.
    public var maxGB: [String: Double]
    /// Un episodio: esta parte de lo de una película.
    public var episodeShare: Double
    /// Lo que el motor no abre (etiquetas de `Source.tags` o `Source.hdr`: «3D», «AV1»…).
    public var cannotDecode: Set<String>

    public init(maxGB: [String: Double], episodeShare: Double = 0.3, cannotDecode: Set<String> = []) {
        self.maxGB = maxGB; self.episodeShare = episodeShare; self.cannotDecode = cannotDecode
    }

    /// iPhone, iPad y Mac: AetherEngine abre MKV, HEVC, HDR10, Dolby Vision y Atmos; lo que no se ve bien es lo muy pesado
    /// (un REMUX 4K de 64 GB se traba al transmitirlo).
    public static let apple = PlaybackDevice(maxGB: ["4K": 60, "1440p": 40, "1080p": 40, "": 20])
    /// Sin límites (para saber cuál habría ganado sin este aparato).
    public static let anything = PlaybackDevice(maxGB: ["": .infinity], episodeShare: 1)

    /// Por qué una versión no se ve bien aquí; nil si se ve bien.
    public func problem(_ src: Source, kind: String) -> PlaybackProblem? {
        if let format = src.tags.first(where: cannotDecode.contains) ?? src.hdr.first(where: cannotDecode.contains) { return .format(format) }
        let gb = Double(src.size) / 1e9
        let limit = (maxGB[src.resolution] ?? maxGB[""] ?? .infinity) * (kind == "movie" ? 1 : episodeShare)
        return gb > limit ? .heavy(gb: Int(gb.rounded())) : nil
    }
}

/// Por qué una versión no se ve bien en este aparato.
public enum PlaybackProblem: Equatable, Sendable {
    /// Pesa demasiado para transmitirla bien aquí («pesa 64 GB»).
    case heavy(gb: Int)
    /// Viene en un formato que el motor no abre («AV1»).
    case format(String)

    /// La llave de los escenarios comunes (`plays_poorly.why`).
    public var key: String { if case .heavy = self { "heavy" } else { "format" } }
}

extension Streams {
    /// Lo que pierde una versión que aquí no se ve bien (N5-A): más que lo que separa tu idioma del último renglón de tu
    /// orden (unos 850), menos que un idioma fuera de tu orden (−1600) y menos que arrancar al instante contra pedirla (1400):
    /// la que se ve bien gana dentro de tu orden; una que arranca ya sigue ganándole a una que hay que pedir.
    public static let poorFit = -900.0
}

/// N5-A: la versión de un idioma que va antes en tu orden y no ganó «Ver» porque aquí no se ve bien («La de inglés pesa
/// 64 GB y aquí no se ve bien»).
public struct PoorFit: Equatable, Sendable {
    public var source: Source
    /// El idioma en que sonaría («en»).
    public var language: String?
    public var problem: PlaybackProblem
}

extension Streams {
    /// ¿«Ver» pone otra porque la de un idioma que va antes en tu orden no se ve bien aquí? Solo cuenta lo que arranca igual
    /// (al instante contra al instante), nunca lo de cine, un tráiler, otro título u otro episodio, ni lo que Real-Debrid
    /// rechazó. nil si «Ver» ya es la de tu mejor idioma o si la mejor de ese idioma se ve bien aquí (perdió por otra cosa).
    public static func poorFit(_ ranked: [Source], playing: Source, prefs: Preferences, kind: String) -> PoorFit? {
        let mine = languageScore(playing, prefs)
        let playingCode = playingLanguage(playing, prefs)?.code
        let skip: Set<String> = ["CAM", "Tráiler", "3D", otherTitleTag, otherEpisodeTag]
        var anywhere = prefs
        anywhere.device = .anything
        let better = ranked.filter { s in
            s.index != playing.index && s.instant == playing.instant && !s.refused && !s.otherTitle && skip.isDisjoint(with: s.tags)
                && languageScore(s, prefs) > mine && playingLanguage(s, prefs)?.code != playingCode
        }
        // La mejor de tu mejor idioma (sin este aparato): si esa se ve bien aquí, perdió por otra cosa y no se dice nada.
        let rank = { (s: Source) in (languageScore(s, prefs), score(s, prefs: anywhere, kind: kind)) }
        guard let best = better.max(by: { rank($0) < rank($1) }), let problem = prefs.device.problem(best, kind: kind) else { return nil }
        return PoorFit(source: best, language: playingLanguage(best, prefs)?.code, problem: problem)
    }
}
