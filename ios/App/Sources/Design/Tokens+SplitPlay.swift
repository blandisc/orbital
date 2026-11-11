import SwiftUI

extension DS {
    /// El botón principal partido de la ficha (`SplitPlayButton`, L3, 11 nov 2026): «Ver» a la izquierda y la versión a la
    /// derecha, en una sola forma. Aire parejo: la división deja el mismo aire arriba que abajo (`dividerInset`).
    enum SplitPlay {
        /// Entre la versión («🇲🇽 1080p») y su flechita.
        static let gap = DS.Space.s1
        /// El grueso de la división entre los dos lados.
        static let divider = DS.Stroke.regular
        /// Cuánto se aparta la división de la orilla de arriba y de la de abajo (la misma).
        static let dividerInset = DS.Space.s3
        /// Qué tan marcada va la división: tenue, del color de la letra del botón.
        static let dividerOpacity = DS.Opacity.faint
    }
}
