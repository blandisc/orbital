import CoreGraphics

/// La receta de la ficha ancha (iPad y Mac; Fernando, 17 nov 2026: «replantea con una receta el cómo se debe armar»):
///
/// 1. **Escenario.** El arte y la columna viven en un escenario centrado de proporción máxima `stageAspect` (2.4:1). En una
///    ventana más ancha (el ultrawide) el escenario no crece: queda al centro y a los lados sigue el mismo arte difuminado,
///    sin orillas. Así nada queda clavado a la izquierda ni flota en medio de un hueco oscuro.
/// 2. **Margen.** La columna («Ver», acciones, sinopsis) y las filas de abajo empiezan en la orilla del escenario más un
///    margen que crece con él (`marginShare`, mínimo `minMargin`, el de la TV).
/// 3. **Vertical.** Si la ventana es más alta que ancha (`portraitBelow`, el iPad parado), la columna va al centro con el
///    texto centrado y el arte se centra en el sujeto (`FocalPoint`); el velo de la izquierda no se usa.
public struct WideStage: Equatable, Sendable {
    /// El ancho del escenario y dónde empieza.
    public let width: CGFloat
    public let x: CGFloat
    /// Margen de la columna dentro del escenario.
    public let margin: CGFloat
    /// Vertical: columna centrada.
    public let portrait: Bool
    /// Cuánto crecen la columna y el logo con un escenario grande (1 hasta `growFrom`).
    public let grow: CGFloat

    /// El ancho de la columna centrada (vertical): lo de abajo arranca en su orilla, no en el margen de la ventana.
    public let column: CGFloat
    let windowWidth: CGFloat
    /// Dónde empieza lo de abajo (pestañas, episodios, filas), desde la orilla de la ventana. Vertical: el margen de la
    /// pantalla, no la orilla de la columna centrada (Fernando, 23 nov 2026: «deberían de empezar más hacia la izquierda;
    /// estás desperdiciando ahí espacio»; antes, I1, arrancaban a ~157 pt en un iPad de 834). Lo de arriba sigue centrado.
    public var leading: CGFloat { portrait ? margin : x + margin }
    /// Si sobra ventana a los lados (hace falta el arte difuminado).
    public var hasSides: Bool { x > 0.5 }

    public init(window: CGSize, heroHeight: CGFloat, stageAspect: CGFloat, portraitBelow: CGFloat, marginShare: CGFloat, minMargin: CGFloat,
                maxMargin: CGFloat = .greatestFiniteMagnitude, growFrom: CGFloat = .greatestFiniteMagnitude, growMax: CGFloat = 1, column: CGFloat = 0) {
        let w = max(0, window.width), h = max(1, heroHeight)
        windowWidth = w
        portrait = w / max(1, window.height) < portraitBelow
        width = min(w, (h * stageAspect).rounded())
        x = ((w - width) / 2).rounded()
        margin = min(maxMargin, max(minMargin, (width * marginShare).rounded()))
        grow = min(growMax, max(1, width / growFrom))
        self.column = column * grow
    }
}
