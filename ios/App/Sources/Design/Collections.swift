import SwiftUI
import OrbitalCore

/// Una colección (Para ti › Listas): la tarjeta en abanico con su emblema al frente y, debajo, su nombre y su dato
/// («Óscar · Mejor película», «Para ver en pareja · 24 títulos»).
struct CollectionCard<Emblem: View>: View {
    let title: Text
    let detail: Text
    let name: String
    let posters: [String?]
    let tint: Color
    @ViewBuilder var emblem: () -> Emblem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            FanCard(name: name, posters: posters, tint: tint, emblem: emblem)
            VStack(alignment: .leading, spacing: 0) {
                title.recipe(.cardTitle).lineLimit(1)
                detail.recipe(.caption).lineLimit(1)
            }
            .padding(.horizontal, DS.Space.s1)
        }
        .frame(width: DS.PlatformFan.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// La estatuilla de un premio, recortada, con el halo de su color (el emblema de su colección).
struct AwardEmblem: View {
    let id: String
    var body: some View {
        Image("Awards/" + id).resizable().scaledToFit()
            .frame(height: DS.Collections.emblem)
            .shadow(color: DS.Collections.tint(id), radius: DS.Collections.glow)
            .accessibilityHidden(true)
    }
}

/// El sello de Trakt (el emblema de tus listas).
struct TraktEmblem: View {
    var body: some View {
        Image(systemName: "checkmark").font(DS.TextRecipe.section.font.weight(.heavy)).foregroundStyle(DS.paper)
            .frame(width: DS.PlatformFan.logo, height: DS.PlatformFan.logo)
            .background(DS.RatingBrand.trakt, in: Circle())
            .shadow(color: DS.RatingBrand.trakt, radius: DS.PlatformFan.glow)
            .accessibilityHidden(true)
    }
}

/// Un premio en Colecciones: su estatuilla al frente, sobre sus tres ganadores más recientes, y su nombre debajo.
struct AwardCard: View {
    let award: AwardCollection

    var body: some View {
        CollectionCard(title: AwardNames.title(award.id), detail: AwardNames.category(award.id), name: award.id,
                       posters: award.suggestions.prefix(3).map { Optional($0.poster) }, tint: DS.Collections.tint(award.id)) {
            AwardEmblem(id: award.id)
        }
    }
}

/// Cómo se llama cada premio y qué categoría es la colección.
enum AwardNames {
    static func title(_ id: String) -> Text {
        switch id {
        case "oscar": Text("Óscar"); case "emmy": Text("Emmy"); case "globe": Text("Globos de Oro"); case "palm": Text("Cannes")
        case "bafta": Text(verbatim: "BAFTA"); case "ariel": Text("Ariel"); default: Text(verbatim: id)
        }
    }

    static func category(_ id: String) -> Text {
        switch id {
        case "emmy": Text("Mejor serie de drama"); case "globe": Text("Mejor película dramática"); case "palm": Text("Palma de Oro")
        case "ariel": Text("Cine mexicano"); default: Text("Mejor película")
        }
    }
}

/// De dónde viene una lista: su sello junto al título (Trakt, Stremio o tu Orbital).
enum ListSource: Hashable {
    case trakt, stremio, orbital
    var name: String { switch self { case .trakt: "Trakt"; case .stremio: "Stremio"; case .orbital: "Orbital" } }
    var color: Color { switch self { case .trakt: DS.RatingBrand.trakt; case .stremio: DS.Collections.stremio; case .orbital: DS.Collections.orbital } }
}

/// El sello de origen: el nombre del servicio en mayúsculas sobre su color.
struct SourceBadge: View {
    let source: ListSource
    var body: some View {
        Text(verbatim: source.name.uppercased())
            .font(DS.TextRecipe.caption.font.weight(.heavy)).tracking(DS.Collections.badgeRadius / 10)
            .foregroundStyle(DS.paper)
            .padding(.horizontal, DS.Space.s1 + DS.Size.hairline).padding(.vertical, DS.Size.hairline)
            .background(source.color, in: RoundedRectangle(cornerRadius: DS.Collections.badgeRadius, style: .continuous))
            .accessibilityLabel(Text("De \(source.name)"))
    }
}

/// Una lista en «Listas de Trakt» o «Listas de Stremio»: dos pósters en pila, su nombre, su sello y cuántos tiene.
struct ListCard: View {
    let name: String
    let source: ListSource
    let posters: [String]
    var count: Int?

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            ZStack(alignment: .topLeading) {
                ForEach(Array(posters.prefix(2).enumerated().reversed()), id: \.offset) { i, url in
                    PosterView(url: url, title: name).frame(width: DS.Collections.stackPoster)
                        .rotationEffect(.degrees(i == 1 ? -DS.Collections.stackAngle : 0))
                        .offset(x: i == 1 ? 0 : DS.Space.s3, y: i == 1 ? DS.Space.s1 : 0)
                        .shadow(color: DS.scrim, radius: DS.Space.s1, y: DS.Space.s1)
                }
            }
            .frame(width: DS.Collections.stackWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: name).recipe(.cardTitle).lineLimit(2)
                HStack(spacing: DS.Space.s1) {
                    SourceBadge(source: source)
                    if let count { Text(verbatim: "\(count)").recipe(.caption) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// «Porque viste X»: el póster de lo que viste a la izquierda y, al lado, lo que Trakt relaciona (se desliza).
struct BecauseCard<Related: View>: View {
    let seedTitle: String
    let seedPoster: String?
    @ViewBuilder var related: () -> Related

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            PosterView(url: seedPoster, title: seedTitle).frame(width: DS.Collections.seedPoster)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Porque viste").recipe(.eyebrow, color: DS.accent)
                Text(verbatim: seedTitle).recipe(.cardTitle).lineLimit(2)
                Text("Lo que Trakt relaciona con lo último que viste").recipe(.caption).lineLimit(2)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DS.Space.s2) { related() }
                        .environment(\.posterCaptions, false)
                }
                .padding(.top, DS.Space.s1)
            }
        }
        .padding(DS.Space.s3)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }
}

/// Un año en «Por año»: cuatro pósters de ese año en mosaico y el número grande encima.
struct YearCard: View {
    let year: Int
    let posters: [String]

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            let half = DS.Collections.yearWidth / 2
            LazyVGrid(columns: [GridItem(.fixed(half), spacing: 0), GridItem(.fixed(half), spacing: 0)], spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    PosterView(url: i < posters.count ? posters[i] : nil, title: String(year), aspect: nil, bleed: true, maxPoints: DS.Image.card)
                        .frame(width: half, height: DS.Collections.yearHeight / 2)
                }
            }
            LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom)
            Text(verbatim: String(year))
                .font(DS.TextRecipe.display.font).fontWeight(.heavy).fontDesign(.rounded).monospacedDigit()
                .foregroundStyle(DS.paper)
                .padding(.horizontal, DS.Space.s3).padding(.bottom, DS.Space.s1)
        }
        .frame(width: DS.Collections.yearWidth, height: DS.Collections.yearHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(year)))
    }
}

/// Arriba de Para ti: el ícono de la app y «Orbital» (sin el título de la pantalla).
struct AppMark: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(scheme == .dark ? "AppIconPreview/night" : "AppIconPreview/day").resizable().scaledToFill()
                .frame(width: DS.Collections.appMark, height: DS.Collections.appMark)
                .clipShape(RoundedRectangle(cornerRadius: DS.Collections.appMarkRadius, style: .continuous))
            Text(verbatim: "Orbital").recipe(.section).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Orbital"))
        .accessibilityAddTraits(.isHeader)
    }
}

/// El nombre de un estudio al frente de su tarjeta (sus logos de TMDB no se leen sobre fondo oscuro).
struct StudioEmblem: View {
    let name: String
    var body: some View {
        Text(verbatim: name).recipe(.cardTitle, color: DS.backdropDeep).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
            .background(DS.paper, in: Capsule())
            .shadow(color: DS.scrimStrong, radius: DS.Space.s2)
            .padding(.horizontal, DS.Space.s2)
            .accessibilityHidden(true)
    }
}
