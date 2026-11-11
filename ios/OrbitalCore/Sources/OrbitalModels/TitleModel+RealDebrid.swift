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
        if let pending = found.first(where: { !$0.instant && !SourcesModel.hidden($0) && !$0.refused }), let torrent = pending.torrent {
            lookupEmpty[metaID] = false
            let language = Streams.playingLanguage(pending, prefs)?.code
            let other = instantLanguage == language ? nil : instantLanguage
            return DebridOffer(torrent: torrent, language: language, release: pending.release.isEmpty ? nil : pending.release,
                               instantLanguage: other, instantSource: other == nil ? nil : instant)
        }
        guard let all = await requests.torrents(kind: kind, videoID: videoID, prefs: prefs) else { lookupEmpty[metaID] = false; return nil }
        lookupEmpty[metaID] = all.isEmpty && found.isEmpty
        // Lo que Real-Debrid no dejó bajar no se vuelve a ofrecer (FQ2-A).
        let refused = services.debridRequests.requester.refused(metaID: metaID)
        let torrents = all.filter { !refused.contains($0.torrent?.hash ?? "") }
        guard let best = torrents.first, let torrent = best.torrent else { return nil }
        let language = Streams.playingLanguage(best, prefs)?.code
        // Si la que arranca ya está en tu idioma, no hace falta pedir nada.
        if let instant, Streams.playingLanguage(instant, prefs)?.code == language || language == nil { return nil }
        return DebridOffer(torrent: torrent, language: language, release: best.release.isEmpty ? nil : best.release,
                           instantLanguage: instantLanguage, instantSource: instant)
    }

    /// FQ1-A: si «Ver» arranca ya en otro idioma de tu orden (castellano, inglés, el original) y tu idioma existe pero Real-Debrid
    /// no lo tiene, la mejor de tu idioma para pedirla aparte («Pedir a la nube en latino»). nil si «Ver» ya va en tu idioma,
    /// no arranca al instante o no se puede pedir.
    func wantedAside(videoID: String, prefs: Preferences, found: [Source]) async -> DebridOffer? {
        guard let playing = recommendedSource, playing.instant, recommendedLanguage != prefs.wanted, services.debridRequests.canRequest else { return nil }
        let refused = services.debridRequests.requester.refused(metaID: metaID)
        func mine(_ s: Source) -> Bool {
            guard let audio = Streams.playingLanguage(s, prefs), audio.code == prefs.wanted, audio.evidence.solid else { return false }
            return !SourcesModel.hidden(s) && !s.refused && !refused.contains(s.torrent?.hash ?? "") && !s.tags.contains(Streams.otherTitleTag)
                && !s.tags.contains(Streams.otherEpisodeTag) && !s.tags.contains("3D")
        }
        func offer(_ s: Source) -> DebridOffer? {
            s.torrent.map { DebridOffer(torrent: $0, language: prefs.wanted, release: s.release.isEmpty ? nil : s.release) }
        }
        if let listed = found.first(where: { !$0.instant && $0.debrid && mine($0) }) { return offer(listed) }
        guard let torrents = await services.debridRequests.torrents(kind: kind, videoID: videoID, prefs: prefs) else { return nil }
        let instant = Set(found.filter(\.instant).compactMap { $0.torrent?.hash })
        return torrents.first { mine($0) && !instant.contains($0.torrent?.hash ?? "") }.flatMap(offer)
    }

    /// La mejor versión que arranca al instante y que la lista de versiones enseña con «Al instante»: una tarjeta de un idioma
    /// de arriba (el tuyo, el original o un español), no escondida en «Otras», en «Más idiomas» ni marcada «¿Otro título?».
    /// Un enlace que no pasa por Real-Debrid arranca, pero la lista no lo llama «Al instante»: tampoco cuenta.
    static func shownInstant(_ found: [Source], prefs: Preferences) -> Source? {
        let main = SourcesModel.languageRows(found, prefs: prefs, limitGB: .infinity).main
        let shown = Set(main.flatMap { $0.options.filter { $0.cached && !$0.otherTitle }.map(\.id) })
        return found.first { shown.contains($0.index) }
    }

    /// El pedido del video que toca (película o el episodio del botón), si hay: el anotado para ese video o el paquete que lo
    /// trae (Torrentio lista esa misma huella para este episodio).
    public var debridRequest: DebridRequest? {
        guard let videoID = continueVideoID else { return nil }
        return services.debridRequests.request(metaID: metaID, videoID: videoID, listed: listedHashes[videoID] ?? [])
    }

    /// IOS-19 · lo que otra cuenta de Real-Debrid (la de tu TV) está pidiendo de este mismo video.
    public var otherAccountRequest: DebridRequest? {
        guard let videoID = continueVideoID, debridRequest == nil else { return nil }
        return services.debridRequests.otherAccountRequest(metaID: metaID, videoID: videoID)
    }

    /// FQ5-A · lo que tu TV ya tiene listo con otra cuenta de este mismo video (si aquí no hay pedido tuyo).
    public var otherAccountReady: DebridRequest? {
        guard let videoID = continueVideoID, debridRequest == nil else { return nil }
        return services.debridRequests.otherAccountReady(metaID: metaID, videoID: videoID)
    }

    /// «Pedirlo y avisarme» desde la ficha: el torrent de `debridOffer` (o el mejor que exista). Con `source`, esa versión de
    /// la lista («Versión» › una que Real-Debrid aún no tiene › «Pedirlo y avisarme»), del video `videoID`.
    /// `inYourLanguage`: «Pedir a la nube en latino» de al lado de «Ver» (FQ1-A): la de `wantedOffer`.
    public func requestFromDebrid(source: Source? = nil, videoID: String? = nil, inYourLanguage: Bool = false, onCellular: Bool = false) async -> DebridRequestsModel.Outcome? {
        guard let videoID = videoID ?? continueVideoID else { return nil }
        let debridOffer = inYourLanguage ? wantedOffer : debridOffer
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

    /// La causa en el orden de la tabla común: tu cuenta (preguntándole ya a Real-Debrid si Torrentio dijo «RD error»),
    /// complementos apagados y lo que dijo Torrentio en lugar de versiones.
    func cause(videoID: String, language: String, offer: DebridOffer?) async -> UnavailableCause? {
        // 1 · Ya lo pediste y Real-Debrid lo está bajando: eso va primero.
        if offersInstant, let request = services.debridRequests.request(metaID: metaID, videoID: videoID, listed: listedHashes[videoID] ?? []),
           request.state.isActive {
            return .downloading(percent: request.percent)
        }
        // 2 · Una película que aún no se estrena (un episodio lo dice el botón: «Sale el …»). Antes decía «Nadie lo tiene».
        if kind == "movie", offer == nil, let day = Self.airDate(meta?["released"]?.string, now: services.now()) { return .unreleased(day: releaseDay(day)) }
        // D1-B: sin Real-Debrid en esta versión (Orbital) no hay cuenta, nube ni complementos de qué hablar.
        guard offersInstant else { return lastLookupEmpty ? .nobodyHasIt : nil }
        let notices = await services.finder.notices(kind: kind, videoID: videoID)
        let health: DebridHealth? = notices.contains(where: \.aboutTheAccount) ? await services.debrid.refreshAfterTrouble() : nil
        let account = UnavailableCause.Account.from(health, saved: services.debrid.saved, now: services.now())
        if let byAccount = UnavailableCause.first(notice: nil, account: account, language: language) { return byAccount }
        // Sin tu clave de Real-Debrid, casi nada se ve en el iPhone (Torrentio no da enlaces sin ella): esa es la causa, tengas
        // armada tu lista de complementos o no (antes, sin lista, «Sin versiones por ahora» sin salida).
        if !services.debrid.hasToken { return .reconnectDebrid }
        let list = services.addonList
        if list.isConfigured, !list.installed.contains(where: { $0.enabled && $0.resources.contains("stream") }) { return .noAddonsOn }
        if let said = UnavailableCause.first(notice: notices.first(where: \.aboutTheAccount) ?? notices.first, account: account, language: language) { return said }
        // R4: con tu Torrentio sin Real-Debrid se sabe si existe (10, se puede pedir) o si nadie lo tiene (11).
        if let offer { return .notInDebrid(language: offer.language ?? language) }
        if lastLookupEmpty { return .nobodyHasIt }
        return nil
    }

    /// «el viernes 18 de diciembre» / «Friday, December 18»: el día de estreno para «Aún no se estrena · sale …».
    func releaseDay(_ date: Date) -> String {
        let english = services.appSettings.uiLanguage.hasPrefix("en")
        let f = DateFormatter()
        f.locale = Locale(identifier: english ? "en_US" : "es_MX")
        // El estreno de Cinemeta es un día (medianoche en UTC): dicho en tu huso, en México salía un día antes («jueves 17»
        // por «viernes 18»; escenarios comunes con la TV, 3 nov).
        f.timeZone = TimeZone(identifier: "UTC")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let text = f.string(from: date)
        return english ? text : "el " + text.replacingOccurrences(of: ",", with: "")
    }
}
