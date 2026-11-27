import Foundation
import OrbitalCore

/// Los tipos que usa la ficha (`TitleModel`): el renglón de un episodio, lo que se sabe de las fuentes de «Ver» y una de tus
/// listas de Trakt. Salieron de `TitleModel.swift` (27 nov 2026) para que no pasara de su tope de líneas (`FileBudgetTests`).

public struct EpisodeRow: Equatable, Identifiable {
    public var id: String                  // el video id
    public var season: Int
    public var number: Int
    public var title: String               // en tu idioma
    public var hasTitle: Bool
    public var overview: String
    public var thumbnail: String?
    public var watched: Bool
    public var progress: Double?           // a medias
    public var timeLeft: String
    public var leftMinutes: Int
    public var download: DownloadState?
    /// Todavía no sale: cuándo (nil = ya salió o no se sabe). Se ve con su fecha y no se puede reproducir ni bajar.
    public var airs: Date? = nil
    /// El idioma del nombre o de la sinopsis cuando no es el tuyo (no había traducción): la ficha dice «En inglés».
    public var titleLanguage: String? = nil
    public var overviewLanguage: String? = nil
    /// Lo que se marca una vez en el renglón: el idioma colado del nombre o, si no, el de la sinopsis.
    public var foreignLanguage: String? { (hasTitle ? titleLanguage : nil) ?? (overview.isEmpty ? nil : overviewLanguage) }
}

/// Lo que se sabe de las fuentes del video de «Ver» antes de abrir el reproductor.
public enum SourceCheck: Equatable, Sendable { case unknown, available, none, offline }

/// Una de tus listas de Trakt, con si el título que ves está en ella.
public struct SavedList: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var contains: Bool
    /// Cuándo cambió en Trakt (las recientes van arriba en «Guardar en…»); nil sin conexión o si Trakt no lo dijo.
    public var updatedAt: Date? = nil

    public init(id: String, name: String, contains: Bool, updatedAt: Date? = nil) {
        self.id = id; self.name = name; self.contains = contains; self.updatedAt = updatedAt
    }
}
