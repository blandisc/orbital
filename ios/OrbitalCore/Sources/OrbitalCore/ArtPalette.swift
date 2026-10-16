import Foundation

/// El color de lo que está al frente, sacado de su arte: la misma cuenta que `orbital/web/js/core/color.js` en la TV, para que
/// la consola y el iPhone se pinten igual con el mismo póster.
///
/// No es el promedio (los pósters promedian a gris café): se agrupan los píxeles por tono y gana el grupo con más peso
/// (cantidad × saturación). De ese tono salen dos colores:
///   - `tint`: muy oscuro, para teñir el fondo (`--art-tint`);
///   - `accent`: claro, para el botón principal y los acentos (`--art-accent` / `--color-primary-art`), con texto oscuro encima.
/// Sin tono (arte gris o que no se pudo leer), los neutros del tema de la TV.
public enum ArtPalette {
    public typealias RGB = (r: Int, g: Int, b: Int)

    /// `--art-tint-neutral` y `--art-accent-neutral` de `themes/orbital.css`.
    public static let neutralTint: RGB = (24, 24, 28), neutralAccent: RGB = (205, 205, 211)

    private static let buckets = 12

    public static func rgbToHsl(_ c: RGB) -> (h: Double, s: Double, l: Double) {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        if maxV == minV { return (0, 0, l) }
        let d = maxV - minV
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == r { h = (g - b) / d + (g < b ? 6 : 0) } else if maxV == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        return (h, s, l)
    }

    public static func hslToRgb(_ h: Double, _ s: Double, _ l: Double) -> RGB {
        func k(_ n: Double) -> Double { (n + h / 30).truncatingRemainder(dividingBy: 12) }
        let a = s * min(l, 1 - l)
        func f(_ n: Double) -> Int { Int((l - a * max(-1, min(k(n) - 3, min(9 - k(n), 1)))) * 255 + 0.5) }   // Math.round de JS
        return (f(0), f(8), f(4))
    }

    /// Tono dominante de una imagen (RGBA plano, 8 bits por canal). nil si es casi gris.
    public static func dominantHue(rgba pixels: [UInt8]) -> (hue: Double, saturation: Double)? {
        var weight = [Double](repeating: 0, count: buckets), hueSum = weight, satSum = weight
        var i = 0
        while i + 3 < pixels.count {
            defer { i += 4 }
            if pixels[i + 3] < 128 { continue }
            let (h, s, l) = rgbToHsl((Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])))
            if s < 0.2 || l < 0.12 || l > 0.9 { continue }   // grises, negros y blancos no cuentan
            let bucket = Int(h / (360 / Double(buckets))) % buckets
            let w = s * (1 - abs(l - 0.5))
            weight[bucket] += w; hueSum[bucket] += h * w; satSum[bucket] += s * w
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return nil }
        return (hueSum[best] / weight[best], satSum[best] / weight[best])
    }

    /// Los dos colores para un tono (`paletteFor`); sin tono, los neutros.
    public static func palette(for dominant: (hue: Double, saturation: Double)?) -> (tint: RGB, accent: RGB) {
        guard let d = dominant else { return (neutralTint, neutralAccent) }
        return (hslToRgb(d.hue, min(d.saturation, 0.55), 0.2), hslToRgb(d.hue, min(max(d.saturation, 0.35), 0.75), 0.76))
    }
}
