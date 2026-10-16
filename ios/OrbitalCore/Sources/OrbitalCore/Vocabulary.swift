import Foundation

/// El vocabulario de la consola, una sola vez para el iPhone: los mismos resultados que `orbital/foryou.py` (`runtime_text`) y
/// `orbital/watch.py` (`time_left`), el saludo de `core/home.js` y la línea de datos de `factLine` / `detail-panel.js`.
/// Solo devuelve textos neutros; poner «Película» o «quedan» en el idioma de la app es cosa de la interfaz.
public enum Vocabulary {
    /// Horas y minutos que quedan al dividir una cantidad de minutos.
    public static func hoursAndMinutes(_ minutes: Int) -> (hours: Int, minutes: Int) { (minutes / 60, minutes % 60) }

    /// «45 min», «1 h 45 min», «2 h» (nil si no hay duración): como `runtime_text` de la consola.
    public static func runtimeText(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        let (h, m) = hoursAndMinutes(minutes)
        return h > 0 && m > 0 ? "\(h) h \(m) min" : h > 0 ? "\(h) h" : "\(m) min"
    }

    /// Minutos enteros que faltan (0 si falta menos de uno).
    public static func minutesLeft(seconds: Double) -> Int { max(0, Int(seconds / 60)) }

    /// «quedan 11 min» / «quedan 1 h 40 min» (vacío si falta menos de un minuto): como `time_left` de la consola.
    public static func timeLeft(seconds: Double) -> String {
        let minutes = minutesLeft(seconds: seconds)
        guard minutes >= 1 else { return "" }
        let (h, m) = hoursAndMinutes(minutes)
        return h > 0 && m > 0 ? "quedan \(h) h \(m) min" : h > 0 ? "quedan \(h) h" : "quedan \(m) min"
    }

    /// Los datos que hay, unidos con « · » (nunca un punto colgando): `factLine` de la TV.
    public static func factLine(_ parts: [String?]) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }

    /// La línea de datos de una sugerencia, del más completo al más corto («Película · 2026 · 1 h 45 min», «Película · 1 h 45 min»,
    /// «Película»): si no cabe, se quita el año y luego la duración, nunca se corta un número a medias. `kind` ya viene en el
    /// idioma de la app; `next` es «T2 · E5» si la serie sigue en un episodio.
    public static func factVariants(kind: String, year: Int?, runtime: Int?, next: String?) -> [String] {
        if let next { return [factLine([kind, next]), kind] }
        let time = runtimeText(minutes: runtime)
        var out: [String] = []
        if let year, let time { out.append(factLine([kind, String(year), time])) }
        if let time { out.append(factLine([kind, time])) }
        else if let year { out.append(factLine([kind, String(year)])) }
        return out + [kind]
    }

    /// Hasta cuatro datos de la ficha, en el orden de `detail-panel.js`: año · género · duración · calificación.
    public static func titleFacts(year: String, genres: [String], runtime: String, rating: String) -> [String] {
        let genre = genres.prefix(2).joined(separator: ", ")
        return [year, genre, runtime, rating.isEmpty ? "" : "★ \(rating)"].filter { !$0.isEmpty }
    }

    /// «Buenos días / Buenas tardes / Buenas noches» (`greeting` de `core/home.js`): de 5 a 12 h, de 12 a 20 h y el resto.
    public enum Greeting: Sendable, Equatable { case morning, afternoon, evening }
    public static func greeting(hour: Int) -> Greeting { hour >= 5 && hour < 12 ? .morning : hour >= 12 && hour < 20 ? .afternoon : .evening }
}

/// Dónde están las imágenes de un título (metahub, igual que la TV).
public enum Artwork {
    /// El logo del título; solo hay con un id de IMDb («tt…»).
    public static func logoURL(metaID: String) -> String? {
        metaID.hasPrefix("tt") ? "https://images.metahub.space/logo/medium/\(metaID)/img" : nil
    }
}
