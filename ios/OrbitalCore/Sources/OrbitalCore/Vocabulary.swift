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

    /// A qué hora acabarías si empiezas ahora (redondeado al minuto siguiente: nunca promete terminar antes).
    public static func endTime(minutesLeft: Int, now: Date) -> Date {
        let end = now.addingTimeInterval(Double(max(0, minutesLeft)) * 60)
        let seconds = end.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.up) * 60)
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

    /// Géneros de Cinemeta (en inglés) en español, con la misma tabla que `genres` de `core/format.js` en la TV; los
    /// desconocidos se dejan igual. Con la clave de TMDB los géneros ya llegan traducidos y pasan sin cambio.
    public static func genres(_ list: [String], language: String) -> [String] {
        guard language.hasPrefix("es") else { return list }
        return list.map { spanishGenres[$0] ?? $0 }
    }

    private static let spanishGenres: [String: String] = [
        "Action": "Acción", "Adventure": "Aventura", "Animation": "Animación", "Biography": "Biografía", "Comedy": "Comedia",
        "Crime": "Crimen", "Documentary": "Documental", "Drama": "Drama", "Family": "Familiar", "Fantasy": "Fantasía",
        "History": "Historia", "Horror": "Terror", "Music": "Música", "Musical": "Musical", "Mystery": "Misterio", "Romance": "Romance",
        "Sci-Fi": "Ciencia ficción", "Science Fiction": "Ciencia ficción", "Sport": "Deportes", "Thriller": "Suspenso",
        "War": "Bélica", "Western": "Western", "Reality-TV": "Reality", "Talk-Show": "Talk show", "Game-Show": "Concurso",
        "News": "Noticias", "Short": "Corto",
    ]

    /// «Buenos días / Buenas tardes / Buenas noches» (`greeting` de `core/home.js`): de 5 a 12 h, de 12 a 20 h y el resto.
    public enum Greeting: Sendable, Equatable { case morning, afternoon, evening }
    public static func greeting(hour: Int) -> Greeting { hour >= 5 && hour < 12 ? .morning : hour >= 12 && hour < 20 ? .afternoon : .evening }
}

/// Dónde están las imágenes de un título (metahub, igual que la TV).
public enum Artwork {
    /// La variante más ligera que aún se ve nítida a `pixels` (lado más largo): un fondo de metahub «medium» pesa
    /// ~770 KB (1920×1080) y el «small» ~19 KB (480×270); en TMDB, w780 pesa ~140 KB contra ~225 KB de w1280.
    /// Las piezas del mosaico, los estrenos y el tono del fondo se ven a menos de 600 px: con esto un Para ti pasa
    /// de ~16 MB a menos de 1 MB.
    public static func variant(_ url: String, pixels: Int) -> String {
        if pixels <= smallBackgroundPixels, url.contains("images.metahub.space/background/medium/") {
            return url.replacingOccurrences(of: "/background/medium/", with: "/background/small/")
        }
        if pixels <= 780, url.contains("image.tmdb.org/t/p/w1280/") {
            return url.replacingOccurrences(of: "/t/p/w1280/", with: "/t/p/w780/")
        }
        return url
    }

    /// Hasta aquí alcanza el fondo «small» de metahub (480 px de ancho) sin verse borroso en una pieza.
    public static let smallBackgroundPixels = 600

    /// El logo del título; solo hay con un id de IMDb («tt…»).
    public static func logoURL(metaID: String) -> String? {
        metaID.hasPrefix("tt") ? "https://images.metahub.space/logo/medium/\(metaID)/img" : nil
    }
}
