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

        public init(ok: Bool, speech: String, continueHere: Bool = false, heard: String = "", choices: [OrbitalRemote.VoiceChoice] = []) {
            self.ok = ok; self.speech = speech; self.continueHere = continueHere; self.heard = heard; self.choices = choices
        }

        /// Para la barra de voz.
        public var reply: OrbitalRemote.VoiceReply { .init(ok: ok, speech: speech, heard: heard, choices: choices) }
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
            return Outcome(ok: reply.ok, speech: reply.speech, heard: reply.heard, choices: reply.choices)
        }
    }

    /// Tocaste una de las opciones: la película se pone en la TV; la serie abre su ficha allá para elegir el episodio.
    public func choose(_ choice: OrbitalRemote.VoiceChoice) async -> Outcome {
        do {
            try await services.orbital.play(kind: choice.kind, metaID: choice.metaID, videoID: choice.kind == "movie" ? choice.metaID : nil,
                                            title: choice.title)
            let speech = choice.kind == "movie" ? "Poniendo \(choice.title)." : "Abriendo \(choice.title) en la TV."
            return Outcome(ok: true, speech: speech, heard: choice.title)
        } catch let failure as OrbitalRemote.Failure {
            return Outcome(ok: false, speech: failure.description, heard: choice.title)
        } catch {
            return Outcome(ok: false, speech: OrbitalRemote.Failure.unreachable.description, heard: choice.title)
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
