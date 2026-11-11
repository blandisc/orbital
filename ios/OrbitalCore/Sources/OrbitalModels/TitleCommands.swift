import Foundation

/// Lo que la ficha abierta deja hacer desde el menú y el teclado (iPad, Mac: ⌘↩ ver, ⌘D guardar, ⌥⌘V versión). Lo publica
/// `TitleView` como valor enfocado (`focusedSceneValue`) y lo lee `AppCommands`.
///
/// Igualdad por el título (revisión del 11 nov 2026). Antes era siempre «igual», por el repintado sin fin de `PlayerCommands`
/// (un valor enfocado que cambia en cada pasada repinta todo). Pero siempre «igual» también dejaba vivo el valor de la PRIMERA
/// ficha: al pasar de una ficha a otra sin que SwiftUI lo cambiara, ⌘↩ podía poner la anterior. Ahora cuenta como cambiado solo
/// cuando cambia el título: en la misma ficha sigue igual en cada pasada (sin repintado) y en otra ficha actúa sobre ella.
public struct TitleCommands: Equatable {
    /// El título al que pertenece (`kind:metaID`).
    public var id: String
    public var play: () -> Void
    public var save: () -> Void
    public var versions: () -> Void

    public init(id: String, play: @escaping () -> Void, save: @escaping () -> Void, versions: @escaping () -> Void) {
        self.id = id; self.play = play; self.save = save; self.versions = versions
    }

    public init(kind: String, metaID: String, play: @escaping () -> Void, save: @escaping () -> Void, versions: @escaping () -> Void) {
        self.init(id: "\(kind):\(metaID)", play: play, save: save, versions: versions)
    }

    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}
