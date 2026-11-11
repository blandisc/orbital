import SwiftUI

extension DS {
    /// La tarjeta de acción (`ActionTileLabel`): ícono arriba, nombre y, si hace falta, un renglón de estado. Aire parejo
    /// (Fernando, 11 nov 2026: «"Guardar / Viendo" como que tiene muy poco espacio abajo»): el mismo relleno arriba y abajo
    /// (`pad`), un alto mínimo y la caja del ícono, por tipo. `title`: la ficha y «Mi media». `key`: las teclas del control.
    enum ActionTile {
        struct Metrics: Sendable {
            /// El aire arriba y abajo del contenido (el mismo: `padding(.vertical, pad)`).
            let pad: CGFloat
            /// El alto mínimo: con un renglón el contenido queda al centro; con más, la tarjeta crece (el aire no se pierde).
            let minHeight: CGFloat
            /// La caja del ícono (el anillo de la descarga cabe en la misma): el ícono queda a la misma altura en toda la fila.
            let icon: CGFloat
        }
        /// En la ficha: 8 de aire arriba y abajo, 64 de alto con un renglón (lo de antes) y 80 con el renglón del estado.
        static let title = Metrics(pad: DS.Space.s2, minHeight: 64, icon: DS.TitleAction.ringSmall)
        /// Las teclas del control: su alto de siempre (más bajo en pantallas chicas) y 4 de aire (antes 0: con un nombre de dos
        /// renglones el ícono tocaba la orilla).
        @MainActor static var key: Metrics { Metrics(pad: DS.Space.s1, minHeight: DS.Remote.keyHeightFitted, icon: DS.Remote.keyIcon) }
        /// Entre el ícono y el nombre.
        static let gap = DS.Space.s1
        /// La orilla de la caja del ícono que no crece con la letra: con letra grande, el aire sobre el ícono queda igual al
        /// de abajo del último renglón (medido en el SE con accessibility-large).
        static let iconRim = DS.Space.s1
    }
}
