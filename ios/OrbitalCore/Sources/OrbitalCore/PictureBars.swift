import Foundation

/// Rayas negras pintadas dentro del archivo: un capítulo casi cuadrado que alguien rellenó con negro a los lados para que mida
/// 16:9 (Fernando, 21 nov 2026: *It's Always Sunny* T4 en una versión «1080p AI»). El motor dice 16:9 y en vertical el video
/// salía con dos rayas negras a los lados; con la proporción de la imagen de verdad se ve como un 4:3 de verdad (Los Simpson).
///
/// Solo los lados: una raya de arriba o de abajo puede traer subtítulos pintados y no se recorta.
public enum PictureBars {
    /// Más oscuro que esto es negro (0–255; el negro de un video comprimido no es 0 exacto).
    public static let darkLuma: UInt8 = 28
    /// Una columna es imagen si al menos esta parte de sus pixeles no es negra (una mota de ruido no cuenta).
    public static let brightShare = 0.02
    /// Una raya menor a esto de cada lado no se quita: no se nota y puede ser la orilla oscura de la escena.
    public static let minBar = 0.04
    /// Las dos rayas tienen que medir casi lo mismo (un relleno siempre es parejo; una escena oscura de un lado, no).
    public static let maxUneven = 0.02
    /// Cuadros que se miran, separados, antes de decidir: una escena oscura en uno no engaña si en otro hay luz a la orilla.
    public static let samplesNeeded = 3

    public struct Sides: Equatable, Sendable {
        public var left: Double, right: Double
        public init(left: Double, right: Double) { self.left = left; self.right = right }
    }

    /// Qué parte del ancho es negra a la izquierda y a la derecha de un cuadro en grises (`luma`, renglón por renglón).
    /// nil si todo el cuadro es negro (un fundido): ese cuadro no dice nada.
    public static func sides(luma: [UInt8], width: Int, height: Int) -> Sides? {
        guard width > 0, height > 0, luma.count >= width * height else { return nil }
        let needed = max(1, Int((Double(height) * brightShare).rounded(.up)))
        func isPicture(_ x: Int) -> Bool {
            var bright = 0
            for y in 0..<height where luma[y * width + x] > darkLuma {
                bright += 1
                if bright >= needed { return true }
            }
            return false
        }
        guard let first = (0..<width).first(where: isPicture), let last = (0..<width).reversed().first(where: isPicture) else { return nil }
        return Sides(left: Double(first) / Double(width), right: Double(width - 1 - last) / Double(width))
    }

    /// La proporción de la imagen de verdad (ancho entre alto) si todas las muestras traen rayas parejas a los lados; nil si no
    /// hay rayas, si faltan muestras o si no cuadran. Cada lado se queda con lo menos que midió: la raya pintada está en todos los
    /// cuadros y lo oscuro de una escena no.
    public static func pictureAspect(frameAspect: Double, samples: [Sides]) -> Double? {
        guard samples.count >= samplesNeeded, frameAspect > 0 else { return nil }
        let left = samples.map(\.left).min() ?? 0, right = samples.map(\.right).min() ?? 0
        guard min(left, right) >= minBar, abs(left - right) <= maxUneven, left + right < 0.5 else { return nil }
        return frameAspect * (1 - left - right)
    }
}
