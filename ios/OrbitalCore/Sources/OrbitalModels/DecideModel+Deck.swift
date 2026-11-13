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

    /// Todo · Películas · Series sin volver a barajar (Fernando, 13 nov 2026): lo que se veía con el tipo de antes se recuerda
    /// y, al regresar a un tipo que ya viste, salen los mismos tres (sin lo que apartaste mientras). Un tipo nuevo se baraja
    /// una vez. Solo «Barajar» o cambiar otro filtro vuelven a barajar (`apply` olvida lo recordado). El mazo no necesita
    /// memoria: su orden es fijo por día (`MatchDeckModel.deck`) y lo que pasaste o guardaste no vuelve.
    public func setKind(_ new: String?) async {
        if !switchKind(new) { await applyKeepingKinds() }
    }

    /// La parte inmediata de `setKind` (para que la pastilla y los carteles cambien en la misma animación): cambia el tipo y,
    /// si ya se había visto, regresa sus tres. Devuelve si los regresó; si no, falta `applyKeepingKinds()`.
    @discardableResult
    public func switchKind(_ new: String?) -> Bool {
        guard new != kind else { return true }
        kindMemory[kind ?? ""] = KindMemory(picks: picks, pick: pick, shown: shown, order: order, exhausted: exhausted)
        kind = new
        let gone = notToday().union(pendingDismissals)
        guard let saved = kindMemory[new ?? ""], case let kept = saved.picks.filter({ !gone.contains($0.imdb) }), !kept.isEmpty else { return false }
        dropUpcoming()
        order = saved.order; shown = saved.shown; exhausted = saved.exhausted
        picks = kept
        select(saved.pick.flatMap { p in kept.first { $0.imdb == p.imdb } } ?? kept[0])
        fillUpcoming()
        enrichPicks(kept)
        return true
    }

    /// Barajar un tipo que aún no se veía sin olvidar lo recordado de los demás.
    public func applyKeepingKinds() async {
        keepingKinds = true
        defer { keepingKinds = false }
        await apply()
    }

    /// Cambia cuando cambia lo que filtra el mazo (para volver a barajarlo), no con el tiempo ni el ánimo.
    public var deckKey: String {
        let parts: [String] = [kind ?? "", genres.sorted().joined(separator: ","), sourceIDs.sorted().joined(separator: ","),
                               decades.sorted().map(String.init).joined(separator: ","), "\(minRating)", "\(minLetterboxd)",
                               fame.rawValue, awards.sorted().joined(separator: ","), "\(candidatesPool.count)"]
        return parts.joined(separator: "|")
    }
}
