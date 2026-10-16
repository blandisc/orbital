import Foundation

/// Los valores de diseño de Orbital, sin SwiftUI (se prueban aquí contra `palette.json`; la app los convierte a `Color`).
/// «Nada se crea suelto»: las pantallas usan estos tokens, no colores ni medidas a mano.
public enum DesignTokens {
    /// Paleta única: los mismos valores que `orbital/web/styles/palette.json`.
    public static let palette: [String: String] = [
        "ink-1000": "#070708", "ink-950": "#0c0c0e", "ink-900": "#131316", "ink-850": "#18181c", "ink-800": "#1e1e23",
        "ink-700": "#2a2a30", "ink-500": "#55555d", "ink-300": "#a3a3ab", "ink-200": "#cdcdd3", "paper": "#f5f4f0",
        "red-400": "#f0574d", "amber-300": "#f4c24d", "teal-300": "#5fd6c6",
        "pad-green": "#5cbf6d", "pad-red": "#e2514a", "pad-blue": "#4a8ae8", "pad-yellow": "#eec03a",
    ]

    /// Espacio (puntos): 4, 8, 12, 16, 20, 24, 32, 40, 56.
    public enum Space { public static let s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0, s8 = 32.0, s10 = 40.0, s14 = 56.0 }
    public enum Radius { public static let xs = 5.0, sm = 7.0, md = 10.0, lg = 13.0, xl = 18.0, xxl = 22.0, pill = 999.0 }
    /// Tamaños de letra (se escalan con Dynamic Type, que hace de «Tamaño del texto»).
    public enum TextSize { public static let xs = 11.0, sm = 12.5, md = 15.0, lg = 17.0, xl = 22.0, xxl = 28.0, display = 34.0 }
    /// Duraciones en segundos; con «Reducir movimiento» valen 0.
    public enum Motion { public static let fast = 0.12, base = 0.2, slow = 0.35, enter = 0.45, tint = 0.6 }
    public enum Opacity {
        public static let hairline = 0.09, fill = 0.10, fillStrong = 0.16, faint = 0.5, track = 0.2, scrim = 0.62
        public static let scrimStrong = 0.92, badge = 0.8, pressed = 0.8, disabled = 0.4, shrink = 0.85, subtitleShadow = 0.9
    }
    /// Subtítulos sobre el video: letra mínima, cuánto suben con los controles a la vista, espacio entre líneas
    /// (fracción de la letra), margen con el borde del video (fracción de su alto), sombra y contorno (fracción
    /// de la letra, para leerse sobre fondos claros).
    public enum Subtitle { public static let minFont = 15.0, liftWithControls = 72.0, lineGap = 0.15, edgeMargin = 0.05, shadowRadius = 0.08, outlineWidth = 0.06 }
    /// Medidas fijas (puntos): el mínimo táctil de iOS, miniaturas, tarjetas.
    public enum Size {
        public static let touchTarget = 44.0, thumbSmall = 48.0, cardMax = 320.0, grabber = 40.0, grabberHeight = 5.0, logo = 80.0, gaugeScale = 0.45
        /// El logo de una plataforma (Netflix, Disney+…) en un chip o un encabezado: siempre la misma altura, venga el logo
        /// cuadrado o apaisado.
        public static let platformLogo = 18.0
    }
    /// Relaciones de aspecto de las imágenes.
    public enum Aspect { public static let poster = 2.0 / 3.0, hero = 16.0 / 11.0, still = 16.0 / 9.0 }
    /// Esperas de la interfaz (segundos).
    public enum Timing {
        public static let controlsHide = 4.0, banner = 4.0, searchDebounce = 0.3, tick = 1.0, longPressDelay = 0.4
        /// Cuánto se queda a la vista el indicador de brillo o volumen después de soltar, antes de desvanecerse.
        public static let gestureIndicatorHold = 1.0
    }
    /// Gestos del reproductor (brillo, volumen, buscar arrastrando, 2× manteniendo el dedo), como en Infuse.
    public enum Gesture {
        /// Puntos de arrastre antes de decidir si el gesto es horizontal o vertical (y de que el toque deje de ser toque).
        public static let axisThreshold = 12.0
        /// Arrastrar horizontalmente toda la pantalla vale esta fracción de la duración…
        public static let seekMaxFraction = 0.10
        /// …o este tope en segundos, lo que sea menor.
        public static let seekMaxSeconds = 180.0
    }
    /// El mosaico de «Para ti» (como `foryou-mosaic.js` en la TV): cuánto se ensancha la columna enfocada,
    /// cuánto se espera quieto antes del ambiente o de «cobrar vida», y a qué ritmo sube sola cada columna.
    public enum Mosaic {
        public static let columnsPortrait = 4, columnsLandscape = 6
        public static let growRatio = 1.8
        public static let idleSeconds = 30.0, aliveSeconds = 2.2, driftTick = 1.0
        public static let driftPerSecond = 16.0
        public static let bufferHeight = 360.0
        /// La fila enfocada, en alto, × el ancho de su columna: con las columnas angostas del iPhone
        /// hace falta más que en la TV (0,64) para que quepan etiqueta + logo + dato sin encimarse.
        public static let focusedRowRatio = 1.6
    }
}

/// Convierte «#rrggbb» en sus componentes 0…1.
public func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
    return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
}
