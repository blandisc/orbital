import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los datos de un título en palabras («T2 · E5 · quedan 20 min», «2021 · Película», la insignia del porqué), con el idioma
/// explícito: el mismo vocabulario que la consola (`Vocabulary`), sin leer el estado de la app.
/// «quedan 1 h 40 min» en el idioma de la app (las mismas horas y minutos que `Vocabulary.timeLeft`).
func timeLeftText(minutes: Int) -> LocalizedStringKey {
    let (h, m) = Vocabulary.hoursAndMinutes(minutes)
    if h > 0 && m > 0 { return "quedan \(h) h \(m) min" }
    if h > 0 { return "quedan \(h) h" }
    return "quedan \(m) min"
}


/// «T2 · E5» / «S2 · E5» (o nada si es una película), en el idioma de la app.
func episodeText(season: Int?, episode: Int?, language: String) -> String {
    guard let episode else { return "" }
    return Strings.episode(season: season, episode: episode, language: language)
}


extension Suggestion {
    /// La plataforma, si la sugerencia es «En Netflix», «En Disney+»… (para su píldora en color).
    var platformName: String? { if case .onPlatform(let name) = reason, !name.isEmpty { name } else { nil } }
}

func badgeKey(_ reason: SuggestionReason) -> LocalizedStringKey {
    switch reason {
    case .recommended: "Recomendada"
    case .watching: "Sigues viéndola"
    case .inWatchlist: "En Mi lista"   // tu watchlist de Trakt: en el iPhone se llama «Mi lista» en todos lados (glosario)
    case .inList(let name) where name == ForYou.favoritesName: "En tus favoritos"   // con su traducción (antes «In “Favoritos”»)
    case .inList(let name): name.isEmpty ? "En una de tus listas" : "En «\(name)»"
    case .trending: "En tendencia"
    case .popular: "Popular"
    case .onPlatform(let name): "En \(name)"
    case .console(let text): LocalizedStringKey(text)   // tal cual lo dice tu Orbital
    }
}


/// «2021 · Película» / «2005–2013 · Serie».
func yearAndKind(year: String, kind: String) -> Text {
    let k = kind == "movie" ? Text("Película") : Text("Serie")
    // «2026–» (una serie que sigue al aire) se queda en «2026»: el guion colgante parece un error.
    let shown = year.trimmingCharacters(in: CharacterSet(charactersIn: "–- "))
    return shown.isEmpty ? k : Text("\(shown) · \(k)")
}

/// El dato de una línea de una sugerencia, como `factLine` en la TV: «Serie · T2 · E5», «Película · 2026 · 1 h 45 min».
/// Del más completo al más corto (`ViewThatFits` elige el que cabe); las reglas viven en `Vocabulary.factVariants`.
func factVariants(_ s: Suggestion, language: String) -> [Text] { factStrings(s, language: language).map { Text(verbatim: $0) } }

/// Lo mismo, como texto (para `DataLine`).
func factStrings(_ s: Suggestion, language: String) -> [String] {
    let next = s.next.map { episodeText(season: $0.season, episode: $0.episode, language: language) }
    return Vocabulary.factVariants(kind: Strings.kind(s.kind, language: language), year: s.year, runtime: s.runtime, next: next)
}

/// El dato de «Seguir viendo» con el mismo vocabulario que la consola: «T2 · E5 · quedan 20 min» (película: solo lo que queda).
func progressFact(season: Int?, episode: Int?, leftMinutes: Int, language: String) -> String {
    Vocabulary.factLine([episodeText(season: season, episode: episode, language: language), leftMinutes > 0 ? Strings.timeLeft(minutes: leftMinutes, language: language) : nil])
}

extension Suggestion {
    var route: TitleRoute { TitleRoute(kind: kind, metaID: imdb, title: title, poster: poster) }
}

