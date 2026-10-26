import Foundation
import OrbitalCore

/// «Ya está para ver»: el aviso de un estreno de lo que sigues en Trakt, pero no a la hora en que sale sino cuando ya tiene
/// fuente (salir no siempre es poderse ver). Se revisa de vez en cuando (al abrir la app y en segundo plano): de lo que
/// salió en las últimas horas y aún no se avisó, se pregunta por fuentes; lo que ya tiene, se avisa una sola vez.
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
        public let quality: String?
        public let instant: Bool
        public let minutes: Int?

        public init(id: String, metaID: String, show: String, season: Int, episode: Int, episodeTitle: String, poster: String, art: String,
                    quality: String?, instant: Bool, minutes: Int?) {
            self.id = id; self.metaID = metaID; self.show = show; self.season = season; self.episode = episode; self.episodeTitle = episodeTitle
            self.poster = poster; self.art = art; self.quality = quality; self.instant = instant; self.minutes = minutes
        }
    }

    static let sentKey = "release-alerts-sent"
    /// Hasta cuánto después de salir se sigue buscando fuente (luego ya no es un estreno).
    public nonisolated static let window: TimeInterval = 36 * 3600
    /// Lo que se recuerda de lo ya avisado (lo más reciente).
    static let memory = 200
    /// El horario silencioso: de las 23 a las 8, el aviso espera a las 8.
    public nonisolated static let quietFrom = 23, quietUntil = 8
    /// Lo más que se espera por las fuentes de cada episodio. Se preguntan todos a la vez: antes iban de uno en uno y un
    /// episodio sin fuentes todavía esperaba a cada complemento hasta 15-30 s; con dos así se acababan los ~30 s que da iOS en
    /// segundo plano, iOS cortaba la revisión y el que sí tenía fuente nunca se avisaba.
    public nonisolated static let findBudget: TimeInterval = 10

    /// Lo que pasó en la última revisión (para la bitácora): qué faltaba avisar, qué ya tenía fuente, qué no contestó a
    /// tiempo y cuándo sale lo siguiente de tu calendario.
    public struct Report: Sendable, Equatable {
        public var pending: [String] = []
        public var found: [String] = []
        public var timedOut: [String] = []
        public var nextAiring: Date?
        public var seconds: Double = 0
    }
    public private(set) var report = Report()
    /// El tope por episodio de esta revisión (las pruebas lo bajan).
    var budget = ReleaseAlerts.findBudget

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

    /// Lo que ya se puede ver y no se ha avisado. Sin el aviso encendido o sin Trakt, nada.
    public func due() async -> [Alert] {
        report = Report()
        guard services.appSettings.releaseAlerts else { return [] }
        let started = Date()
        let now = services.now()
        let airings = (try? await services.forYou.calendar(skip: -1, days: 2)) ?? []
        report.nextAiring = airings.map(\.aired).filter { $0 > now }.min()
        let pending = Self.pending(airings, sent: sent(), now: now)
        report.pending = pending.map(\.id)
        // Todos a la vez, cada uno con su tope: la revisión entera cabe en el tiempo que da iOS.
        let finder = services.finder
        let budget = self.budget
        let asks = pending.map { item in
            (item, services.titlePrefs.languages(for: item.airing.series.imdb, settings: services.appSettings).prefs)
        }
        let answers = await withTaskGroup(of: (Int, Source?, Bool).self) { group in
            for (i, ask) in asks.enumerated() {
                group.addTask { let (best, late) = await Self.firstSource(finder, id: ask.0.id, prefs: ask.1, budget: budget); return (i, best, late) }
            }
            var out: [(Int, Source?, Bool)] = []
            for await answer in group { out.append(answer) }
            return out.sorted { $0.0 < $1.0 }
        }
        var out: [Alert] = []
        for (i, best, late) in answers {
            let (airing, episode, id) = pending[i]
            if late { report.timedOut.append(id) }
            guard let best else { continue }
            report.found.append(id)
            out.append(Alert(id: id, metaID: airing.series.imdb, show: airing.series.title, season: airing.season, episode: episode,
                             episodeTitle: episode == airing.first ? airing.episodeTitle : "", poster: airing.series.poster, art: airing.series.wide,
                             quality: best.resolution.isEmpty ? nil : best.resolution, instant: best.cached, minutes: airing.series.runtime))
        }
        report.seconds = Date().timeIntervalSince(started)
        return out
    }

    /// La mejor fuente de un episodio, o nada si en `budget` segundos no llegó ninguna (`late`: se acabó el tiempo). Lo que
    /// gane primero contesta y a lo otro ya no se le espera: la búsqueda corre en su propia tarea, que no se detiene al
    /// cancelarla, y un grupo de tareas se quedaba esperándola hasta el final.
    nonisolated static func firstSource(_ finder: StreamFinder, id: String, prefs: Preferences, budget: TimeInterval) async -> (Source?, late: Bool) {
        await withCheckedContinuation { (done: CheckedContinuation<(Source?, late: Bool), Never>) in
            let once = Once()
            let lookup = Task {
                let best = (try? await finder.find(kind: "series", videoID: id, prefs: prefs, fresh: true))?.first
                if once.claim() { done.resume(returning: (best, false)) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
                if once.claim() { lookup.cancel(); done.resume(returning: (nil, true)) }
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
