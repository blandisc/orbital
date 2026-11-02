import Foundation
import OrbitalCore

/// «Ya salió»: el aviso de un estreno de lo que sigues en Trakt en cuanto sale, tenga o no ya de dónde verse (Fernando,
/// 1 nov 2026: antes se esperaba a que Real-Debrid lo tuviera y los avisos llegaban tarde o no llegaban). Se revisa de vez
/// en cuando (al abrir la app y en segundo plano): lo que salió en las últimas horas y aún no se avisó, se avisa una vez.
@MainActor
public final class ReleaseAlerts {
    public struct Alert: Sendable, Equatable, Identifiable {
        public let id: String              // el video: «tt…:2:5»
        public let metaID: String
        public let show: String
        public let season: Int
        public let episode: Int
        public let episodeTitle: String
        public let poster: String
        public let art: String
        /// La imagen del propio episodio (Cinemeta), si ya la hay: el aviso la prefiere al fondo de la serie.
        public let still: String?
        public let quality: String?
        public let instant: Bool
        public let minutes: Int?

        public init(id: String, metaID: String, show: String, season: Int, episode: Int, episodeTitle: String, poster: String, art: String,
                    still: String? = nil, quality: String?, instant: Bool, minutes: Int?) {
            self.id = id; self.metaID = metaID; self.show = show; self.season = season; self.episode = episode; self.episodeTitle = episodeTitle
            self.poster = poster; self.art = art; self.still = still; self.quality = quality; self.instant = instant; self.minutes = minutes
        }

        /// Lo mismo con el nombre y la imagen del episodio que dice Cinemeta (lo que no traiga se queda como estaba).
        func with(_ episode: Episode?) -> Alert {
            guard let episode else { return self }
            return Alert(id: id, metaID: metaID, show: show, season: season, episode: self.episode,
                         episodeTitle: episode.hasTitle ? episode.title : episodeTitle, poster: poster, art: art,
                         still: episode.thumbnail ?? still, quality: quality, instant: instant, minutes: minutes)
        }
    }

    static let sentKey = "release-alerts-sent"
    /// Hasta cuánto después de salir se avisa (luego ya no es un estreno).
    public nonisolated static let window: TimeInterval = 36 * 3600
    /// Lo que se recuerda de lo ya avisado (lo más reciente).
    static let memory = 200
    /// El horario silencioso: de las 23 a las 8, el aviso espera a las 8.
    public nonisolated static let quietFrom = 23, quietUntil = 8
    /// Lo más que se espera la ficha de cada serie (el nombre y la imagen de cada episodio). Sin ella el aviso sale igual.
    public nonisolated static let metaBudget: TimeInterval = 4

    /// Lo que pasó en la última revisión (para la bitácora): qué faltaba avisar y cuándo sale lo siguiente de tu calendario.
    public struct Report: Sendable, Equatable {
        public var pending: [String] = []
        public var nextAiring: Date?
        public var seconds: Double = 0
    }
    public private(set) var report = Report()

    private let services: Services
    public init(_ services: Services) { self.services = services }

    /// Cada episodio que ya salió (en la ventana) y aún no se avisó. Un estreno de varios episodios el mismo día cuenta cada uno.
    public nonisolated static func pending(_ airings: [Airing], sent: Set<String>, now: Date) -> [(airing: Airing, episode: Int, id: String)] {
        airings.filter { $0.aired <= now && now.timeIntervalSince($0.aired) <= window }
            .flatMap { a in (a.first...max(a.first, a.last)).map { (a, $0, "\(a.series.imdb):\(a.season):\($0)") } }
            .filter { !sent.contains($0.2) }
    }

    /// Cuándo entregar un aviso: ahora (nil) o, en el horario silencioso, a las 8 de la mañana.
    public nonisolated static func deliverAt(now: Date, calendar: Calendar = .current) -> Date? {
        let hour = calendar.component(.hour, from: now)
        guard hour >= quietFrom || hour < quietUntil else { return nil }
        let morning = calendar.date(bySettingHour: quietUntil, minute: 0, second: 0, of: now) ?? now
        return hour >= quietFrom ? calendar.date(byAdding: .day, value: 1, to: morning) : morning
    }

    /// Lo que ya salió y no se ha avisado. Sin el aviso encendido o sin Trakt, nada.
    public func due() async -> [Alert] {
        report = Report()
        guard services.appSettings.releaseAlerts else { return [] }
        let started = Date()
        let now = services.now()
        let airings = (try? await services.forYou.calendar(skip: -1, days: 2)) ?? []
        report.nextAiring = airings.map(\.aired).filter { $0 > now }.min()
        let pending = Self.pending(airings, sent: sent(), now: now)
        report.pending = pending.map(\.id)
        let out = pending.map { airing, episode, id in
            Alert(id: id, metaID: airing.series.imdb, show: airing.series.title, season: airing.season, episode: episode,
                  episodeTitle: episode == airing.first ? airing.episodeTitle : "", poster: airing.series.poster, art: airing.series.wide,
                  quality: nil, instant: false, minutes: airing.series.runtime)
        }
        let detailed = await withEpisodeDetails(out)
        report.seconds = Date().timeIntervalSince(started)
        return detailed
    }

    /// El nombre y la imagen de cada episodio: el calendario de Trakt trae un solo nombre por estreno (el del primero, si salen
    /// varios el mismo día) y ninguna imagen del episodio. Una ficha por serie, todas a la vez y cada una con su tope.
    func withEpisodeDetails(_ alerts: [Alert]) async -> [Alert] {
        let cinemeta = services.cinemeta
        let shows = Array(Set(alerts.map(\.metaID)))
        let budget = Self.metaBudget
        let episodes = await withTaskGroup(of: [String: Episode].self) { group in
            for show in shows {
                group.addTask {
                    let meta = await Self.within(budget) { try? await cinemeta.meta(kind: "series", id: show) }
                    guard let meta else { return [:] }
                    return Dictionary(CinemetaParsing.seasons(meta).flatMap(\.episodes).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                }
            }
            var all: [String: Episode] = [:]
            for await found in group { all.merge(found) { a, _ in a } }
            return all
        }
        return alerts.map { $0.with(episodes[$0.id]) }
    }

    /// Lo que conteste `work` en `seconds`, o nada (sin esperar a que termine).
    nonisolated static func within<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async -> T?) async -> T? {
        await withCheckedContinuation { (done: CheckedContinuation<T?, Never>) in
            let once = Once()
            let job = Task { let value = await work(); if once.claim() { done.resume(returning: value) } }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if once.claim() { job.cancel(); done.resume(returning: nil) }
            }
        }
    }

    /// Ya se avisó: no se vuelve a avisar.
    public func markSent(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        let all = (sentList() + ids).suffix(Self.memory)
        services.kv.set(Self.sentKey, data: try? JSONEncoder().encode(Array(all)))
    }

    private func sentList() -> [String] { services.kv.data(Self.sentKey).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
    private func sent() -> Set<String> { Set(sentList()) }
}

/// Quién llegó primero (la búsqueda o el tope): solo uno contesta.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func claim() -> Bool { lock.withLock { defer { taken = true }; return !taken } }
}
