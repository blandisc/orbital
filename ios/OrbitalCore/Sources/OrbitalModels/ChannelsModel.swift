import Foundation
import OrbitalCore

/// Canales de Inicio (docs/producto/inicio-benchmark/): las series que eliges, cada una siempre al aire con un episodio al
/// azar (`ChannelSchedule`), con la imagen y el nombre de ese capítulo (Cinemeta). Lo que eliges se guarda en el teléfono;
/// la primera vez hay unos canales de arranque. Se añade una serie buscándola o de las sugeridas.
@MainActor
public final class ChannelsModel: ObservableModel {
    /// Una serie elegida (lo que se guarda).
    public struct Pick: Codable, Sendable, Equatable, Identifiable {
        public var id: String, title: String, poster: String
        public init(id: String, title: String, poster: String) { self.id = id; self.title = title; self.poster = poster }
    }

    /// Un canal listo para pintar: la serie, su logo, sus episodios y cuánto dura cada uno.
    public struct Channel: Sendable, Equatable, Identifiable {
        public var pick: Pick
        public var logo: String?
        public var background: String
        public var episodes: [ChannelSchedule.Episode]
        public var length: TimeInterval
        public var id: String { pick.id }
        /// Lo que está al aire a esta hora.
        public func onAir(at now: Date) -> ChannelSchedule.OnAir? {
            ChannelSchedule.onAir(seriesID: pick.id, episodes: episodes, length: length, now: now)
        }
    }

    /// Los canales de arranque (antes de elegir) y las sugeridas para añadir.
    public nonisolated static let starters: [Pick] = [
        Pick(id: "tt0096697", title: "Los Simpson", poster: poster("tt0096697")),
        Pick(id: "tt0386676", title: "The Office", poster: poster("tt0386676")),
        Pick(id: "tt0108778", title: "Friends", poster: poster("tt0108778")),
        Pick(id: "tt0098904", title: "Seinfeld", poster: poster("tt0098904")),
        Pick(id: "tt0149460", title: "Futurama", poster: poster("tt0149460")),
    ]
    public nonisolated static let suggested: [Pick] = [
        Pick(id: "tt0903747", title: "Breaking Bad", poster: poster("tt0903747")),
        Pick(id: "tt0212671", title: "Malcolm", poster: poster("tt0212671")),
        Pick(id: "tt2467372", title: "Brooklyn Nine-Nine", poster: poster("tt2467372")),
        Pick(id: "tt10986410", title: "Ted Lasso", poster: poster("tt10986410")),
        Pick(id: "tt0118480", title: "Stargate SG-1", poster: poster("tt0118480")),
        Pick(id: "tt14452776", title: "The Bear", poster: poster("tt14452776")),
    ]
    nonisolated static func poster(_ id: String) -> String { String(format: ForYou.metahubPoster, id) }
    static let key = "home-channels"
    /// Si Cinemeta no dice cuánto dura un episodio.
    nonisolated static let defaultMinutes = 22

    /// Las series elegidas, en su orden.
    public private(set) var picks: [Pick] { didSet { if picks != oldValue { changed() } } }
    /// Las que ya se trajeron (en el orden de `picks`).
    public private(set) var channels: [Channel] = [] { didSet { if channels != oldValue { changed() } } }
    /// Lo que encontró la búsqueda.
    public private(set) var results: [Pick] = [] { didSet { if results != oldValue { changed() } } }
    private var loaded: [String: Channel] = [:]
    private let services: Services

    public init(_ services: Services) {
        self.services = services
        picks = services.kv.data(Self.key).flatMap { try? JSONDecoder().decode([Pick].self, from: $0) } ?? Self.starters
        super.init()
    }

    /// Sugeridas que aún no son canal.
    public var suggestions: [Pick] { Self.suggested.filter { s in !picks.contains { $0.id == s.id } } }
    public func isChannel(_ id: String) -> Bool { picks.contains { $0.id == id } }

    /// Trae los episodios de cada canal que falte (a la par); los que ya están no se vuelven a pedir.
    public func load() async {
        let missing = picks.filter { loaded[$0.id] == nil }
        let cinemeta = services.cinemeta
        let now = Date()
        await withTaskGroup(of: Channel?.self) { group in
            for pick in missing {
                group.addTask {
                    guard let meta = try? await cinemeta.meta(kind: "series", id: pick.id) else { return nil }
                    return Self.channel(pick, meta: meta, now: now)
                }
            }
            for await channel in group { if let channel { loaded[channel.id] = channel } }
        }
        publish()
    }

    /// Un canal desde la ficha de Cinemeta: los episodios que ya salieron (sin especiales), con su imagen y su nombre.
    nonisolated static func channel(_ pick: Pick, meta: JSON, now: Date) -> Channel? {
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        let episodes = CinemetaParsing.seasons(meta).filter { !$0.isSpecials }.flatMap { season in
            season.episodes.filter { e in
                guard let released = e.released, let at = ISO8601DateFormatter().date(from: released) ?? day.date(from: String(released.prefix(10))) else { return true }
                return at <= now
            }.map { ChannelSchedule.Episode(season: season.season, episode: $0.episode, name: $0.hasTitle ? $0.title : "", still: $0.thumbnail ?? "", videoID: $0.id) }
        }
        guard !episodes.isEmpty else { return nil }
        let info = CinemetaParsing.describe(meta)
        let minutes = Int(info.runtime.filter(\.isNumber)).flatMap { $0 >= 5 ? $0 : nil } ?? defaultMinutes
        return Channel(pick: pick, logo: info.logo, background: meta["background"]?.nonEmptyString ?? String(format: ForYou.metahubBackground, pick.id),
                       episodes: episodes, length: TimeInterval(minutes * 60))
    }

    /// Prende o apaga un canal (al final de la fila si es nuevo).
    public func toggle(_ pick: Pick) {
        if isChannel(pick.id) { picks.removeAll { $0.id == pick.id } } else { picks.append(pick) }
        services.kv.set(Self.key, data: try? JSONEncoder().encode(picks))
        publish()
    }

    /// Busca series por nombre («mal» encuentra Malcolm).
    public func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { results = []; return }
        let found = (try? await services.cinemeta.search("series", query: query)) ?? []
        guard !Task.isCancelled else { return }
        results = found.compactMap { m in
            guard let id = m["id"]?.nonEmptyString, id.hasPrefix("tt"), let name = m["name"]?.nonEmptyString else { return nil }
            return Pick(id: id, title: name, poster: m["poster"]?.nonEmptyString ?? Self.poster(id))
        }
    }

    private func publish() { channels = picks.compactMap { loaded[$0.id] } }
}
