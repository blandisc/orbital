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

/// IMDb · TMDB · Trakt, cada una con el logotipo oficial de su servicio y su calificación real: IMDb de Cinemeta
/// (`imdbRating`), TMDB de su `vote_average` ×10 y Trakt de su `rating` ×10. La que falta o vale 0 no se enseña. Los tres
/// logos miden lo mismo de alto y van al mismo espacio; los números, de ancho fijo. El renglón guarda su alto (no brinca).
struct RatingsRow: View {
    let imdb: String?
    let tmdb: Double?
    let trakt: Double?
    /// Al centro (la ficha).
    var centered = false

    var body: some View {
        // En un renglón; si no cabe (letra de accesibilidad en un SE), uno debajo de otro en vez de cortar los números.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s4) {
                if centered { Spacer(minLength: 0) }
                marks
                Spacer(minLength: 0)
            }
            VStack(alignment: centered ? .center : .leading, spacing: DS.Space.s2) { marks }
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        }
        .frame(minHeight: DS.Size.touchTarget / 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var marks: some View {
        if let imdb, (Double(imdb) ?? 0) > 0 { rating(.imdb, Text(verbatim: imdb)) }
        if let tmdb, tmdb > 0 { rating(.tmdb, Text(verbatim: "\(Int((tmdb * 10).rounded()))\u{00A0}%")) }
        if let trakt, trakt > 0 { rating(.trakt, Text(verbatim: "\(Int((trakt * 10).rounded()))\u{00A0}%")) }
    }

    private func rating(_ service: RatingMark.Service, _ value: Text) -> some View {
        HStack(spacing: DS.Space.s2) {
            RatingMark(service: service)
            // Entero y en un renglón (con letra grande «86 %» se partía y el % caía abajo).
            value.font(DS.TextRecipe.secondary.font.weight(.semibold)).monospacedDigit().foregroundStyle(DS.text)
                .lineLimit(1).fixedSize()
        }
    }
}

/// El logotipo oficial de un servicio de calificaciones (vector en `Assets.xcassets/Ratings`, en sus colores de marca),
/// a la altura común de los tres; crece con la letra.
struct RatingMark: View {
    enum Service: String { case imdb, tmdb, trakt }
    let service: Service
    @ScaledMetric(relativeTo: .subheadline) private var height = DS.RatingBrand.markHeight

    var body: some View {
        Image("rating-" + service.rawValue).resizable().scaledToFit()
            .frame(height: height)
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
    /// El ancho del póster: el de la tira, o el de su columna en una cuadrícula (`DSPosterGrid`).
    var width: CGFloat = DS.Poster.railWidth
    @Environment(\.posterCaptions) private var captions
    var body: some View {
        NavigationLink(value: TmdbRoute(title: title)) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterCard(title: title.title, poster: title.poster, width: width)
                if captions {   // en la filmografía (cuadrícula) dice su papel; en una tira, solo el póster
                    Text(verbatim: title.title).recipe(.footnote).lineLimit(1).frame(width: width, alignment: .leading)
                    Text(verbatim: title.role ?? title.year.map(String.init) ?? "").recipe(.footnote).lineLimit(1).frame(width: width, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
