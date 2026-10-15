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
        public static let scrimStrong = 0.92, badge = 0.8, pressed = 0.8, disabled = 0.4, shrink = 0.85
    }
    /// Medidas fijas (puntos): el mínimo táctil de iOS, miniaturas, tarjetas.
    public enum Size { public static let touchTarget = 44.0, thumbSmall = 48.0, cardMax = 320.0, grabber = 40.0, grabberHeight = 5.0, logo = 80.0 }
    /// Relaciones de aspecto de las imágenes.
    public enum Aspect { public static let poster = 2.0 / 3.0, hero = 16.0 / 11.0, still = 16.0 / 9.0 }
    /// Esperas de la interfaz (segundos).
    public enum Timing { public static let controlsHide = 4.0, banner = 4.0, searchDebounce = 0.3, tick = 1.0, longPressDelay = 0.4 }
}

/// Convierte «#rrggbb» en sus componentes 0…1.
public func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
    var text = hex.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("#") { text.removeFirst() }
    guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
    return (Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255, Double(value & 0xff) / 255)
}
