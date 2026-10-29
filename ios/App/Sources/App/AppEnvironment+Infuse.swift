import SwiftUI
import UIKit
import OrbitalCore
import OrbitalModels

/// Ver con Infuse: abrirlo con el video, recibirlo de vuelta y guardar el avance.
extension AppEnvironment {
    /// Reproduce en Infuse (si lo prefieres en Ajustes, o si el motor propio no pudo) y se queda esperando a que vuelva.
    func playExternal(_ request: PlayRequest, source: Source? = nil) async {
        let position = request.fromStart ? 0 : await services.watch.resumePosition(metaID: request.metaID, videoID: request.videoID, kind: request.kind)
        let langs = services.titlePrefs.languages(for: request.metaID, settings: services.appSettings)
        var chosen = source
        var unreachable = false
        if chosen == nil {
            do { chosen = try await services.finder.best(kind: request.kind, videoID: request.videoID, prefs: langs.prefs) }
            catch { unreachable = error is StreamFinderError }
        }
        guard let url = chosen?.playbackURL else {
            if unreachable {
                return notify("Sin internet", detail: "No pude buscar dónde verlo", tone: .warn, actionTitle: "Reintentar") { [weak self] in
                    Task { await self?.playExternal(request, source: source) }
                }
            }
            return notify("Real-Debrid aún no lo tiene", detail: "Los estrenos suelen llegar unas horas después")
        }
        // Apagados en este título (o en Ajustes): Infuse los recibe apagados (antes mandaba los de Ajustes de todos modos).
        let subtitle = langs.subtitles.isEmpty ? nil : await services.finder.subtitles(kind: request.kind, videoID: request.videoID, language: langs.subtitles).first
        var season: Int?, episode: Int?
        let parts = request.videoID.split(separator: ":")
        if request.kind == "series", parts.count >= 3 { season = Int(parts[parts.count - 2]); episode = Int(parts[parts.count - 1]) }
        let filename = Infuse.filename(title: request.originalTitle, year: request.year, season: season, episode: episode, ext: DownloadFiles.fileExtension(for: url))
        guard let infuseURL = Infuse.playURL(.init(video: url, position: Int(position), subtitle: subtitle, filename: filename)) else { return }
        let runtime = request.meta.map { CinemetaParsing.runtimeSeconds(CinemetaParsing.describe($0).runtime) } ?? 0
        external = ExternalSession(request: request, startedAt: Date(), startPosition: position, duration: runtime)
        let opened = await UIApplication.shared.open(infuseURL)
        if !opened { external = nil; notify("No pude abrir Infuse", detail: "¿Está instalado?", tone: .warn) }
    }

    /// Infuse volvió (`orbital-ios://infuse-done?...`): se guarda dónde te quedaste. Infuse ya avisa a Trakt por su cuenta.
    func infuseReturned(_ result: Infuse.Result) async {
        defer { external = nil; watchedSomething += 1 }
        guard let session = external else { return }
        switch result {
        case .failed:
            // Sin el texto técnico de Infuse: qué hacer, y la salida de verla aquí.
            let request = session.request
            notify("Infuse no pudo con esta versión", detail: "Prueba otra versión o ábrela aquí", tone: .warn, actionTitle: "Ver aquí") { [weak self] in
                self?.play(request)
            }
        case .closed:
            guard let seconds = Infuse.seconds(from: result, knownDuration: session.duration) else { return }
            let r = session.request
            let watched = max(0, seconds - session.startPosition)
            let event = ProgressEvent(kind: r.kind, metaID: r.metaID, videoID: r.videoID, originalTitle: r.originalTitle, position: seconds, duration: session.duration,
                                      watched: min(watched, Date().timeIntervalSince(session.startedAt)), at: Date().timeIntervalSince1970)
            await services.watch.report(event, phase: .stopped(finished: StremioLibrary.finished(position: seconds, duration: session.duration, kind: r.kind)), scrobbleToTrakt: false)
            // Infuse no dice la duración: si tampoco la sabemos, se pregunta si terminaste.
            if session.duration == 0, seconds > 60 { askFinished = r }
        }
    }

    /// «Sí, lo terminé»: se marca como visto y Stremio apunta al siguiente.
    func confirmFinished(_ request: PlayRequest) async {
        let event = ProgressEvent(kind: request.kind, metaID: request.metaID, videoID: request.videoID, originalTitle: request.originalTitle,
                                  position: 1, duration: 1, watched: 0, at: Date().timeIntervalSince1970)
        await services.watch.report(event, phase: .stopped(finished: true), scrobbleToTrakt: false)
        askFinished = nil
    }
}
