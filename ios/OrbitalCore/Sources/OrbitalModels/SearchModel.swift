import Foundation
import OrbitalCore

@MainActor
public final class SearchModel: ObservableModel {
    public struct Result: Equatable, Identifiable {
        public var id: String { "\(kind):\(metaID)" }
        public var kind: String, metaID: String, title: String, originalTitle: String, poster: String?, year: String
    }

    public private(set) var results: [Result] = [] { didSet { changed() } }
    public private(set) var isSearching = false { didSet { changed() } }
    public private(set) var error: String? { didSet { changed() } }
    public private(set) var recent: [String] { didSet { changed() } }
    private let services: Services
    private var latest = 0

    public init(_ services: Services) {
        self.services = services
        recent = services.kv.data("recent-searches").flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        super.init()
    }

    /// Busca películas y series; la última búsqueda manda (si escribes rápido, las viejas se descartan).
    public func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        latest += 1
        let ticket = latest
        guard query.count >= 2 else { results = []; error = nil; isSearching = false; return }
        isSearching = true
        defer { if ticket == latest { isSearching = false } }
        do {
            let found = try await services.cinemeta.searchAll(query)
            guard ticket == latest else { return }
            var names: [String: String] = [:]
            for kind in ["movie", "series"] {
                let metas = found.filter { $0.kind == kind }.map { JSON.object(["id": .string($0.metaID), "name": .string($0.title)]) }
                for meta in await services.localizer.catalog(kind: kind, metas: metas) {
                    if let id = meta["id"]?.string, let name = meta["name"]?.string { names[id] = name }
                }
            }
            guard ticket == latest else { return }
            results = found.map { Result(kind: $0.kind, metaID: $0.metaID, title: names[$0.metaID] ?? $0.title, originalTitle: $0.title, poster: $0.poster, year: $0.year) }
            error = nil
        } catch { if ticket == latest { results = []; self.error = "\(error)" } }
    }

    /// Recuerda lo que buscaste (solo cuando abres un resultado).
    public func remember(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        recent = Array(([query] + recent.filter { $0.lowercased() != query.lowercased() }).prefix(8))
        services.kv.set("recent-searches", data: try? JSONEncoder().encode(recent))
    }

    public func clearRecent() { recent = []; services.kv.set("recent-searches", data: nil) }
}
