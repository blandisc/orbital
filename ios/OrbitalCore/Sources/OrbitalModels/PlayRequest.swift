import Foundation
import OrbitalCore
import os

/// Lo que se pide reproducir y lo que el reproductor anuncia: la petición, «Siguiente», los avisos, el audio de otra versión y el episodio local.

/// Qué se va a reproducir. `originalTitle` es el nombre de Cinemeta (lo que se guarda en Stremio);
/// `displayTitle` es el de tu idioma (lo que se muestra).
public struct PlayRequest: Sendable {
    public var kind: String
    public var metaID: String
    public var videoID: String
    public var originalTitle: String
    public var displayTitle: String
    public var episodeLabel: String
    public var poster: String?
    public var year: String?
    public var meta: JSON?                 // la ficha original: de ahí salen el siguiente episodio y las duraciones
    public var fromStart = false
    /// El segundo exacto donde empezar («Seguir en el iPhone» desde la TV); sin él, donde te quedaste.
    public var startPosition: Double?
    public var localFile: URL?             // una descarga: se reproduce sin red
    public var localSubtitles: [URL] = []
    /// Lo que se sabe de los subtítulos guardados con la descarga (fuente, copia, si es para sordos), para nombrarlos.
    public var savedSubtitles: [SavedSubtitle] = []
    public var binge: String?              // el grupo de la fuente anterior (misma calidad e idioma)
    public var sourceIndex: Int?           // una fuente elegida en la lista
    /// Desde Mi media: primero tu copia de OneDrive (también para el siguiente episodio); si falla, Real-Debrid.
    public var ownCopy = false
    /// Empieza en vertical (la ruleta de Los Simpson: la tele ya está de pie); girar el teléfono lo acuesta igual.
    public var startPortrait = false
    /// Un canal de Inicio: se ve como la tele, sin guardar el avance ni avisar a Trakt (no mete capítulos sueltos en «Seguir
    /// viendo» ni mueve el siguiente de la serie). Lo que sigue al terminar hereda lo mismo.
    public var offTheRecord = false

    public init(kind: String, metaID: String, videoID: String, originalTitle: String, displayTitle: String, episodeLabel: String = "", poster: String? = nil,
                year: String? = nil, meta: JSON? = nil, fromStart: Bool = false, localFile: URL? = nil, localSubtitles: [URL] = [], savedSubtitles: [SavedSubtitle] = [], binge: String? = nil, sourceIndex: Int? = nil) {
        self.kind = kind; self.metaID = metaID; self.videoID = videoID; self.originalTitle = originalTitle; self.displayTitle = displayTitle
        self.episodeLabel = episodeLabel; self.poster = poster; self.year = year; self.meta = meta; self.fromStart = fromStart
        self.localFile = localFile; self.localSubtitles = localSubtitles; self.savedSubtitles = savedSubtitles; self.binge = binge; self.sourceIndex = sourceIndex
    }
}

public struct UpNext: Sendable, Equatable {
    public var videoID: String
    public var label: String           // «T2 · E6»
    public var title: String
    public var secondsLeft: Int
    /// La imagen del episodio (Cinemeta), si la trae.
    public var thumbnail: String? = nil
}

public enum PlayerNotice: Sendable, Equatable {
    case triedAnotherSource(attempt: Int)
    case audioNotInYourLanguage
    /// Esta versión no trae el idioma que quieres (o no su variante: latino) y otra sí: se ofrece cambiar sin perder el punto.
    /// `language` es el código que quieres («es-419»); `have`, lo que trae esta («en», «es-ES»).
    case otherVersionHasYourLanguage(language: String, have: [String], sourceIndex: Int)
    /// La versión que elegiste no abrió: se volvió a la que veías, en el mismo segundo.
    case switchFailedBack
    /// Real-Debrid aún no tiene esa versión (mandó su video corto de «descargando» en lugar de la película).
    case notReadyOnRealDebrid
}

/// Un idioma de audio que solo trae otra versión (otro archivo): a cuál iría y qué tan seguro es que lo trae.
public struct OtherVersionAudio: Sendable, Equatable, Identifiable {
    public let code: String          // «es-419»
    public let sourceIndex: Int
    public let quality: String       // «1080p» (vacío si no se sabe)
    public let instant: Bool         // ya está en Real-Debrid
    /// Comprobado, o lo dice el nombre o el sitio. Si no (se supone por el original, o no se sabe): «tal vez».
    public let sure: Bool
    public var id: String { code }
}

/// El siguiente episodio ya descargado (para seguir viendo sin conexión).
public struct LocalEpisode: Sendable, Equatable {
    public var file: URL
    public var subtitles: [URL]
    public var saved: [SavedSubtitle]
    public init(file: URL, subtitles: [URL] = [], saved: [SavedSubtitle] = []) { self.file = file; self.subtitles = subtitles; self.saved = saved }
}
