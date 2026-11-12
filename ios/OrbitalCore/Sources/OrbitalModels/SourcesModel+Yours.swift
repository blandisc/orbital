import Foundation
import OrbitalCore

/// «Versión» cuando tu idioma no arranca al instante (Fernando, 12 nov, Los Simpson T11E2 en latino: «me salen puros episodios
/// en inglés. Y me tengo que meter a checar cada uno»): se espera al complemento que llegó tarde, se dice si tu idioma existe
/// aunque haya que pedirlo y se revisa por dentro el audio de unas cuantas que arrancan al instante.
extension SourcesModel {
    /// Abre la lista: la arma, espera al complemento lento (si trajo algo, se rehace) y revisa el audio de las dudosas.
    public func load(onCellular: Bool = false) async {
        loads += 1
        let mine = loads
        await fill(onCellular: onCellular, quietly: false)
        // C8: el que no contestó a tiempo sigue buscando; lo que traiga se suma a la lista en cuanto llega.
        if !quiet.isEmpty, await services.finder.lateAnswers(kind: kind, videoID: videoID), mine == loads, !Task.isCancelled {
            await fill(onCellular: onCellular, quietly: true)
        }
        await probeAudio(onCellular: onCellular, mine: mine)
    }

    /// «Reintentar» de «No contestó a tiempo»: se les vuelve a preguntar a todos, también a los que se saltaban.
    public func retryQuiet(onCellular: Bool = false) async {
        await services.finder.retryQuiet(kind: kind, videoID: videoID)
        await load(onCellular: onCellular)
    }

    /// Revisa por dentro (solo el encabezado del MKV) el audio de las primeras que arrancan al instante con idioma dudoso, una a
    /// la vez; cada una que dice algo nuevo queda «Comprobado» (y «probable» en los demás episodios de su paquete) y la lista se
    /// rehace. Se corta al cerrar «Versión» (la tarea se cancela) o si se abre el reproductor.
    func probeAudio(onCellular: Bool, mine: Int) async {
        let probe = services.audioProbe
        let playing = services.titlePrefs.resumeChoice(metaID: metaID, videoID: videoID)?.source
        let picks = AudioProbe.candidates(ranked, wanted: prefs.wanted, tried: probe.tried).filter { $0.key != playing }
        for source in picks {
            guard !Task.isCancelled, mine == loads, !playerOpen() else { return }
            guard let tracks = await probe.audioTracks(of: source), !Task.isCancelled, mine == loads else { continue }
            let codes = PlayerModel.realAudio(tracks, source: source)
            PlayerModel.note("revisé el audio de «\(source.release)»: \(codes.isEmpty ? "sin idioma" : codes.joined(separator: ", "))")
            guard services.titlePrefs.rememberChecked(key: source.key, codes: codes, family: source.binge, pack: source.torrent?.hash) else { continue }
            await services.finder.forgetSorted()
            await fill(onCellular: onCellular, quietly: true)
        }
    }

    /// Trae tu idioma (con seguridad) alguna que arranca al instante, o alguna de tu lista que hay que pedir.
    static func hasYours(_ found: [Source], prefs: Preferences) -> Bool {
        found.contains { !hidden($0) && !$0.refused && !$0.isOtherTitle && speaksYours($0, prefs: prefs) }
    }

    /// Esta versión suena en tu idioma, con seguridad (no «tal vez»).
    static func speaksYours(_ s: Source, prefs: Preferences) -> Bool {
        let want = prefs.wanted
        return s.audio.contains { a in a.evidence.solid && (rowCode(a) == want || (want.count == 2 && a.code.hasPrefix(want))) }
    }

    /// «Hay latino, pero hay que pedirlo a la nube»: ninguna fila de tu idioma trae una que arranque al instante, y hay alguna
    /// en tu idioma para pedir (de tu lista o de lo que existe sin Real-Debrid). La mejor, en el orden de la recomendación. Lo
    /// que ya pediste y sigue en camino no se vuelve a ofrecer (ya dice cómo va en su renglón).
    public static func yoursToRequest(_ ranked: [Source], rows: [LanguageRow], prefs: Preferences, limitGB: Double, inCloud: Set<Int> = []) -> RequestableVersion? {
        let yourRows = rows.filter { $0.code == prefs.wanted || ($0.yours && $0.code != "es") }
        let instantYours = yourRows.contains { row in row.options.contains { $0.speed != .realDebridMustDownload && !$0.otherTitle } }
        guard !instantYours, !inCloud.contains(where: { id in ranked.contains { $0.index == id && speaksYours($0, prefs: prefs) } }) else { return nil }
        guard let pick = ranked.first(where: { s in
            !s.cached && s.debrid && !hidden(s) && !s.refused && !s.isOtherTitle && s.torrent != nil && speaksYours(s, prefs: prefs)
        }) else { return nil }
        let code = Streams.playingLanguage(pick, prefs).map(rowCode) ?? prefs.wanted
        let evidence = pick.audio.filter { rowCode($0) == code }.map(\.evidence).min() ?? .name
        return RequestableVersion(code: code, option: option(pick, code: code, evidence: evidence, limitGB: limitGB, recommended: false))
    }
}
