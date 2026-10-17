import Foundation
import OrbitalCore

/// Colecciones (Para ti › Listas): los premios (fijos), tus listas de Trakt con sus tres primeros pósters, y lo más
/// popular de cada año.
@MainActor
public final class CollectionsModel: ObservableModel {
    /// Una de tus listas de Trakt: nombre, cuántos títulos y sus tres primeros pósters (la pila de la tarjeta).
    public struct UserList: Sendable, Identifiable, Equatable {
        public let id: String, name: String, count: Int, posters: [String]
    }

    public let awards: [AwardCollection] = Awards.all
    public private(set) var lists: [UserList] = [] { didSet { changed() } }
    public private(set) var loadingLists = false { didSet { changed() } }
    /// Los años de «Por año», del actual hacia atrás.
    public let years: [Int]

    private let services: Services
    private var listItems: [String: [Suggestion]] = [:]
    private var yearItems: [String: [Suggestion]] = [:]

    public init(_ services: Services) {
        self.services = services
        let now = Calendar.current.component(.year, from: services.now())
        years = Array(stride(from: now, through: Self.firstYear, by: -1))
        super.init()
    }

    static let firstYear = 1980

    public var traktLinked: Bool { services.trakt?.linked ?? false }

    /// Tus listas (y lo que tiene cada una, para su pila de pósters).
    public func loadLists() async {
        guard let trakt = services.trakt, trakt.linked, lists.isEmpty else { return }
        loadingLists = true
        defer { loadingLists = false }
        let all = (try? await trakt.lists()) ?? []
        let loaded = await withTaskGroup(of: (Int, String, [Suggestion]).self) { group in
            for (i, l) in all.enumerated() {
                group.addTask { (i, l.id, ((try? await trakt.listItems(l.id)) ?? []).map { Suggestion($0, reason: .inList(l.name)) }) }
            }
            var out: [(Int, String, [Suggestion])] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }
        }
        for (_, id, items) in loaded { listItems[id] = items }
        lists = all.map { l in
            let items = listItems[l.id] ?? []
            return UserList(id: l.id, name: l.name, count: items.count, posters: items.prefix(3).map(\.poster))
        }
    }

    public func items(ofList id: String) -> [Suggestion] { listItems[id] ?? [] }

    /// Lo más popular de un año en Trakt (películas o series).
    public func items(year: Int, kind: String) async -> [Suggestion] {
        let key = "\(kind):\(year)"
        if let cached = yearItems[key] { return cached }
        guard let trakt = services.trakt else { return [] }
        let found = ((try? await trakt.popular(kind: kind, limit: 60, years: String(year))) ?? []).map { Suggestion($0, reason: .popular) }
        yearItems[key] = found
        return found
    }
}
