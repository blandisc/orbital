import Foundation
import OrbitalCore
import OrbitalAddons

/// Lo de Real-Debrid de un video en el reproductor.
struct PlayerDebridState {
    /// La versión «por bajar» que se abrió o se saltó (ya pedida): la que se pide con «Pedirlo y avisarme».
    var pendingSource: Source?
    /// No se pudo ni buscar (leer tus complementos falló, con internet): la causa 3, con el error en palabras.
    var searchProblem: String?
    /// El siguiente episodio ya se le pidió a Real-Debrid en este video (R8): no se pide dos veces.
    var requestedNext: String?
    /// Sin ninguna versión: lo que dijo tu Torrentio sin Real-Debrid (R4): existe (10, con su torrent) o nadie lo tiene (11).
    var lookupCause: (cause: UnavailableCause, torrent: Source?)?
}

/// Real-Debrid en el reproductor (R5, R6, D5): los avisos de Torrentio, los reintentos que no piden descargas y la causa en
/// palabras cuando no hay qué ver.
extension PlayerModel {
    /// La causa de tu cuenta, si tu cuenta es el problema.
    var accountCause: UnavailableCause? {
        UnavailableCause.first(notice: nil, account: .from(debridHealth, saved: debridSaved?(), now: clock()), language: wantedLanguage)
    }

    /// Por qué no hay qué ver, en palabras y con una salida (D5, R1, R7), cuando se sabe algo mejor que «no hay» o «ninguna
    /// funcionó»: tu Real-Debrid venció, sin Premium, la clave ya no sirve, Real-Debrid no lo dejó bajar o lo está bajando.
    public var cause: UnavailableCause? {
        guard failure == .noSources || failure == .noneWorked else { return nil }
        let account = UnavailableCause.Account.from(debridHealth, saved: debridSaved?(), now: clock())
        if let byAccount = UnavailableCause.first(notice: nil, account: account, language: wantedLanguage) { return byAccount }
        if let searchProblem = rd.searchProblem { return .cannotSearch(reason: searchProblem) }
        // 1 · Ya pedido (aquí, en la ficha o por Torrentio al abrirlo): cuánto lleva.
        if let request = currentRequest, request.state.isActive { return .downloading(percent: request.percent) }
        if let said = UnavailableCause.first(notice: lastNotice, account: account, language: wantedLanguage) { return said }
        return rd.lookupCause?.cause
    }

    /// No se pudo ni buscar: la causa 3, con el error en palabras.
    func cannotSearch(_ error: Error) {
        rd.searchProblem = UserMessages.humanize(String(describing: error))
        fail("No puedo buscar versiones.", .noSources)
    }

    /// El pedido de este video en la libreta, si hay.
    var currentRequest: DebridRequest? {
        guard let request else { return nil }
        return debridRequests?.request(metaID: request.metaID, videoID: request.videoID)
    }

    /// Esa versión ya está pedida en la libreta (y sigue en camino): abrirla otra vez no sirve.
    func alreadyRequested(_ source: Source) -> Bool {
        guard let torrent = source.torrent, let found = debridRequests?.request(hash: torrent.hash) else { return false }
        return found.state.isActive
    }

    /// Torrentio ya se la pidió a Real-Debrid al abrirla: a la libreta, para seguirla y avisar.
    func noteOpenedOnDebrid(_ source: Source) {
        rd.pendingSource = source
        guard let requests = debridRequests, let request else { return }
        let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
        let numbers = episodeNumbers(request.videoID), language = Streams.playingLanguage(source, prefs)?.code
        Task { await requests.noteOpened(source, kind: request.kind, metaID: request.metaID, videoID: request.videoID, title: request.displayTitle,
                                         season: numbers?.season, episode: numbers?.episode, language: language) }
    }

    /// «T1 E2» de un video id de serie («tt…:1:2»).
    func episodeNumbers(_ videoID: String) -> (season: Int, episode: Int)? {
        let parts = videoID.split(separator: ":")
        guard parts.count >= 3, let season = Int(parts[parts.count - 2]), let episode = Int(parts[parts.count - 1]) else { return nil }
        return (season, episode)
    }

    /// No hay ninguna versión: se dice y, con tu Torrentio sin Real-Debrid, se averigua si existe (R4).
    func noSources(generation mine: Int) async {
        // Solo había de otro título (9 nov): se dice tal cual, no «no hay».
        if !sourceChoices.isEmpty, sourceChoices.allSatisfy({ $0.tags.contains(Streams.otherTitleTag) }) {
            Self.note("solo había versiones de otro título: \(sourceChoices.count)")
            return fail("Solo encontré versiones de otra serie con un nombre parecido. Si quieres verlas, están en «Versión».", .noSources)
        }
        fail("No hay versiones en Real-Debrid para este título.", .noSources)
        await explainNoSources(generation: mine)
    }

    /// No hubo ninguna versión: con tu Torrentio sin Real-Debrid se sabe si existe (y se puede pedir) o si nadie lo tiene.
    func explainNoSources(generation mine: Int) async {
        guard let requests = debridRequests, let request, requests.canRequest else { return }
        let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
        guard let found = await requests.torrents(kind: request.kind, videoID: request.videoID, prefs: prefs), mine == generation else { return }
        if let best = found.first {
            rd.lookupCause = (.notInDebrid(language: Streams.playingLanguage(best, prefs)?.code ?? wantedLanguage), best)
        } else {
            rd.lookupCause = (.nobodyHasIt, nil)
        }
    }

    /// «Pedirlo y avisarme» desde el reproductor (R7): la versión «por bajar» que ya se abrió (Real-Debrid ya la conoce) o el
    /// mejor torrent que exista. Nunca la pide dos veces.
    public func requestFromDebrid() async -> DebridRequestsModel.Outcome? {
        guard let requests = debridRequests, let request else { return nil }
        let prefs = titlePrefs.languages(for: request.metaID, settings: settings.value, onCellular: onCellular()).prefs
        let pick = rd.pendingSource ?? rd.lookupCause?.torrent
        let numbers = episodeNumbers(request.videoID)
        let outcome = await requests.request(kind: request.kind, metaID: request.metaID, videoID: request.videoID, title: request.displayTitle,
                                             season: numbers?.season, episode: numbers?.episode, prefs: prefs, preferred: pick?.torrent,
                                             language: pick.flatMap { Streams.playingLanguage($0, prefs)?.code },
                                             release: pick.flatMap { $0.release.isEmpty ? nil : $0.release })
        changed()
        return outcome
    }

    /// Las que quedan por probar en un reintento (las que arrancan al instante y no han fallado).
    var remainingInstant: Int { sourceChoices.filter { $0.instant && !failedSources.contains($0.index) }.count }

    /// ¿La versión que falló ya había sonado? Solo entonces «Sigue en el mismo punto» dice algo cierto. Si nunca arrancó (lo
    /// común: Real-Debrid no la tenía lista), no hay punto que conservar: «La anterior no estaba disponible» (Fernando, 12 nov
    /// 2026: «no es como que falle y que luego busques otra para que continúe. Es que esa no estaba disponible»).
    public var retriedAfterPlaying: Bool { lastGoodPosition > 0 }

    /// «Probando otra versión (2 de 3)»: el intento que sigue y cuántos habrá en total, contando solo las que se van a
    /// probar (las que arrancan al instante, hasta `maxSourceRetries + 1`). Así el número del aviso es el de verdad.
    func triedAnother() -> PlayerNotice {
        let total = min(PlaybackRules.maxSourceRetries + 1, failedSources.count + max(1, remainingInstant))
        return .triedAnotherSource(attempt: min(failedSources.count + 1, total), of: total)
    }

    /// Lo que Torrentio mandó en lugar de versiones: si es de tu cuenta («RD error», sin acceso), se le pregunta ya a
    /// Real-Debrid (lo guardado puede decir «Premium» el día que venció, B-P1-1).
    func noteTorrentioNotices(_ notices: [StreamNotice], generation mine: Int) async {
        guard let first = notices.first(where: \.aboutTheAccount) ?? notices.first else { return }
        lastNotice = first
        guard first.aboutTheAccount, let debridTrouble else { return }
        let health = await debridTrouble()
        if mine == generation { debridHealth = health }
    }
}
