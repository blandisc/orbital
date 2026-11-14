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

extension DecideModel {
    /// De «Una por una» a «Tres que caben» con la carta que estabas viendo (Fernando, 13 nov 2026: «mejor la transición del
    /// póster de cuando estás en el Tinder de películas a cuando estás en la sección de 3»): si no está entre los tres y cabe
    /// en lo de esta noche (tiempo y ánimo), entra en el lugar de la elegida y queda elegida, así la carta se encoge hasta su
    /// cartel. Devuelve si quedó entre los tres (si no cabe, el trío no cambia).
    @discardableResult
    public func bringIn(_ s: Suggestion) -> Bool {
        if let same = picks.first(where: { $0.imdb == s.imdb }) { select(same); return true }
        guard let v = verdict(s, filters), v.matches, v.fits else { return false }
        coalescing {
            var next = picks
            if let at = next.firstIndex(where: { $0.imdb == pick?.imdb }) { next[at] = s } else if next.count < 3 { next.append(s) } else { next[next.count / 2] = s }
            shown.insert(s.imdb)
            picks = next
        }
        select(s)
        return true
    }
}
