import Foundation
import OrbitalCore

/// «Tus vistas» de un título o un capítulo (O3-B; F5 de la revisión del 10 nov 2026): cada vez que lo viste, cambiar una fecha
/// sin perder la vista, «La vi otra vez», borrar una (con «Deshacer») y, sin internet, lo que espera en este aparato. La hoja
/// y el renglón de la ficha solo pintan esto; las reglas viven en `WatchService+Viewings` y se prueban en `ViewingsModelTests`.
@MainActor
public final class ViewingsModel: ObservableModel {
    public let kind: String
    public let metaID: String
    public let videoID: String
    /// El nombre del título (para «La vi otra vez» de algo que aún no estaba aquí).
    public let title: String

    /// La más nueva primero. Las de id 0 aún no llegan a Trakt («Espera a que haya internet»).
    public private(set) var viewings: [TraktViewing] = [] { didSet { if oldValue != viewings { changed() } } }
    public private(set) var loading = true { didSet { if oldValue != loading { changed() } } }
    /// Sin internet: solo lo que espera en este aparato (la hoja lo dice).
    public private(set) var offline = false { didSet { if oldValue != offline { changed() } } }

    private let services: Services

    public init(_ services: Services, kind: String, metaID: String, videoID: String, title: String) {
        self.services = services
        self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.title = title
        super.init()
    }

    /// Cuántas veces la viste (nil: aún no se sabe o no se pudo preguntar).
    public var count: Int? { loading && viewings.isEmpty ? nil : viewings.count }
    /// La última vez.
    public var last: TraktViewing? { viewings.first }

    /// Para la hoja: sube primero lo que esperaba y, sin internet, enseña lo de la cola.
    public func load() async {
        loading = true
        (viewings, offline) = await services.watch.viewingsOrQueued(kind: kind, videoID: videoID)
        loading = false
    }

    /// Para el renglón de la ficha («La viste 2 veces · la última, el …»): solo pregunta; sin red, no dice nada.
    public func peek() async {
        if let found = try? await services.watch.viewings(kind: kind, videoID: videoID) { viewings = found }
        loading = false
    }

    /// Borra esa vista ya (la hoja lo anima) y devuelve el envío. Si era la única, deja de contar como visto.
    public func remove(_ v: TraktViewing) -> @MainActor () async -> Void {
        let left = viewings.count - 1
        viewings.removeAll { $0 == v }
        let watch = services.watch, kind = kind, metaID = metaID, videoID = videoID
        return { await watch.removeViewing(v, kind: kind, metaID: metaID, videoID: videoID, remaining: left) }
    }

    /// «Deshacer» de «Vista borrada»: la misma, con su fecha.
    public func undoRemove(_ v: TraktViewing) async {
        await services.watch.addViewing(kind: kind, metaID: metaID, videoID: videoID, at: v.at)
        await load()
    }

    /// Otra fecha: la nueva entra y la vieja sale cuando la nueva llegó a Trakt.
    public func move(_ v: TraktViewing, to date: Date) async {
        await services.watch.moveViewing(v, kind: kind, videoID: videoID, to: date)
        await load()
    }

    /// «La vi otra vez»: una vista más, aunque haya otra cerca (la pediste tú).
    public func add(at date: Date) async {
        await services.watch.addViewing(kind: kind, metaID: metaID, videoID: videoID, name: title, at: date)
        await load()
    }
}
