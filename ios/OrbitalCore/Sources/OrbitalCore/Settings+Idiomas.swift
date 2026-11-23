import Foundation

extension AppSettings {
    /// El que vale para títulos y sinopsis (ID-A, Fernando, 22 nov 2026: «el idioma del app y el idioma de los metadatos»):
    /// `metadataLanguage` si lo elegiste o, si no, el de la app (lo de siempre: al llegar nada cambia).
    public var titleLanguage: String { metadataLanguage ?? uiLanguage }
}
