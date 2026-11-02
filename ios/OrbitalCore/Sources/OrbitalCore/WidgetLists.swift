import Foundation

/// Lo que el widget «Mosaico de una lista» necesita para pintarse sin red: tus listas de Explorar (Mi lista, Tus series, el
/// Top 10, tus listas de Trakt…) con los pósters de cada una ya reducidos junto al archivo. La app lo escribe cuando Explorar
/// arma sus estantes; el widget lee la lista que elegiste al configurarlo.
public struct WidgetLists: Codable, Equatable, Sendable {
    public struct Poster: Codable, Equatable, Sendable, Identifiable {
        public var kind: String
        public var metaID: String
        public var title: String
        /// El póster remoto y el reducido (nombre del archivo en la carpeta de las listas).
        public var poster: String
        public var imageFile: String?
        public var id: String { metaID }
        public init(kind: String, metaID: String, title: String, poster: String, imageFile: String? = nil) {
            self.kind = kind; self.metaID = metaID; self.title = title; self.poster = poster; self.imageFile = imageFile
        }
        /// Tocar un póster abre su ficha.
        public var link: URL? { WidgetLink.title(kind: kind, id: metaID) }
    }

    public struct List: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// De dónde sale («Trakt», «Esta semana en México»…), vacío si no se sabe.
        public var subtitle: String
        public var posters: [Poster]
        public init(id: String, title: String, subtitle: String = "", posters: [Poster]) {
            self.id = id; self.title = title; self.subtitle = subtitle; self.posters = posters
        }
    }

    /// Cuántas listas y cuántos pósters por lista se guardan (el grande enseña ~24 en el muro).
    public static let maxLists = 12, maxPosters = 24
    public var lists: [List]
    public init(lists: [List]) {
        self.lists = Array(lists.filter { !$0.posters.isEmpty }.prefix(Self.maxLists)).map { list in
            var copy = list; copy.posters = Array(list.posters.prefix(Self.maxPosters)); return copy
        }
    }

    /// La lista con ese id, o la primera (la que sale si aún no eliges, o si la que elegiste ya no existe).
    public func list(_ id: String?) -> List? { lists.first { $0.id == id } ?? lists.first }

    /// Un nombre de archivo seguro para el póster de un título.
    public static func imageFileName(for metaID: String) -> String {
        metaID.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined() + ".jpg"
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
    public static func decode(_ data: Data) -> WidgetLists? { try? JSONDecoder().decode(WidgetLists.self, from: data) }
}
