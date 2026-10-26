import Foundation

/// Cómo se recoge el arte de la ficha al desplazar (como Apple TV o Música): todo sale de cuánto subió el arte respecto a su
/// alto (`progress`, 0 arriba … 1 recogido) con curvas suaves (smoothstep), nunca a saltos. Solo aritmética: la vista la aplica
/// con `visualEffect` (sin recalcular imágenes) y los valores vienen de los tokens (`DS.HeroCollapse`).
public struct HeroCollapse: Equatable, Sendable {
    public struct Tuning: Equatable, Sendable {
        /// Qué parte del desplazamiento se queda atrás el arte (0: se va con el contenido).
        public var parallax: Double
        /// Cuánto se encoge ya recogido (0.05 = 5 %).
        public var shrink: Double
        /// El desenfoque máximo (pt) y desde qué progreso empieza (antes el arte se ve nítido).
        public var blur: Double
        public var blurFrom: Double
        /// El velo parejo del color del fondo, ya recogido (0…1).
        public var dim: Double
        /// A qué progreso el degradado que sube desde abajo cubre todo el arte.
        public var riseEnd: Double
        /// Desde qué progreso el arte se desvanece (termina en 1).
        public var fadeFrom: Double
        /// A qué progreso el logo y la frase ya se fueron, y cuánto se encogen mientras.
        public var contentFadeEnd: Double
        public var contentShrink: Double

        public init(parallax: Double, shrink: Double, blur: Double, blurFrom: Double, dim: Double, riseEnd: Double, fadeFrom: Double,
                    contentFadeEnd: Double, contentShrink: Double) {
            self.parallax = parallax; self.shrink = shrink; self.blur = blur; self.blurFrom = blurFrom; self.dim = dim
            self.riseEnd = riseEnd; self.fadeFrom = fadeFrom; self.contentFadeEnd = contentFadeEnd; self.contentShrink = contentShrink
        }
    }

    /// 0 con el arte entero a la vista, 1 cuando ya subió todo su alto.
    public var progress: Double
    /// Lo que baja el arte para quedarse atrás (pt, positivo hacia abajo).
    public var offset: Double
    /// Escala del arte: < 1 al recogerse, > 1 al jalar hacia abajo (se estira desde abajo).
    public var scale: Double
    public var blur: Double
    /// Opacidad del velo parejo y qué parte del alto cubre el degradado de abajo (0…1).
    public var dim: Double
    public var rise: Double
    public var artOpacity: Double
    /// El logo y la frase: se van antes que el arte (no se quedan detrás de los datos).
    public var contentOpacity: Double
    public var contentScale: Double

    /// `minY`: dónde está la parte de arriba del arte en el desplazamiento (negativo al subir, positivo al jalar hacia abajo).
    /// Con «Reducir movimiento» no hay parallax, escala, desenfoque ni degradado que sube: solo se oscurece y se desvanece.
    public static func at(minY: Double, height: Double, reduceMotion: Bool, tuning t: Tuning) -> HeroCollapse {
        let h = max(height, 1)
        let p = clamp(-minY / h)
        let pull = max(0, minY) / h
        let fade = 1 - smoothstep(t.fadeFrom, 1, p)
        let content = 1 - smoothstep(0, t.contentFadeEnd, p)
        if reduceMotion {
            return HeroCollapse(progress: p, offset: 0, scale: 1, blur: 0, dim: smoothstep(0, 1, p) * t.dim, rise: 0,
                                artOpacity: fade, contentOpacity: content, contentScale: 1)
        }
        return HeroCollapse(progress: p,
                            offset: max(0, -minY) * t.parallax,
                            scale: pull > 0 ? 1 + pull : 1 - smoothstep(0, 1, p) * t.shrink,
                            blur: smoothstep(t.blurFrom, 1, p) * t.blur,
                            dim: smoothstep(0, 1, p) * t.dim,
                            rise: smoothstep(0, t.riseEnd, p),
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
