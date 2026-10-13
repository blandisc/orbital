import SwiftUI
import OrbitalCore
import OrbitalModels

/// «quedan 1 h 40 min» en el idioma de la app.
func timeLeftText(minutes: Int) -> LocalizedStringKey {
    let h = minutes / 60, m = minutes % 60
    if h > 0 && m > 0 { return "quedan \(h) h \(m) min" }
    if h > 0 { return "quedan \(h) h" }
    return "quedan \(m) min"
}

/// «T2 · E5» / «S2 · E5» (o nada si es una película), en el idioma de la app.
@MainActor func episodeText(season: Int?, episode: Int?) -> String {
    guard let episode else { return "" }
    return Strings.episode(season: season, episode: episode, language: AppEnvironment.shared.services.appSettings.uiLanguage)
}

func badgeKey(_ reason: SuggestionReason) -> LocalizedStringKey {
    switch reason {
    case .recommended: "Recomendada"
    case .watching: "Sigues viéndola"
    case .inWatchlist: "En tu lista"
    case .inList(let name): name.isEmpty ? "En tu lista" : "En «\(name)»"
    case .trending: "En tendencia"
    case .popular: "Popular"
    case .onPlatform(let name): "En \(name)"
    }
}

/// Una fila horizontal de portadas con su título.
struct Rail<Content: View>: View {
    let title: LocalizedStringKey
    var trailing: LocalizedStringKey?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title, trailing: trailing).padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) { content() }.padding(.horizontal, DS.Space.gutter)
            }
        }
    }
}

/// Una portada que lleva a la ficha, con su nombre debajo.
struct TitleLink: View {
    let route: TitleRoute
    var badge: LocalizedStringKey?
    var progress: Double?
    var width: CGFloat = DS.Poster.railWidth

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterCard(title: route.title, poster: route.poster, badge: badge, progress: progress, width: width)
                Text(route.title).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1).frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

extension Suggestion {
    var route: TitleRoute { TitleRoute(kind: kind, metaID: imdb, title: title, poster: poster) }
}
