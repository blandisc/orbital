import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una tarjeta de la portada de Inicio: el arte, su porqué en turquesa, su logo, sus datos y «Ver». Aparte de `HomeView` para
/// que Inicio no pase su tope de líneas (18 nov 2026, con el tablero). En el tablero (MI2) es una tarjeta con esquinas
/// (`tile`); si no, de orilla a orilla en oscuro.
struct HomeHeroSlide: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    let s: Suggestion
    let aspect: CGFloat
    /// Lo que se encima «Seguir viendo» en su borde (0 en claro y en el tablero).
    let overlap: CGFloat
    var tile = false
    let open: (TitleRoute) -> Void

    var body: some View {
        // La portada abre la ficha con su propio toque; «Ver» va aparte (un botón dentro de un NavigationLink puede abrir la
        // ficha en vez de reproducir).
        BleedArt(url: s.wide, title: titleName(s.title, id: s.imdb, kind: s.kind), aspect: aspect, fallback: s.poster, tall: TallArtKey(imdb: s.imdb, kind: s.kind), tile: tile) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    if let reason = Self.reasonText(s.reason) { Eyebrow(text: reason, onArt: true, reason: true) }
                    TitleLogo(url: titleName.logo(s.logo ?? Artwork.logoURL(metaID: s.imdb), for: s.title, id: s.imdb, kind: s.kind), title: titleName(s.title, id: s.imdb, kind: s.kind), size: .hero)
                    DataLine(parts: Self.data(s, language: env.services.appSettings.uiLanguage), color: DS.onArtSecondary, trakt: TraktRatings.shown(s.imdb, fallback: s.traktRating))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text("Ver ficha")) { open(s.route) }
                HeroActions { buttons }
            }
            // La portada es arte de alto fijo: con letra de accesibilidad su texto se salía por arriba de la tarjeta (bordes,
            // SE con letra grande). Crece hasta xxxLarge, como las piezas del mosaico; el visor de contenido grande lo amplía.
            .dsChromeType()
            .accessibilityShowsLargeContentViewer()
            // Los puntos (en ventana ancha van debajo) y, en oscuro, lo que se encima. En el tablero (Mac, iPad) «Ver» va más
            // cerca de la orilla de abajo: se veía flotando a media tarjeta (Fernando, 24 nov 2026).
            .padding(.bottom, overlap + (tile ? DS.Space.s2 : WindowMetrics.roomy ? DS.Space.s4 : DS.Space.s6))
        }
        .environment(\.artCentered, Double(aspect) >= ArtFit.tallBelow)   // marco ancho (el Duo): el carrusel, al centro
        .contentShape(Rectangle())
        .onTapGesture { open(s.route) }
    }

    @ViewBuilder private var buttons: some View {
        WithArtColors(url: s.wide) { colors in
            Button {
                if s.kind == "series" { open(s.route) } else { Task { await env.play(s) } }
            } label: {
                Label { s.kind == "series" ? Text("Ver la serie") : Text("Ver") } icon: { Image(systemName: "play.fill") }.lineLimit(1)
            }
            .dsArtButton(colors)
        }
        if env.services.orbital.isConfigured {
            // Un toque lo explica («¿Ver en la TV?»), el segundo lo manda: solo el ícono no decía qué hacía.
            ConfirmIconButton(symbol: "tv.and.mediabox", prompt: "¿Ver en la TV?", label: "Ver en la TV") {
                Task { await env.playOnTV(kind: s.kind, metaID: s.imdb, videoID: s.kind == "movie" ? s.imdb : nil, title: s.title) }
            }
        }
    }

    /// Por qué está en la portada, en turquesa arriba del título («En tendencia esta semana», «Para ti»…).
    static func reasonText(_ reason: SuggestionReason) -> Text? {
        switch reason {
        case .trending: Text("En tendencia esta semana")
        case .popular: Text("Lo más popular")
        case .recommended: Text("Para ti")
        default: Text("Destacado")
        }
    }

    /// «Película · 2024 · Drama».
    static func data(_ s: Suggestion, language: String) -> [String] {
        [Strings.kind(s.kind, language: language), s.year.map(String.init), Vocabulary.genres(s.genres, language: language).first].compactMap { $0 }
    }
}
