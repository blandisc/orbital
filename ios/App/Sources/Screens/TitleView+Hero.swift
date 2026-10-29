import SwiftUI
import OrbitalCore
import OrbitalModels

/// El arte de la ficha y la línea de datos («2021 · Película · 1 h 45 min», calificaciones, plataformas).
extension TitleView {
    /// El arte a sangre, más alto, con el logo (o el nombre) al centro y la frase de la película debajo, como un cartel de cine.
    /// Al deslizar se recoge como en Apple TV: se queda un poco atrás, se oscurece hacia el color del fondo con un degradado que
    /// sube desde abajo, se difumina al final; el logo se va antes. Con «Reducir movimiento», solo se oscurece y se desvanece.
    func hero(_ model: TitleModel) -> some View {
        BleedArt(url: model.background ?? model.poster, title: model.title,
                 aspect: heroAspect, collapse: Backdrop.tone(tint.colors, scheme: scheme) ?? DS.bg,
                 fallback: model.background == nil ? nil : model.poster, tall: TallArtKey(imdb: model.metaID, kind: model.kind)) {
            VStack(spacing: DS.Space.s2) {
                TitleLogo(url: model.info.logo ?? Artwork.logoURL(metaID: model.metaID), title: model.title, size: .hero, centered: true)
                    .containerRelativeFrame(.horizontal) { width, _ in width * DS.TitleAction.logoWidth }
                if let tagline = model.extras?.tagline {
                    Text(verbatim: tagline).font(DS.TextRecipe.secondary.font.italic()).foregroundStyle(DS.onArtSecondary)
                        .multilineTextAlignment(.center).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
    }

    /// Bajo el arte, al centro, un bloque chico de datos en gris: un renglón con año · Serie/Película · géneros · duración y la
    /// clasificación («TV-MA») como insignia con contorno al final; pegadas debajo, las calificaciones, discretas (logos chicos,
    /// números en gris). El año va sin el guion colgante («2026–» parecía un error). La calidad de la que va a sonar vive bajo «Ver».
    func facts(_ model: TitleModel) -> some View {
        let language = env.services.appSettings.uiLanguage
        let minutes = Int(CinemetaParsing.runtimeSeconds(model.info.runtime) / 60)
        let runtime = Vocabulary.runtimeText(minutes: minutes > 0 ? minutes : nil) ?? model.info.runtime
        let year = model.info.year.trimmingCharacters(in: CharacterSet(charactersIn: "–- "))
        let facts = Vocabulary.titleFacts(year: Vocabulary.factLine([year, Strings.kind(model.kind, language: language)]),
                                          genres: Vocabulary.genres(model.info.genres, language: language), runtime: runtime, rating: "")
        return VStack(spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                Text(verbatim: Vocabulary.factLine(facts)).recipe(.footnote).multilineTextAlignment(.center).lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                if let certification = model.extras?.certification {
                    QualityBadges(items: [certification]).fixedSize().accessibilityLabel(Text("Clasificación \(certification)"))
                }
            }
            RatingsRow(imdb: model.info.rating, tmdb: model.extras?.rating, trakt: model.traktRating, centered: true)
        }
        .frame(maxWidth: .infinity)
    }
}
