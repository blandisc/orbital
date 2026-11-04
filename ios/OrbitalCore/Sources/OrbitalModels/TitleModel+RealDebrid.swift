import Foundation
import OrbitalCore
import OrbitalAddons

/// «Pedirlo y avisarme» en la ficha (R2-A, R4): qué torrent existe para lo que Real-Debrid todavía no tiene, en qué idioma,
/// y si otro idioma sí arranca al instante («Verlo en inglés al instante»).
public struct DebridOffer: Equatable, Sendable {
    public var torrent: TorrentID
    /// El idioma de lo que se pediría («es-419»), si se sabe.
    public var language: String?
    public var release: String?
    /// Otro idioma que sí arranca al instante («en»), si hay, y esa versión («Verlo en inglés al instante»).
    public var instantLanguage: String?
    public var instantSource: Source?
}

extension TitleModel {
    /// La ficha guarda si la última vez Torrentio sin Real-Debrid contestó «no hay ninguno» (causa 11).
    var lastLookupEmpty: Bool { lookupEmpty[metaID] ?? false }

    /// Lo que se puede pedir de ese video: la versión «por bajar» de tu lista (Real-Debrid ya la conoce) o el mejor torrent que
    /// existe sin Real-Debrid (R4). nil sin clave, sin Torrentio o si nada existe.
    func offerToRequest(videoID: String, prefs: Preferences, found: [Source]) async -> DebridOffer? {
        let requests = services.debridRequests
        guard requests.canRequest else { lookupEmpty[metaID] = false; return nil }
        // «Verlo en X al instante» solo ofrece lo que «Versión» enseña como «Al instante» (Fernando, 3 nov, con «El viento tiene
        // miedo»: la ficha prometía otra versión que sí la tiene y en la lista no aparecía ninguna).
        let instant = Self.shownInstant(found, prefs: prefs)
        let instantLanguage = instant.flatMap { Streams.playingLanguage($0, prefs)?.code }
        // La de tu lista que todavía no está (Torrentio la conoce con Real-Debrid): esa misma.
        if let pending = found.first(where: { !$0.instant && !SourcesModel.hidden($0) }), let torrent = pending.torrent {
            lookupEmpty[metaID] = false
            let language = Streams.playingLanguage(pending, prefs)?.code
            let other = instantLanguage == language ? nil : instantLanguage
            return DebridOffer(torrent: torrent, language: language, release: pending.release.isEmpty ? nil : pending.release,
                               instantLanguage: other, instantSource: other == nil ? nil : instant)
        }
        guard let torrents = await requests.torrents(kind: kind, videoID: videoID, prefs: prefs) else { lookupEmpty[metaID] = false; return nil }
        lookupEmpty[metaID] = torrents.isEmpty && found.isEmpty
        guard let best = torrents.first, let torrent = best.torrent else { return nil }
        let language = Streams.playingLanguage(best, prefs)?.code
        // Si la que arranca ya está en tu idioma, no hace falta pedir nada.
        if let instant, Streams.playingLanguage(instant, prefs)?.code == language || language == nil { return nil }
        return DebridOffer(torrent: torrent, language: language, release: best.release.isEmpty ? nil : best.release,
                           instantLanguage: instantLanguage, instantSource: instant)
    }

    /// La mejor versión que arranca al instante y que la lista de versiones enseña con «Al instante»: una tarjeta de un idioma
    /// de arriba (el tuyo, el original o un español), no escondida en «Otras», en «Más idiomas» ni marcada «¿Otro título?».
    /// Un enlace que no pasa por Real-Debrid arranca, pero la lista no lo llama «Al instante»: tampoco cuenta.
    static func shownInstant(_ found: [Source], prefs: Preferences) -> Source? {
        let main = SourcesModel.languageRows(found, prefs: prefs, limitGB: .infinity).main
        let shown = Set(main.flatMap { $0.options.filter { $0.cached && !$0.otherTitle }.map(\.id) })
        return found.first { shown.contains($0.index) }
    }

    /// El pedido del video que toca (película o el episodio del botón), si hay.
    public var debridRequest: DebridRequest? {
        guard let videoID = continueVideoID else { return nil }
        return services.debridRequests.request(metaID: metaID, videoID: videoID)
    }

    /// IOS-19 · lo que otra cuenta de Real-Debrid (la de tu TV) está pidiendo de este mismo video.
    public var otherAccountRequest: DebridRequest? {
        guard let videoID = continueVideoID, debridRequest == nil else { return nil }
        return services.debridRequests.otherAccountRequest(metaID: metaID, videoID: videoID)
    }

    /// «Pedirlo y avisarme» desde la ficha: el torrent de `debridOffer` (o el mejor que exista). Con `source`, esa versión de
    /// la lista («Versión» › una que Real-Debrid aún no tiene › «Pedirlo y avisarme»), del video `videoID`.
    public func requestFromDebrid(source: Source? = nil, videoID: String? = nil, onCellular: Bool = false) async -> DebridRequestsModel.Outcome? {
        guard let videoID = videoID ?? continueVideoID else { return nil }
        let prefs = services.titlePrefs.languages(for: metaID, settings: services.appSettings, onCellular: onCellular).prefs
        let numbers = kind == "series" ? episode(videoID).map { ($0.0, $0.1.episode) } : nil
        let picked = source.flatMap { s in s.torrent.map { (torrent: $0, language: Streams.playingLanguage(s, prefs)?.code, release: s.release.isEmpty ? nil : s.release) } }
        let outcome = await services.debridRequests.request(kind: kind, metaID: metaID, videoID: videoID, title: title.isEmpty ? originalTitle : title,
                                                            season: numbers?.0, episode: numbers?.1, prefs: prefs,
                                                            preferred: picked?.torrent ?? debridOffer?.torrent,
                                                            language: picked == nil ? debridOffer?.language : picked?.language,
                                                            release: picked == nil ? debridOffer?.release : picked?.release)
        guard videoID == continueVideoID else { return outcome }   // otro episodio: el botón de la ficha no cambia
        if case .requested(let request) = outcome { unavailableCause = request.state.isActive ? .downloading(percent: request.percent) : unavailableCause }
        if case .nobodyHasIt = outcome { unavailableCause = .nobodyHasIt }
        return outcome
    }
}
