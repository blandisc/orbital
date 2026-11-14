import Foundation
import OrbitalCore

/// El mapa de «Lo que ves» (día por día, como el de GitHub): qué días entran y qué tan fuerte se pinta cada uno.
/// Fernando, 14 nov 2026: «se traba cuando entras a la gráfica… no te está poniendo más fuerte los días que ves más».
/// - Lo que marcaste «No sé cuándo» Trakt lo guarda en 1970 (o en el estreno): no es un día en que viste. Sin quitarlo, el
///   mapa se estiraba miles de semanas atrás (se trababa) y ese día gigante dejaba a todos los demás del mismo azul pálido.
/// - El tono va por niveles (1 a 3) según cómo se compara el día con tus otros días, no contra el día más grande: un maratón
///   no apaga el resto del año.
public enum WatchingHeat {
    /// Lo más atrás que llega el mapa (tres años); lo de antes se ve en «Tu año» de ese año.
    public static let maxWeeks = 156
    /// Lo que cuenta un video sin duración en Trakt (si no, un día con capítulos sin `runtime` se veía vacío).
    public static let fallbackMinutes = 45
    /// Antes de esto no hay fecha de verdad: es el «No sé cuándo» de Trakt.
    public static let unknownBefore = Date(timeIntervalSince1970: 86_400 * 366)

    /// Los minutos de cada día (al principio del día), solo desde `since` y sin los «No sé cuándo».
    public static func minutes(_ plays: [TraktPlay], since: Date, calendar: Calendar) -> [Date: Int] {
        var out: [Date: Int] = [:]
        for p in plays where p.at >= unknownBefore && p.at >= since {
            out[calendar.startOfDay(for: p.at), default: 0] += p.minutes > 0 ? p.minutes : fallbackMinutes
        }
        return out
    }

    /// El nivel de cada día con algo (1, 2 o 3): por tercios de tus días, de menos a más.
    public static func levels(_ minutes: [Date: Int]) -> [Date: Int] {
        let sorted = minutes.values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return [:] }
        let low = sorted[(sorted.count - 1) / 3], high = sorted[2 * (sorted.count - 1) / 3]
        return minutes.compactMapValues { v in
            guard v > 0 else { return nil }
            return v > high ? 3 : v > low ? 2 : 1
        }
    }
}
