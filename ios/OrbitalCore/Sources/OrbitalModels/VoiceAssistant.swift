import Foundation
import OrbitalCore

/// Hace una orden de voz (del micrófono del control o de Siri): `VoiceRouter` decide quién la atiende y aquí se hace. Lo del
/// iPhone (descargar, seguir aquí) y las teclas no necesitan que la consola entienda nada; todo lo demás se lo pregunta a tu
/// Orbital (`/api/voice`, lo mismo que Alexa) y regresa lo que contestó.
@MainActor
public final class VoiceAssistant {
    public struct Outcome: Equatable, Sendable {
        public var ok: Bool
        /// Lo que se dice en voz alta y se enseña (de la consola tal cual, o del iPhone en español: la pantalla lo traduce).
        public var speech: String
        /// Seguir viendo en el iPhone lo que se ve en la TV (lo hace la pantalla: abrir el reproductor).
        public var continueHere = false
        /// Lo que se entendió, ya limpio («pon El viaje de Chihiro»): se enseña bajo la respuesta para saber si el dictado
        /// escribió bien el nombre.
        public var heard = ""
        /// La consola no supo cuál (varias con el mismo nombre): se tocan en el iPhone (`choose`).
        public var choices: [OrbitalRemote.VoiceChoice] = []
        /// Con «pon Dune» la consola ya puso una de `choices` (su `metaID`): las demás sirven para cambiarla.
        public var picked: String?
        /// Abrir la guía de voz («¿qué puedo decir?»).
        public var guide = false
        /// Las frases del momento que mandó la consola (vacío: se quedan las de antes).
        public var hints: [String] = []

        public init(ok: Bool, speech: String, continueHere: Bool = false, heard: String = "", choices: [OrbitalRemote.VoiceChoice] = [],
                    picked: String? = nil, guide: Bool = false, hints: [String] = []) {
            self.ok = ok; self.speech = speech; self.continueHere = continueHere; self.heard = heard; self.choices = choices
            self.picked = picked; self.guide = guide; self.hints = hints
        }

        /// Para la barra de voz.
        public var reply: OrbitalRemote.VoiceReply {
            .init(ok: ok, speech: speech, heard: heard, choices: choices, picked: picked, guide: guide, hints: hints)
        }
    }

    private let services: Services
    private let tvNow: TVNowModel

    public init(services: Services, tvNow: TVNowModel) { self.services = services; self.tvNow = tvNow }

    public func handle(_ said: String) async -> Outcome {
        var outcome = await run(said)
        if outcome.heard.isEmpty { outcome.heard = VoiceRouter.clean(said) }
        return outcome
    }

    private func run(_ said: String) async -> Outcome {
        switch VoiceRouter.route(said) {
        case .nothing:
            return Outcome(ok: false, speech: "No te escuché.")
        case .key(let action):
            await tvNow.press(action)
            return Outcome(ok: true, speech: "")
        case .continueHere:
            await tvNow.refreshNow()
            guard tvNow.now != nil else { return Outcome(ok: false, speech: "No hay nada en la TV para seguir aquí.") }
            return Outcome(ok: true, speech: "Sigue aquí.", continueHere: true)
        case .download(let title):
            return await download(title)
        case .console(let text):
            let reply = await tvNow.say(text)
            return Outcome(ok: reply.ok, speech: reply.speech, heard: reply.heard, choices: reply.choices, picked: reply.picked,
                           guide: reply.guide, hints: reply.hints)
        }
    }

    /// Tocaste una de las opciones: la película se pone en la TV; la serie, desde su primer episodio (si Cinemeta no contesta,
    /// abre su ficha allá para elegirlo).
    public func choose(_ choice: OrbitalRemote.VoiceChoice) async -> Outcome {
        if choice.kind == "series", let first = await episodes(seriesID: choice.metaID).first, let episode = first.episodes.first {
            return await playEpisode(seriesID: choice.metaID, episode: episode, season: first.season, title: choice.title)
        }
        let speech = choice.kind == "movie" ? "Poniendo \(choice.title)." : "Abriendo \(choice.title) en la TV."
        return await play(kind: choice.kind, metaID: choice.metaID, videoID: choice.kind == "movie" ? choice.metaID : nil,
                          title: choice.title, speech: speech)
    }

    /// Las temporadas de una serie para elegir episodio: sin especiales (temporada 0) ni episodios que aún no salen.
    public func episodes(seriesID: String) async -> [Season] {
        guard let meta = try? await services.cinemeta.meta(kind: "series", id: seriesID) else { return [] }
        return CinemetaParsing.seasons(meta).filter { !$0.isSpecials }.compactMap { season in
            var aired = season
            aired.episodes = season.episodes.filter { CinemetaParsing.aired($0.released) }
            return aired.episodes.isEmpty ? nil : aired
        }
    }

    /// Pone en la TV ese episodio («The Office · T2 E5»).
    public func playEpisode(seriesID: String, episode: Episode, season: Int, title: String) async -> Outcome {
        let label = "\(title) · T\(season) E\(episode.episode)"
        return await play(kind: "series", metaID: seriesID, videoID: episode.id, title: label, speech: "Poniendo \(label).")
    }

    private func play(kind: String, metaID: String, videoID: String?, title: String, speech: String) async -> Outcome {
        do {
            try await services.orbital.play(kind: kind, metaID: metaID, videoID: videoID, title: title)
            return Outcome(ok: true, speech: speech, heard: title)
        } catch let failure as OrbitalRemote.Failure {
            return Outcome(ok: false, speech: failure.description, heard: title)
        } catch {
            return Outcome(ok: false, speech: OrbitalRemote.Failure.unreachable.description, heard: title)
        }
    }

    /// Descargar en el iPhone: lo que se ve en la TV, o una película por su nombre (una serie se descarga por episodios: desde
    /// su ficha).
    private func download(_ title: String?) async -> Outcome {
        if let title {
            guard let found = try? await services.cinemeta.searchAll(title), !found.isEmpty else {
                return Outcome(ok: false, speech: "No encontré \(title).")
            }
            let target = VoiceRouter.fold(title)
            let pick = found.first { VoiceRouter.fold($0.title) == target } ?? found[0]
            guard pick.kind == "movie" else {
                return Outcome(ok: false, speech: "\(pick.title) es una serie: elige los episodios en su ficha para descargarlos.")
            }
            let outcome = await services.queueDownload(kind: "movie", metaID: pick.metaID, videoID: pick.metaID, title: pick.title,
                                                       originalTitle: pick.title, subtitle: "", poster: pick.poster)
            return Self.outcome(outcome, name: pick.title)
        }
        await tvNow.refreshNow()
        guard let now = tvNow.now, let metaID = now.metaID, !now.live else {
            return Outcome(ok: false, speech: "No hay nada en la TV para descargar.")
        }
        let episode = services.tvEpisodeLabel(now.season, now.episode, now.episodeLabel)
        let outcome = await services.queueDownload(kind: now.kind, metaID: metaID, videoID: now.videoID ?? metaID, title: now.title,
                                                   originalTitle: now.title, subtitle: episode, poster: now.poster)
        return Self.outcome(outcome, name: episode.isEmpty ? now.title : "\(now.title) \(episode)")
    }

    static func outcome(_ outcome: TitleModel.DownloadOutcome, name: String) -> Outcome {
        switch outcome {
        case .queued: Outcome(ok: true, speech: "Descargando \(name) en el iPhone.")
        case .already: Outcome(ok: true, speech: "\(name) ya está descargado.")
        case .noSources: Outcome(ok: false, speech: "No encontré una versión para descargar \(name).")
        case .notEnoughSpace(let message), .failed(let message): Outcome(ok: false, speech: message)
        }
    }
}
