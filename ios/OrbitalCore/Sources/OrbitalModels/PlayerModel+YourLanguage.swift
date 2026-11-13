import Foundation
import OrbitalCore

/// Tu idioma en el reproductor directo (Fernando, 13 nov: «Sobre todo pasa cuando le doy a la ruleta esta de los Simpsons,
/// ya sea que entre por widget o por control panel»). La ruleta, el widget, el Centro de control y «Continuar» abren el
/// reproductor sin pasar por «Versión»: se sigue eligiendo la mejor que hay (la regla no cambia), pero la bitácora dice en
/// qué idioma quedó y, si ninguna de tu idioma arranca al instante, se consulta lo que existe (tu Torrentio sin Real-Debrid,
/// R4) y, si tu idioma está para pedir, se avisa una vez: «No está en latino al instante · Versión».
extension PlayerModel {
    /// La de tu idioma para pedir, si la hay (la que ofrece «Versión» del reproductor con «Pedir a la nube»).
    public var yoursToRequest: RequestableVersion? { rd.yours?.version }
    /// Su torrent (para decir cómo va si ya la pediste).
    public var yoursToRequestHash: String? { rd.yours?.source.torrent?.hash }

    /// Lo elegido, a la bitácora con su idioma; si no es el tuyo, se busca si existe para pedir.
    func noteChoice(_ found: Source, prefs: Preferences, generation mine: Int) {
        Self.note("versión: \(found.release.prefix(120))\(found.isOtherTitle ? " [¿otro título?]" : "")")
        let heard = Streams.playingLanguage(found, prefs).map { "\($0.code)\($0.evidence.solid ? "" : " (tal vez)")" } ?? "sin idioma"
        Self.note("idioma: \(heard) · \(YourLanguageNow.summary(sourceChoices, prefs: prefs))")
        guard !YourLanguageNow.available(sourceChoices, prefs: prefs), request?.sourceIndex == nil else { return }
        Task { [weak self] in await self?.lookForYours(prefs: prefs, generation: mine) }
    }

    /// Lo que existe en tu idioma sin Real-Debrid y tu lista no trae: la mejor para pedir y el aviso (una vez por video).
    func lookForYours(prefs: Preferences, generation mine: Int) async {
        guard let requests = debridRequests, requests.canRequest, let request, !hasPlayedYoursNotice else { return }
        guard let all = await requests.torrents(kind: request.kind, videoID: request.videoID, prefs: prefs), mine == generation else { return }
        let refused = requests.requester.refused(metaID: request.metaID)
        guard let pick = Self.yoursFromLookup(all, choices: sourceChoices, prefs: prefs, kind: request.kind, limitGB: settings.value.warnCellularOverGB, refused: refused) else {
            Self.note("tu idioma tampoco está para pedir (\(all.count) torrents sin Real-Debrid)")
            return
        }
        rd.yours = pick
        Self.note("hay \(pick.version.code) para pedir a la nube: \(pick.source.release.prefix(80))")
        changed()
        // Un aviso a la vez: si ya hay otro (otra versión, «descargando»), ese manda.
        if notice == nil { notice = .yoursOnlyByRequest(language: pick.version.code) }
    }

    /// Ya se avisó «No está en latino al instante» en este video.
    var hasPlayedYoursNotice: Bool { rd.yours != nil }

    /// La mejor en tu idioma para pedir, de lo que existe sin Real-Debrid (`all`) y no está ya en tu lista (`choices`) ni lo
    /// rechazó Real-Debrid. nil si en tu lista ya hay una de tu idioma al instante o si tu idioma no existe.
    static func yoursFromLookup(_ all: [Source], choices: [Source], prefs: Preferences, kind: String = "series", limitGB: Double, refused: Set<String> = []) -> (version: RequestableVersion, source: Source)? {
        let known = Set(choices.compactMap { $0.torrent?.hash }).union(refused)
        let extra: [Source] = all.compactMap { s in
            guard let hash = s.torrent?.hash, !known.contains(hash), !SourcesModel.hidden(s), SourcesModel.speaksYours(s, prefs: prefs) else { return nil }
            var s = s
            s.debrid = true; s.cached = false
            return s
        }
        let ranked = Streams.rank(choices + extra, prefs: prefs, kind: kind)
        guard let version = SourcesModel.yoursToRequest(ranked, rows: [], prefs: prefs, limitGB: limitGB),
              let source = ranked.first(where: { $0.index == version.id }) else { return nil }
        return (version, source)
    }
}
