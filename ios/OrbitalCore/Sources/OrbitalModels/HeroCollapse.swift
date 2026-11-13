import Foundation

/// Cómo se recoge el arte de la ficha al desplazar (AR1, Fernando, 13 nov 2026: «Se funde»): se va con el contenido, se
/// desenfoca y se desvanece hacia el fondo que de verdad tiene detrás. Sin parallax, sin encogerse y sin velo de color: eso lo
/// sacaba de su marco y dejaba un bloque con el borde recto. Todo sale de cuánto subió el arte respecto a su alto (`progress`,
/// 0 arriba … 1 recogido) con curvas suaves (smoothstep), nunca a saltos. Solo aritmética: la vista la aplica con
/// `visualEffect` (sin recalcular imágenes) y los valores vienen de los tokens (`DS.TitleHero`).
public struct HeroCollapse: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        /// El desenfoque máximo (pt) y desde qué progreso empieza (antes el arte se ve nítido).
        public var blur: Double
        public var blurFrom: Double
        /// Desde qué progreso el arte se desvanece (termina en 1).
        public var fadeFrom: Double
        /// A qué progreso el logo y la frase ya se fueron, y cuánto se encogen mientras.
        public var contentFadeEnd: Double
        public var contentShrink: Double

        public init(blur: Double, blurFrom: Double, fadeFrom: Double, contentFadeEnd: Double, contentShrink: Double) {
            self.blur = blur; self.blurFrom = blurFrom; self.fadeFrom = fadeFrom
            self.contentFadeEnd = contentFadeEnd; self.contentShrink = contentShrink
        }
    }

    /// 0 con el arte entero a la vista, 1 cuando ya subió todo su alto.
    public var progress: Double
    /// Escala del arte: > 1 solo al jalar hacia abajo (se estira desde abajo); al recogerse no cambia.
    public var scale: Double
    public var blur: Double
    public var artOpacity: Double
    /// El logo y la frase: se van antes que el arte (no se quedan detrás de los datos).
    public var contentOpacity: Double
    public var contentScale: Double

    /// `minY`: dónde está la parte de arriba del arte en el desplazamiento (negativo al subir, positivo al jalar hacia abajo).
    /// Con «Reducir movimiento» no hay escala ni desenfoque: solo se desvanece. `card`: el arte es una tarjeta (modo claro) y
    /// sube nítida con el contenido, sin desenfoque ni desvanecido (desenfocada se lavaba a un rectángulo gris).
    public static func at(minY: Double, height: Double, reduceMotion: Bool, card: Bool = false, tuning t: Tuning) -> HeroCollapse {
        let h = max(height, 1)
        let p = clamp(-minY / h)
        let pull = max(0, minY) / h
        let fade = card ? 1 : 1 - smoothstep(t.fadeFrom, 1, p)
        let content = 1 - smoothstep(0, t.contentFadeEnd, p)
        if reduceMotion {
            return HeroCollapse(progress: p, scale: 1, blur: 0, artOpacity: fade, contentOpacity: content, contentScale: 1)
        }
        return HeroCollapse(progress: p,
                            scale: 1 + pull,
                            blur: card ? 0 : smoothstep(t.blurFrom, 1, p) * t.blur,
                            artOpacity: fade,
                            contentOpacity: content,
                            contentScale: 1 - smoothstep(0, t.contentFadeEnd, p) * t.contentShrink)
    }

    /// La curva suave de siempre (Hermite): 0 antes de `edge0`, 1 después de `edge1`, sin quiebres en las orillas.
    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else { return x < edge0 ? 0 : 1 }
        let t = clamp((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
}
