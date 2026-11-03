import Foundation
import OrbitalCore

/// R15 · «Avisarme cuando aparezca»: «Nadie lo tiene todavía en internet» deja de ser un callejón. Se revisa una vez al día
/// durante 14 días (como «Recordarme» de Netflix) y, en cuanto aparece una versión, avisa («Ya apareció») para pedirla o
/// verla. Revisa al volver a la app y cuando iOS la despierta (mejor esfuerzo, como los pedidos).
@MainActor
public final class AppearWatch: ObservableModel {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var kind: String
        public var metaID: String
        public var videoID: String
        public var title: String
        public var since: Date
        public var checked: Date?
        public var id: String { "\(kind):\(videoID)" }
        /// El último día que se revisa.
        public var until: Date { since.addingTimeInterval(AppearWatch.days * 86_400) }
    }

    public nonisolated static let days: TimeInterval = 14
    /// Una vez al día (con un poco de holgura: iOS no despierta a la hora exacta).
    public nonisolated static let every: TimeInterval = 20 * 3_600
    static let storeKey = "appear-watch"

    public private(set) var entries: [Entry] = [] { didSet { if oldValue != entries { changed(); save() } } }
    private let kv: KeyValueStore
    private let clock: @Sendable () -> Date
    /// ¿Ya existe al menos una versión de ese video? nil si no se pudo preguntar (sin red: se intenta la próxima vez).
    private let lookup: @MainActor (Entry) async -> Bool?
    /// Apareció: el aviso (lo pone la app).
    public var onAppeared: (@MainActor (Entry) async -> Void)?
    private var checking = false

    public init(kv: KeyValueStore, clock: @escaping @Sendable () -> Date = { Date() }, lookup: @escaping @MainActor (Entry) async -> Bool?) {
        self.kv = kv; self.clock = clock; self.lookup = lookup
        super.init()
        entries = kv.data(Self.storeKey).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    private func save() { kv.set(Self.storeKey, data: try? JSONEncoder().encode(entries)) }

    public func entry(kind: String, videoID: String) -> Entry? { entries.first { $0.kind == kind && $0.videoID == videoID } }

    /// «Avisarme cuando aparezca». Revisar ahora no hace falta: acabas de ver que nadie lo tiene.
    public func watch(kind: String, metaID: String, videoID: String, title: String) {
        let now = clock()
        entries = entries.filter { !($0.kind == kind && $0.videoID == videoID) }
            + [Entry(kind: kind, metaID: metaID, videoID: videoID, title: title, since: now, checked: now)]
    }

    /// «Ya no avisarme».
    public func stop(kind: String, videoID: String) { entries.removeAll { $0.kind == kind && $0.videoID == videoID } }

    /// Lo que toca revisar hoy (y se olvida lo que pasó de 14 días).
    public func due() -> [Entry] {
        let now = clock()
        entries.removeAll { now > $0.until }
        return entries.filter { $0.checked.map { now.timeIntervalSince($0) >= Self.every } ?? true }
    }

    /// Revisa lo que toca; lo que apareció avisa y sale de la lista. Devuelve lo que apareció.
    @discardableResult
    public func check() async -> [Entry] {
        guard !checking else { return [] }
        checking = true
        defer { checking = false }
        var found: [Entry] = []
        for entry in due() {
            guard let exists = await lookup(entry) else { continue }   // sin respuesta: mañana se intenta
            if exists {
                found.append(entry)
                stop(kind: entry.kind, videoID: entry.videoID)
                await onAppeared?(entry)
            } else if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[i].checked = clock()
            }
        }
        return found
    }
}
