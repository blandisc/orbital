import SwiftUI
import OrbitalCore
import OrbitalModels

/// El arte de la ficha y la línea de datos («2021 · Película · 1 h 45 min», calificaciones, plataformas).
extension TitleView {
    /// El arte a sangre, más alto, con el logo (o el nombre) al centro y la frase de la película debajo, como un cartel de cine.
    /// Al deslizar se funde (AR1, Fernando, 13 nov 2026): se va con el contenido, se difumina y se desvanece hacia el fondo que
    /// de verdad tiene detrás, sin enseñar su orilla; el logo se va antes. En claro, la tarjeta sube nítida. Con «Reducir
    /// movimiento» o «Reducir transparencia», solo se desvanece.
    func hero(_ model: TitleModel) -> some View {
        // El arte sube detrás del reloj y de la barra (como el Mosaico): mide lo de siempre más ese alto de arriba y se corre
        // hacia arriba lo mismo, así lo de abajo («Ver», los datos) no se mueve.
        let extra = scheme == .dark ? topInset : 0
        let aspect = contentWidth > 0 && extra > 0 ? contentWidth / (contentWidth / heroAspect + extra) : heroAspect
        return BleedArt(url: model.background ?? model.poster, title: titleName(model.title, id: model.metaID, kind: model.kind),
                 aspect: aspect, collapses: true, zoom: PlayerZoomID(metaID: model.metaID, slot: "title"),   // «Ver» hace crecer el video desde el arte
                 fallback: model.background == nil ? nil : model.poster, tall: TallArtKey(imdb: model.metaID, kind: model.kind), fadesTop: false, raised: extra) {
            VStack(spacing: DS.Space.s2) {
                TitleLogo(url: model.logo, title: titleName(model.title, id: model.metaID, kind: model.kind), size: .hero, centered: true)
                    .containerRelativeFrame(.horizontal) { width, _ in width * DS.TitleAction.logoWidth }   // ds-exception: el logo, parte del ancho del arte de la ficha
                if let tagline = model.extras?.tagline {
                    Text(verbatim: tagline).font(DS.TextRecipe.secondary.font.italic()).foregroundStyle(DS.onArtSecondary)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .tiltable()   // mantener y mover: el arte se inclina con un brillo
        .padding(.top, -extra)
    }

    /// Bajo el arte, al centro, un bloque chico de datos en gris: un renglón con año · Serie/Película · géneros · duración y la
    /// clasificación («TV-MA») como insignia con contorno al final; pegadas debajo, las calificaciones, discretas (logos chicos,
    /// números en gris). El año va sin el guion colgante («2026–» parecía un error). La versión que va a sonar vive en el botón principal.
    /// `leading`: a la izquierda, sobre el arte (la ficha ancha del iPad y la Mac, como la TV).
    func facts(_ model: TitleModel, leading: Bool = false) -> some View {
        let language = env.services.appSettings.uiLanguage
        let minutes = Int(CinemetaParsing.runtimeSeconds(model.info.runtime) / 60)
        let runtime = Vocabulary.runtimeText(minutes: minutes > 0 ? minutes : nil) ?? model.info.runtime
        let year = model.info.year.trimmingCharacters(in: CharacterSet(charactersIn: "–- "))
        let facts = Vocabulary.titleFacts(year: Vocabulary.factLine([year, Strings.kind(model.kind, language: language)]),
                                          genres: Vocabulary.genres(model.info.genres, language: language), runtime: runtime, rating: "")
        // Se parte solo entre datos, nunca dentro de uno («2 h 35 min» entero, en el SE): cada dato con espacios que no se
        // separan. Si no cabe en un renglón, la clasificación baja a su propio renglón en vez de flotar junto a dos.
        let line = Vocabulary.factLine(facts.map { $0.replacingOccurrences(of: " ", with: "\u{00A0}") })
        let certification = model.extras?.certification
        return VStack(alignment: leading ? .leading : .center, spacing: DS.Space.s2) {
            // Su propio tipo (no anidado en el de la ficha): ver `TitleFactsLine`.
            TitleFactsLine(line: line, certification: certification, leading: leading, lineLimit: typeSize.isAccessibilitySize ? 4 : 2)
            RatingsRow(imdb: model.info.rating, tmdb: model.extras?.rating, trakt: model.traktRating, letterboxd: letterboxdInfo?.average, centered: !leading)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }

}

/// La línea de datos de la ficha («2005–2013 · Serie · Comedia · 22 min» y la clasificación): en un renglón si cabe; si no, la
/// clasificación baja a su renglón. Es un tipo propio a propósito (11 nov 2026): metida en `TitleView.oneColumnLayout`, la
/// `ViewThatFits` con dos pilas genéricas dejaba un tipo de vista anidado enorme, y una compilación Debug de la app cerró
/// (EXC_BAD_ACCESS al copiar ese tipo, en `swift_retain`). Con un tipo con nombre la ficha no carga ese anidado.
struct TitleFactsLine: View {
    let line: String
    let certification: String?
    let leading: Bool
    let lineLimit: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s2) {
                text.fixedSize()
                badge
            }
            VStack(alignment: leading ? .leading : .center, spacing: DS.Space.s1) {
                text
                badge
            }
        }
    }

    private var text: some View {
        Text(verbatim: line).recipe(.footnote).multilineTextAlignment(leading ? .leading : .center).lineLimit(lineLimit)
    }

    @ViewBuilder private var badge: some View {
        if let certification {
            QualityBadges(items: [certification]).fixedSize().accessibilityLabel(Text("Clasificación \(certification)"))
        }
    }
}
