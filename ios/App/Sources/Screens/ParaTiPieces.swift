import SwiftUI
import OrbitalCore
import OrbitalModels

/// Piezas de Para ti que conocen el entorno de la app: las acciones de una sugerencia, el póster de estante y el filtro por tipo.

/// Las acciones de una sugerencia (mantener el dedo sobre un póster, o «Más» en el destacado): ver, Mi lista, descargar, la TV y «No me interesa».
struct SuggestionActions: View {
    @Environment(AppEnvironment.self) private var env
    let suggestion: Suggestion
    var includeWatch = true
    /// Dentro de una de tus listas (Inicio y su «Ver todo»): en vez de «Guardar» y «No me interesa», «Quitar de …» (eso hace
    /// `onDismiss`); y en una película, «Marcar como vista».
    var list: SaveDestination? = nil
    /// Una película marcada como vista: Trakt la saca sola de tu watchlist (la pantalla la quita ya).
    var onWatched: ((Suggestion) -> Void)? = nil
    /// En tus favoritos (Para ti › Tuyo › Favoritos): «Quitar de favoritos» (eso hace `onDismiss`) en vez de «No me interesa».
    var favorite = false
    let onDismiss: (Suggestion) -> Void

    var body: some View {
        if includeWatch { Button("Ver", systemImage: "play.fill") { Task { await env.play(suggestion) } } }
        if list == nil { Button("Guardar", systemImage: "plus") { Task { await env.save(suggestion) } } }   // a la lista por omisión (`SaveDestination`)
        Button("Descargar", systemImage: "arrow.down.circle") { Task { await env.download(suggestion) } }
        if env.services.orbital.isConfigured {
            Button("Ver en la TV", systemImage: "tv") { Task { await env.playOnTV(kind: suggestion.kind, metaID: suggestion.imdb, videoID: env.videoID(for: suggestion), title: suggestion.title) } }
        }
        if list != nil, suggestion.kind == "movie" {
            Button("Marcar como vista", systemImage: "checkmark.circle") {
                Task { if await env.markWatched(suggestion), list != nil { onWatched?(suggestion) } }
            }
        }
        if let list {
            Button("Quitar de Mi lista", systemImage: "minus.circle", role: .destructive) { onDismiss(suggestion) }
        } else if favorite {
            Button("Quitar de favoritos", systemImage: "heart.slash", role: .destructive) { onDismiss(suggestion) }
        } else {
            Button("No me interesa", systemImage: "hand.thumbsdown", role: .destructive) { onDismiss(suggestion) }
        }
    }
}

/// Un póster de un estante: toca para abrir la ficha (con una háptica suave), mantén para el menú.
struct ShelfPoster: View {
    let suggestion: Suggestion
    let style: ShelfPlan.Style
    let inList: Bool
    /// El porqué en el póster («Sale el viernes», «N.º 3 en Netflix»), si lo hay.
    var badge: PosterBadge? = nil
    /// El ancho del póster (más chico dentro de «Porque viste»).
    var width: CGFloat = DS.Poster.railWidth
    /// En tu lista de Favoritos: su menú ofrece «Quitar de favoritos» (no «No me interesa»).
    var favorite = false
    let onDismiss: (Suggestion) -> Void
    @State private var taps = 0

    var body: some View {
        Group {
            if style == .top10, let rank = suggestion.rank {
                TitleNavigationLink(route: suggestion.route) { RankedPosterCard(rank: rank, title: suggestion.title, poster: suggestion.poster, movement: suggestion.movement, isNew: suggestion.isNew).titleZoomSource(suggestion.route) }.buttonStyle(.plain)
            } else {
                TitleLink(route: suggestion.route, badge: badge.flatMap(badgeText), platformRank: platformRank, bookmarked: inList, rank: style == .platform ? suggestion.rank : nil, width: width,
                          detail: yearAndKind(year: suggestion.year.map(String.init) ?? "", kind: suggestion.kind))
            }
        }
        .simultaneousGesture(TapGesture().onEnded { taps += 1 })
        .sensoryFeedback(.impact(flexibility: .soft), trigger: taps)
        .contextMenu { SuggestionActions(suggestion: suggestion, favorite: favorite, onDismiss: onDismiss) }
    }

    /// «N.º 3 en Netflix» no va en texto: es la píldora de la plataforma, con su logo.
    private var platformRank: (rank: Int, platform: String)? {
        if case .rank(let n, let platform) = badge { return (n, platform) }
        return nil
    }
}

/// «Sale hoy», «Sale mañana» o «Sale el viernes». El puesto en una plataforma va en su píldora (`PlatformBadge`).
@MainActor func badgeText(_ badge: PosterBadge) -> LocalizedStringKey? {
    switch badge {
    case .rank: return nil
    case .airs(let day):
        if Calendar.current.isDateInToday(day) { return "Sale hoy" }
        if Calendar.current.isDateInTomorrow(day) { return "Sale mañana" }
        let weekday = day.formatted(.dateTime.weekday(.wide).locale(AppEnvironment.shared.uiLocale))
        return "Sale el \(weekday)"
    }
}

/// Los nombres de los estantes: los de la consola vienen ya con su texto; los de este iPhone se nombran por su id.
@MainActor func shelfTitle(_ plan: ShelfPlan) -> Text {
    // En español se usa el texto de la TV tal cual; en inglés, las listas conocidas con su nombre traducido (la TV manda español).
    let english = AppEnvironment.shared.services.appSettings.uiLanguage == "en"
    // Mi lista y Favoritos se llaman igual en toda la app, aunque la TV las mande con otro nombre («Tu watchlist»).
    if english || ["watchlist", ForYou.favoritesList].contains(plan.id), let known = knownShelfTitle(plan) { return known }
    if !plan.title.isEmpty { return Text(verbatim: plan.title) }
    if let known = knownShelfTitle(plan) { return known }
    return Text(verbatim: plan.list.brand.flatMap { brand in Tmdb.platforms.first { $0.brand == brand }?.name } ?? plan.id)
}

/// El nombre de una lista que el iPhone conoce (para nombrarla en su idioma); nil si es un catálogo de complemento.
@MainActor private func knownShelfTitle(_ plan: ShelfPlan) -> Text? {
    let brand = plan.list.brand.flatMap { brand in Tmdb.platforms.first { $0.brand == brand }?.name } ?? plan.list.brand
    // Sin marca no se puede nombrar («Top 10 en »): se deja el título de la TV.
    if plan.id.hasPrefix("chart:") { return brand.map { Text("Top 10 en \($0)") } }
    if plan.id.hasPrefix("jw:") { return brand.map { Text("Tendencias en \($0)") } }
    switch plan.id {
    case "mine": return Text("Tus series")
    case "watchlist": return Text("Mi lista")   // el mismo nombre que su renglón en «Tuyo» y que Inicio
    case ForYou.favoritesList: return Text("Favoritos")
    case "recs": return Text("Recomendadas")
    case "trend": return Text("En tendencia")
    case "popular": return Text("Lo más popular")
    case "critics": return Text("Aprobadas por la crítica")
    default: return nil
    }
}

@MainActor func shelfMeta(_ plan: ShelfPlan) -> Text? {
    let english = AppEnvironment.shared.services.appSettings.uiLanguage == "en"
    if !plan.list.meta.isEmpty, !english { return Text(verbatim: plan.list.meta) }
    if plan.id.hasPrefix("chart:") { return Text("Esta semana en México") }
    if plan.id.hasPrefix("jw:") { return Text("Tendencia en JustWatch · México") }
    switch plan.id {
    case "mine": return Text("Las que estás viendo")
    case "watchlist": return Text("Lo que dejaste pendiente")
    case "recs": return Text("Por lo que has visto")
    case "trend": return Text("Lo más visto esta semana")
    case "popular": return Text("De todos los tiempos")
    case "critics": return Text("Certified Fresh recientes · Series Fresh")
    default: return plan.style == .platform ? Text("Lo más popular") : plan.id.hasPrefix("addon:") ? Text("De tus complementos") : Text("Una lista para ti")
    }
}

/// Cómo guarda «Para ti › Listas» su filtro (el control es `DSKindFilter`, el de toda la app).
enum KindFilter: String { case all, series, movie }

/// Un póster de un estante de Para ti con su menú, el mismo en la fila y en su «Ver todo»: en tus Favoritos, «Quitar de
/// favoritos» (en Trakt, con «Deshacer»); en los demás, «No me interesa». Una sola pieza para que las dos no se separen.
struct PlanPoster: View {
    @Environment(AppEnvironment.self) private var env
    let suggestion: Suggestion
    let plan: ShelfPlan
    let model: ParaTiModel
    var style: ShelfPlan.Style
    var badge: PosterBadge? = nil
    var width: CGFloat = DS.Poster.railWidth

    var body: some View {
        let favorites = plan.id == ForYou.favoritesList
        // En Mi lista todo está ahí: el marcador sobra.
        ShelfPoster(suggestion: suggestion, style: style, inList: plan.id != "watchlist" && model.watchlistKeys.contains(suggestion.imdb),
                    badge: badge, width: width, favorite: favorites) { dismissed in
            Task { if favorites { await env.removeFavorite(dismissed) } else { await model.dismiss(dismissed) } }
        }
    }
}

