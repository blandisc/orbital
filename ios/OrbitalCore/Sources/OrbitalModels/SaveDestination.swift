import Foundation

/// Adónde va un título al tocar «Guardar» sin elegir lista. **La regla vive solo aquí**: con Trakt conectado, tu watchlist de
/// Trakt (la que ves en la TV, en «Para ti» y en cualquier app de Trakt); sin Trakt (o un título sin IMDb, que Trakt no
/// conoce), Mi lista de Stremio, como siempre. La usan la ficha (tocar «Guardar» y el orden de su menú), el menú de los
/// pósters (`AppEnvironment.save`) y la hoja «Guardar en…» (cuál de las fijas va primero).
public enum SaveDestination: String, Equatable, Sendable, CaseIterable {
    case traktWatchlist
    case stremioLibrary

    public static func preferred(traktLinked: Bool, metaID: String) -> SaveDestination {
        traktLinked && metaID.hasPrefix("tt") ? .traktWatchlist : .stremioLibrary
    }

    /// Las dos fijas, la de por omisión primero (sin Trakt solo queda Mi lista).
    public static func fixed(traktLinked: Bool, metaID: String) -> [SaveDestination] {
        let first = preferred(traktLinked: traktLinked, metaID: metaID)
        guard first == .traktWatchlist else { return [.stremioLibrary] }
        return [.traktWatchlist, .stremioLibrary]
    }
}

/// Qué hace un toque en «Guardar» de la ficha.
public enum QuickSave: Equatable, Sendable {
    /// No está en ningún lado: se guarda en la de por omisión.
    case add(SaveDestination)
    /// Solo está en la de por omisión: se quita (con «Deshacer»).
    case remove(SaveDestination)
    /// Está en otras listas: que elijas en «Guardar en…» (un toque no adivina de cuál quitarlo).
    case choose

    public static func decide(preferred: SaveDestination, inLibrary: Bool, inWatchlist: Bool, inOtherLists: Bool) -> QuickSave {
        let inPreferred = preferred == .traktWatchlist ? inWatchlist : inLibrary
        let elsewhere = (preferred == .traktWatchlist ? inLibrary : inWatchlist) || inOtherLists
        switch (inPreferred, elsewhere) {
        case (false, false): return .add(preferred)
        case (true, false): return .remove(preferred)
        default: return .choose
        }
    }
}
