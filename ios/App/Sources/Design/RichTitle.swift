import SwiftUI
import OrbitalCore

// La ficha rica (como Infuse): insignias de calidad, calificaciones de varias fuentes, caras del reparto, tráiler y extras,
// logos de dónde verlo y los títulos de TMDB (recomendaciones, saga, filmografía) que se abren resolviendo su IMDb.

/// Insignias de calidad con contorno (4K · DV · HDR10+ · ATMOS · TRUEHD), como las de un disco.
struct QualityBadges: View {
    let items: [String]
    var body: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach(items, id: \.self) { item in
                Text(verbatim: item.uppercased()).font(DS.TextRecipe.caption.font.weight(.bold)).monospaced()
                    .foregroundStyle(DS.text).lineLimit(1)
                    .padding(.horizontal, DS.Space.s1)
                    .overlay(RoundedRectangle(cornerRadius: DS.Rich.badgeRadius).stroke(DS.textMuted, lineWidth: DS.Rich.badgeStroke))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Lo que se enseña de una fuente: resolución, rango dinámico y sonido.
    static func items(resolution: String, hdr: [String], audio: [String]) -> [String] {
        ([resolution].filter { !$0.isEmpty } + hdr + audio)
    }
}

/// IMDb · TMDB · Trakt, cada una con el logotipo de su servicio y su calificación. El renglón guarda su alto aunque aún no
/// llegue nada (no brinca).
struct RatingsRow: View {
    let imdb: String?
    let tmdb: Double?
    let trakt: Double?

    var body: some View {
        HStack(spacing: DS.Space.s4) {
            if let imdb, !imdb.isEmpty { rating(RatingMark(service: .imdb), Text(verbatim: imdb)) }
            if let tmdb { rating(RatingMark(service: .tmdb), Text(verbatim: "\(Int((tmdb * 10).rounded())) %")) }
            if let trakt { rating(RatingMark(service: .trakt), Text(verbatim: "\(Int((trakt * 10).rounded())) %")) }
            Spacer(minLength: 0)
        }
        .frame(minHeight: DS.Size.touchTarget / 2)
        .accessibilityElement(children: .combine)
    }

    private func rating(_ mark: RatingMark, _ value: Text) -> some View {
        HStack(spacing: DS.Space.s2) {
            mark
            value.font(DS.TextRecipe.secondary.font.weight(.semibold)).monospacedDigit().foregroundStyle(DS.text)
        }
    }
}

/// El logotipo de un servicio de calificaciones, dibujado en sus colores de marca (como los muestra Infuse).
struct RatingMark: View {
    enum Service { case imdb, tmdb, trakt }
    let service: Service

    var body: some View {
        Group {
            switch service {
            case .imdb:
                Text(verbatim: "IMDb").font(DS.TextRecipe.caption.font.weight(.black)).foregroundStyle(DS.RatingBrand.imdbInk)
                    .padding(.horizontal, DS.Space.s1)
                    .frame(height: DS.RatingBrand.markHeight)
                    .background(DS.RatingBrand.imdb, in: RoundedRectangle(cornerRadius: DS.RatingBrand.markRadius))
            case .tmdb:
                Text(verbatim: "TMDB").font(DS.TextRecipe.caption.font.weight(.heavy)).foregroundStyle(DS.RatingBrand.tmdbInk)
                    .padding(.horizontal, DS.Space.s1)
                    .frame(height: DS.RatingBrand.markHeight)
                    .background(LinearGradient(colors: [DS.RatingBrand.tmdbStart, DS.RatingBrand.tmdbEnd], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: DS.RatingBrand.markRadius))
            case .trakt:
                Image(systemName: "checkmark").font(DS.TextRecipe.caption.font.weight(.heavy)).foregroundStyle(DS.paper)
                    .frame(width: DS.RatingBrand.markHeight, height: DS.RatingBrand.markHeight)
                    .background(DS.RatingBrand.trakt, in: Circle())
            }
        }
        .accessibilityLabel(Text(verbatim: service == .imdb ? "IMDb" : service == .tmdb ? "TMDB" : "Trakt"))
    }
}

/// La cara de una persona en un círculo (o sus iniciales si TMDB no tiene foto).
struct PersonPhoto: View {
    let name: String
    let photo: String?
    var size: CGFloat = DS.Rich.face

    var body: some View {
        Group {
            if let photo, let url = URL(string: photo) {
                RemoteImage(url: url, maxPoints: size) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { initials }
                }
            } else { initials }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Text(verbatim: name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .recipe(.cardTitle, color: DS.textMuted).frame(maxWidth: .infinity, maxHeight: .infinity).background(DS.fill)
    }
}

/// Una persona del reparto: su cara, su nombre y su personaje (o su trabajo).
struct PersonFace: View {
    let name: String
    let role: String
    let photo: String?

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            PersonPhoto(name: name, photo: photo)
            Text(verbatim: name).recipe(.caption, color: DS.text).lineLimit(2).multilineTextAlignment(.center)
            if !role.isEmpty { Text(verbatim: role).recipe(.caption, color: DS.textMuted).lineLimit(1) }
        }
        .frame(width: DS.Rich.faceColumn, alignment: .top)
        .accessibilityElement(children: .combine)
    }
}

/// Un video de YouTube (tráiler, avance, detrás de cámaras): su imagen con ▶ y su nombre. Se abre en YouTube.
struct VideoClipCard: View {
    let clip: VideoClip
    var width: CGFloat = DS.Rich.clipWidth
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { if let url = clip.url { openURL(url) } } label: {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterView(url: clip.thumbnail, title: clip.name, aspect: DS.Poster.stillAspect)
                    .overlay {
                        Image(systemName: "play.fill").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.paper)
                            .frame(width: DS.Rich.trailerPlay, height: DS.Rich.trailerPlay).glassEffect(.regular, in: Circle())
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                Text(verbatim: clip.name).recipe(.footnote, color: DS.text).lineLimit(1)
            }
            .frame(width: width)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: clip.name))
    }
}

/// Logos con su nombre (dónde verlo, la cadena o el estudio).
struct BrandLogos: View {
    let brands: [Brand]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s3) {
                ForEach(brands) { brand in
                    HStack(spacing: DS.Space.s2) {
                        if let logo = brand.logo, let url = URL(string: logo) {
                            RemoteImage(url: url, maxPoints: DS.Rich.logo) { phase in
                                if case .success(let image) = phase { image.resizable().scaledToFit() } else { Color.clear }
                            }
                            .frame(width: DS.Rich.logo, height: DS.Rich.logo)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Rich.logoRadius))
                        }
                        Text(verbatim: brand.name).recipe(.footnote, color: DS.text).lineLimit(1)
                    }
                    .padding(.trailing, DS.Space.s2)
                }
            }
        }
    }
}

/// A dónde lleva un título de TMDB (se resuelve su IMDb al abrirlo) y una persona.
struct TmdbRoute: Hashable { var title: TmdbTitle }
struct PersonRoute: Hashable { var id: Int; var name: String }

/// Un póster de TMDB que abre su ficha.
struct TmdbPoster: View {
    let title: TmdbTitle
    @Environment(\.posterCaptions) private var captions
    var body: some View {
        NavigationLink(value: TmdbRoute(title: title)) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterCard(title: title.title, poster: title.poster, width: DS.Poster.railWidth)
                if captions {   // en la filmografía (cuadrícula) dice su papel; en una tira, solo el póster
                    Text(verbatim: title.title).recipe(.footnote).lineLimit(1).frame(width: DS.Poster.railWidth, alignment: .leading)
                    Text(verbatim: title.role ?? title.year.map(String.init) ?? "").recipe(.footnote).lineLimit(1).frame(width: DS.Poster.railWidth, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
