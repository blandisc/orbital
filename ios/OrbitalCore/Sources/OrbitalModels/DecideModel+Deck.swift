import Foundation
import OrbitalCore

/// «Una sola puerta» (DE2, Fernando, 13 nov 2026: «Construye DE1 y DE2 para ver cómo se ven»): «Decide por mí» tiene dos
/// pestañas, «Tres que caben» y «Una por una» (el mazo), y las dos usan los mismos filtros de «Afinar».
extension DecideModel {
    /// Las dos maneras de decidir, con los nombres de la TV (`DECIDE_MODES` en `orbital/web/js/components/decide.js`).
    public enum Mode: String, CaseIterable, Sendable { case trio, deck }

    /// Lo que va al mazo: lo mismo que filtra «Afinar» (géneros, épocas, calificación, fama, premios y listas) y el tipo. El
    /// tiempo y el ánimo son de «Tres que caben» (son de esta noche; el mazo es para guardar). Sin lo que apartaste hoy.
    public func deckPool() -> [Suggestion] {
        var f = filters
        f.mood = nil
        let skipped = notToday()
        return candidatesPool.filter { s in
            guard !skipped.contains(s.imdb), f.kind == nil || s.kind == f.kind, let v = verdict(s, f) else { return false }
            return v.matches
        }
    }

    /// Cambia cuando cambia lo que filtra el mazo (para volver a barajarlo), no con el tiempo ni el ánimo.
    public var deckKey: String {
        let parts: [String] = [kind ?? "", genres.sorted().joined(separator: ","), sourceIDs.sorted().joined(separator: ","),
                               decades.sorted().map(String.init).joined(separator: ","), "\(minRating)", "\(minLetterboxd)",
                               fame.rawValue, awards.sorted().joined(separator: ","), "\(candidatesPool.count)"]
        return parts.joined(separator: "|")
    }
}
