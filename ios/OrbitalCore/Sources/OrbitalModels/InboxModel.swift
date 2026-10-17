import Foundation
import OrbitalCore

/// «Desde la TV»: lo que tu Orbital le deja al iPhone con «Enviar al iPhone» y «Descargar en el iPhone».
///
/// Cada sondeo de `TVNowModel` (o la tarea en segundo plano de iOS) trae los pendientes y los pasa a `process`:
/// - `download`: busca la fuente recomendada y la pone en la cola de descargas (el mismo camino que el botón Descargar
///   de la ficha; «Solo con Wi‑Fi» lo respeta la cola).
/// - `open`: guarda un «Desde la TV» que Inicio enseña como tarjeta pequeña (Ver · Descargar · Descartar).
/// A la consola se le avisa (`ack`) **solo de lo que ya se atendió**: si algo no se pudo (sin red, la fuente no
/// contestó) se queda en su bandeja y se reintenta en el siguiente sondeo; tras `maxFailures` intentos se avisa del
/// problema, en palabras, y se da por atendido para no insistir para siempre.
@MainActor
public final class InboxModel: ObservableModel {
    public enum Event: Equatable {
        /// Se puso a descargar (con su nombre: «The Office T2 · E5»).
        case downloading(String)
        /// Llegó algo para abrir: la tarjeta «Desde la TV» ya está en Inicio.
        case received(String)
        case downloadFailed(String, reason: Reason)
    }
    public enum Reason: Equatable { case noSources, notEnoughSpace, other }

    /// Lo que la TV mandó para abrir, a la espera de que lo veas, lo descargues o lo descartes (el más reciente primero).
    public private(set) var fromTV: [OrbitalRemote.InboxItem] = [] { didSet { changed() } }
    /// El aviso de la app (toast): lo que pasó con lo que mandó la TV.
    public var onEvent: ((Event) -> Void)?

    public static let storeKey = "from-tv"
    public static let limit = 20
    public static let maxFailures = 3

    private let services: Services
    private var handled = Set<String>()        // ya atendidos: si el ack se perdió y la consola lo repite, no se vuelve a hacer
    private var failures: [String: Int] = [:]
    private var busy = false

    public init(_ services: Services) {
        self.services = services
        super.init()
        if let data = services.kv.data(Self.storeKey), let saved = try? JSONDecoder().decode([OrbitalRemote.InboxItem].self, from: data) { fromTV = saved }
    }

    /// Atiende los pendientes que trajo la consola y le avisa de lo que ya atendió.
    public func process(_ items: [OrbitalRemote.InboxItem]) async {
        guard !items.isEmpty, !busy else { return }
        busy = true
        defer { busy = false }
        var acked: [String] = []
        for item in items {
            if handled.contains(item.id) { acked.append(item.id); continue }
            let done: Bool
            switch item.action {
            case .download: done = await download(item)
            case .open: receive(item); done = true
            }
            if done { handled.insert(item.id); acked.append(item.id) }
        }
        guard !acked.isEmpty else { return }
        // Si el aviso no llega, la consola lo repite y `handled` evita hacerlo dos veces.
        try? await services.orbital.ack(ids: acked)
    }

    /// `true` si ya se atendió (se descargó, ya estaba, o no se puede y se avisó); `false` si vale la pena reintentar.
    private func download(_ item: OrbitalRemote.InboxItem) async -> Bool {
        let outcome = await queue(item)
        switch outcome {
        case .queued:
            onEvent?(.downloading(name(item))); return true
        case .already:
            return true
        case .noSources:
            onEvent?(.downloadFailed(name(item), reason: .noSources)); return true
        case .notEnoughSpace:
            onEvent?(.downloadFailed(name(item), reason: .notEnoughSpace)); return true
        case .failed:
            failures[item.id, default: 0] += 1
            guard failures[item.id, default: 0] >= Self.maxFailures else { return false }
            onEvent?(.downloadFailed(name(item), reason: .other)); return true
        }
    }

    private func queue(_ item: OrbitalRemote.InboxItem) async -> TitleModel.DownloadOutcome {
        await services.queueDownload(kind: item.kind, metaID: item.metaID, videoID: item.videoID ?? item.metaID, title: item.title,
                                     originalTitle: item.title, subtitle: services.tvEpisodeLabel(item.season, item.episode, item.episodeLabel), poster: item.poster)
    }

    private func receive(_ item: OrbitalRemote.InboxItem) {
        var list = fromTV.filter { !($0.metaID == item.metaID && $0.videoID == item.videoID) }  // el mismo título no se repite
        list.insert(item, at: 0)
        fromTV = Array(list.prefix(Self.limit))
        save()
        onEvent?(.received(name(item)))
    }

    /// «Descartar» en la tarjeta.
    public func dismiss(_ item: OrbitalRemote.InboxItem) {
        fromTV.removeAll { $0.id == item.id }
        save()
    }

    /// «Descargar» en la tarjeta: se baja lo mismo que si la TV hubiera mandado «Descargar en el iPhone». Si no se pudo, la
    /// tarjeta se queda para intentarlo otra vez.
    public func downloadFromCard(_ item: OrbitalRemote.InboxItem) async {
        switch await queue(item) {
        case .queued: onEvent?(.downloading(name(item))); dismiss(item)
        case .already: dismiss(item)
        case .noSources: onEvent?(.downloadFailed(name(item), reason: .noSources))
        case .notEnoughSpace: onEvent?(.downloadFailed(name(item), reason: .notEnoughSpace))
        case .failed: onEvent?(.downloadFailed(name(item), reason: .other))
        }
    }

    /// «Ver» en la tarjeta: la tarjeta ya cumplió.
    public func watched(_ item: OrbitalRemote.InboxItem) { dismiss(item) }

    private func save() {
        services.kv.set(Self.storeKey, data: try? JSONEncoder().encode(fromTV))
    }

    /// «The Office T2 E5» con la etiqueta de la TV en el idioma de la app.
    private func name(_ item: OrbitalRemote.InboxItem) -> String {
        let episode = services.tvEpisodeLabel(item.season, item.episode, item.episodeLabel)
        return episode.isEmpty ? item.title : "\(item.title) \(episode)"
    }
}
