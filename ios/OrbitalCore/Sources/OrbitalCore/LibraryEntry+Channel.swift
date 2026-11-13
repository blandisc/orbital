import Foundation

/// V2 (Fernando, 13 nov 2026: «vamos con B2»): **el canal no desordena tu serie, pero lo que dejaste a medias siempre se puede
/// retomar.** Un episodio de un canal de Inicio o de la ruleta de Los Simpson que cortas a la mitad sale en «Seguir viendo»
/// («T15 E12 · quedan 12 min») y la ficha ofrece continuarlo; al terminarlo (ahí o desde la ficha) o quitarlo, la serie vuelve
/// a donde ibas en tu orden, sin un «siguiente: T15 E13». El que ves completo queda visto (aquí y en Trakt), sin mover nada.
///
/// Cómo: el título guarda UN solo «dónde vas» (`videoID`, `position`, `nextUp`). El canal lo ocupa con su episodio a medias y
/// aparta el de antes en `detour.before`; terminar o quitar ese episodio lo regresa.
public struct ChannelDetour: Sendable, Equatable, Codable {
    /// El episodio del canal que dejaste a medias.
    public var videoID: String
    /// Dónde ibas en tu orden antes del canal.
    public var before: Spot

    /// Un «dónde vas» completo de `LibraryEntry`.
    public struct Spot: Sendable, Equatable, Codable {
        public var videoID: String?
        public var position: Double
        public var duration: Double
        public var fraction: Double?
        public var updatedAt: Double
        public var nextUp: Bool
        public var hiddenAt: Double?
    }
}

extension LibraryEntry {
    /// Menos que esto visto de un canal (zapear) no lo pone en «Seguir viendo» ni aparta tu orden.
    public static let channelMinWatched = PlaybackRules.minWatchedToSave

    var spot: ChannelDetour.Spot {
        .init(videoID: videoID, position: position, duration: duration, fraction: fraction, updatedAt: updatedAt, nextUp: nextUp, hiddenAt: hiddenAt)
    }

    mutating func restore(_ s: ChannelDetour.Spot) {
        videoID = s.videoID; position = s.position; duration = s.duration; fraction = s.fraction
        updatedAt = s.updatedAt; nextUp = s.nextUp; hiddenAt = s.hiddenAt
    }

    /// ¿El canal puso justo el episodio que te tocaba en tu orden (el siguiente, o el que ibas a medias)? Entonces cuenta como
    /// verlo en orden: al terminarlo, la serie pasa al que sigue.
    public func isYourTurn(_ video: String) -> Bool { detour == nil && videoID == video && (nextUp || position > 0) }

    /// Un episodio del canal a medias: ocupa «dónde vas» y aparta tu orden (el de antes del primer desvío, no otro del canal).
    /// `watched`: segundos que llevas vistos de ese episodio; si zapeaste (menos de `channelMinWatched`) y no lo venías viendo,
    /// no cambia nada.
    public mutating func channelProgress(videoID video: String, position: Double, duration: Double, watched: Double, at: Double) {
        let continuing = detour?.videoID == video && videoID == video
        guard continuing || watched >= Self.channelMinWatched else { return }
        let before = detour?.before ?? spot
        videoID = video; self.position = position; self.duration = duration; fraction = nil
        nextUp = false; hiddenAt = nil; updatedAt = at; channelAt = max(channelAt ?? 0, at)
        detour = ChannelDetour(videoID: video, before: before)
    }

    /// Terminaste un episodio del canal: queda visto y, si era el que dejaste a medias, vuelves a tu orden de antes. Tu orden
    /// no pasa al que le sigue.
    public mutating func channelFinished(videoID video: String, at: Double) {
        channelFinished(videoID: video, at: at, restoring: detour?.videoID == video ? detour : nil)
    }

    mutating func channelFinished(videoID video: String, at: Double, restoring d: ChannelDetour?) {
        seen.insert(video); channelAt = max(channelAt ?? 0, at)
        guard let d else { return }
        restore(d.before); detour = nil
    }

    /// «Quitar de Seguir viendo» con un episodio del canal a medias: vuelves a tu orden de antes y la serie sale de la fila.
    public mutating func dismissDetour() {
        if let d = detour, d.videoID == videoID { restore(d.before) }
        detour = nil
    }
}
