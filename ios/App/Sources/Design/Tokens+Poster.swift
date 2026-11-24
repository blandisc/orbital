import SwiftUI

/// Un título sin póster (Fernando, 23 nov 2026: «un fondo más bonito… sobre todo cuando hacemos búsquedas y encontramos cosas
/// raras»): su nombre sobre un resplandor de color, como la tarjeta sin arte de la TV (`.card--no-art`), en vez de un cuadro gris
/// con el nombre chiquito. El color sale del nombre (siempre el mismo para el mismo título) y es uno de los tintes de la app.
extension DS.Poster {
    static let missingHues: [Color] = [DS.ListTint.spark, DS.ListTint.series, DS.ListTint.calendar, DS.ListTint.trend,
                                       DS.ListTint.bookmark, DS.ListTint.library]
    /// Cuánto color lleva el resplandor arriba a la izquierda y cuánto le queda abajo (los de la TV: 45 % y 14 %).
    static let missingGlow = 0.45, missingBase = 0.14
    /// El dibujo de película, tenue, en la parte de arriba (ancho del póster).
    static let missingIconShare: CGFloat = 0.36
    /// En una caja ancha (un episodio, «Seguir viendo», un tráiler) el dibujo solo, centrado, de este alto de la caja: su nombre
    /// ya va al lado o abajo (23 nov 2026: el de póster vertical quedaba subido, con el número suelto en la esquina).
    static let missingWideIconShare: CGFloat = 0.42
    /// El nombre se achica hasta aquí antes de cortarse (cuatro renglones).
    static let missingTextShrink: CGFloat = 0.7

    /// El tinte de un título: el mismo en cada visita (no `hashValue`, que cambia en cada arranque).
    static func missingHue(_ title: String) -> Color {
        let sum = title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return missingHues[sum % missingHues.count]
    }
}
