import Foundation

/// Adónde va un título al tocar «Guardar» sin elegir lista. **La regla vive solo aquí**: a Mi lista, que vive en el teléfono y
/// es tu watchlist de Trakt (la que ves en la TV, en «Para ti» y en cualquier app de Trakt). Sin Trakt (o un título sin IMDb,
/// que Trakt no conoce) se queda en el teléfono. La usan la ficha, el menú de los pósters (`AppEnvironment.save`) y la hoja
/// «Guardar en…».
public enum SaveDestination: String, Equatable, Sendable, CaseIterable {
    case myList

    public static func preferred(traktLinked: Bool, metaID: String) -> SaveDestination { .myList }

    /// Las fijas de «Guardar en…» (arriba de tus listas de Trakt).
    public static func fixed(traktLinked: Bool, metaID: String) -> [SaveDestination] { [.myList] }
}

/// Qué hace un toque en «Guardar» de la ficha.
public enum QuickSave: Equatable, Sendable {
    /// No está en ningún lado: se guarda en Mi lista.
    case add(SaveDestination)
    /// Solo está en Mi lista: se quita (con «Deshacer»).
    case remove(SaveDestination)
    /// Está en otras listas: que elijas en «Guardar en…» (un toque no adivina de cuál quitarlo).
    case choose

    public static func decide(inList: Bool, inOtherLists: Bool) -> QuickSave {
        switch (inList, inOtherLists) {
        case (false, false): return .add(.myList)
        case (true, false): return .remove(.myList)
        default: return .choose
        }
    }
}
