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
    /// Con su nombre y dato debajo (Premios); sin ellos cuando el emblema ya lo dice (Estudios).
    var captioned = true
    @ViewBuilder var emblem: () -> Emblem

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            FanCard(name: name, posters: posters, tint: tint, emblem: emblem).reflected(weight: tint)
            if captioned {
                VStack(alignment: .leading, spacing: 0) {
                    title.recipe(.cardTitle).lineLimit(1)
                    detail.recipe(.caption).lineLimit(1)
                }
                .padding(.horizontal, DS.Space.s1)
            }
        }
        .frame(width: DS.PlatformFan.width, alignment: .leading)
        // VoiceOver dice el nombre y la categoría («Óscar, Mejor película»), no el id interno del premio («palm»).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(captioned ? title + Text(verbatim: ", ") + detail : title)
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
            .font(DS.TextRecipe.caption.font.weight(.bold)).tracking(DS.Collections.badgeRadius / 10)   // negrita, como `.source-badge` de la TV
            .foregroundStyle(DS.paper)
            .padding(.horizontal, DS.Space.s1 + DS.Size.hairline).padding(.vertical, DS.Size.hairline)
            .lineLimit(1).fixedSize()   // un sello no se parte en dos renglones («STRE / MIO»)
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
    /// Lo último que viste, para elegir «Porque vi…» (id, nombre); vacío: sin menú.
    var choices: [(id: String, title: String)] = []
    var choose: (String) -> Void = { _ in }
    @ViewBuilder var related: () -> Related

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            PosterView(url: seedPoster, title: seedTitle).frame(width: DS.Collections.seedPoster)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Porque viste").recipe(.eyebrow, color: DS.accent)
                if choices.count > 1 {
                    // «Porque vi esto»: tú eliges de qué; sin elegir, cambia solo cada día.
                    Menu {
                        Section("Recomiéndame por…") {
                            ForEach(choices, id: \.id) { c in
                                Button { choose(c.id) } label: {
                                    if c.title == seedTitle { Label(c.title, systemImage: "checkmark") } else { Text(verbatim: c.title) }
                                }
                            }
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                            Text(verbatim: seedTitle).recipe(.cardTitle).lineLimit(2).multilineTextAlignment(.leading)
                            Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Elige otro título para recomendarte por él"))
                    .accessibilityIdentifier("because-choose")
                } else {
                    Text(verbatim: seedTitle).recipe(.cardTitle).lineLimit(2)
                }
                Text(choices.count > 1 ? "Toca el nombre para elegir otro de lo que viste" : "Lo que Trakt relaciona con lo último que viste").recipe(.caption).lineLimit(2)
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

/// Arriba de Inicio: el logotipo de la app como en la TV y la computadora (el planeta, «orbital» y su luna), en lugar del
/// saludo. Al abrir, el anillo se dibuja y la luna cae en su lugar.
struct AppMark: View {
    var body: some View {
        OrbitalWordmark(size: DS.Size.headerWordmark, animated: true).foregroundStyle(DS.text).fixedSize()
    }
}

/// El logo de un estudio al frente de su tarjeta, sobre una cápsula clara (muchos logos son oscuros); sin logo, su nombre.
struct StudioEmblem: View {
    let name: String
    var logo: String?

    var body: some View {
        Group {
            if let url = logo.flatMap(URL.init(string:)) {
                RemoteImage(url: url, maxPoints: DS.Collections.studioLogoWidth) { phase in
                    switch phase {
                    // El logo en blanco (como la TV: brightness(0) invert(1)), sin cápsula.
                    case .success(let image): image.resizable().scaledToFit().brightness(-1).colorInvert()
                    default: nameText.padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2).background(DS.paper, in: Capsule())
                    }
                }
                .frame(width: DS.Collections.studioLogoWidth, height: DS.Collections.studioLogoHeight)
            } else {
                // Sin logo, el nombre en cápsula.
                nameText.padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2).background(DS.paper, in: Capsule())
            }
        }
        .shadow(color: DS.scrimStrong, radius: DS.Space.s2)
        .padding(.horizontal, DS.Space.s2)
        .accessibilityHidden(true)
    }

    private var nameText: some View {
        Text(verbatim: name).recipe(.cardTitle, color: DS.backdropDeep).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
    }
}

/// Una tira de tarjetas (Plataformas, Premios, Estudios, Por año) desde la orilla izquierda: las que van saliendo por los
/// lados se encogen y oscurecen un poco.
struct CenteredCarousel<Item, ID: Hashable, Card: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    let cardWidth: CGFloat
    @ViewBuilder var card: (Item) -> Card

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                ForEach(items, id: id) { item in
                    card(item)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content.scaleEffect(1 - abs(phase.value) * DS.Collections.sideShrink)
                                .brightness(-abs(phase.value) * DS.Collections.sideFade)   // más oscuras, como en el carrusel de Inicio
                        }
                }
            }
            .scrollTargetLayout()
        }
        // Desde la orilla izquierda, como el resto de las tiras (sin espacio muerto antes de la primera).
        .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

/// El reflejo de una tarjeta sobre el piso (la tarjeta volteada, corta, un poco desenfocada y que se desvanece) y su peso:
/// una sombra de su color solo bajo la tarjeta (en el reflejo dibujaba esquinas que no existen).
struct Reflection: ViewModifier {
    var weight: Color?
    func body(content: Content) -> some View {
        content
            .shadow(color: (weight ?? .clear).opacity(DS.Collections.weightTint), radius: DS.Collections.weight, y: DS.Collections.weightY)
            // La copia volteada va encima del mismo tamaño que el original (un `overlay` le da su ancho y alto): antes se le daban
            // 44 pt de alto y un póster, que guarda su proporción, se encogía a lo ancho (el reflejo «estrecho»). Su borde de
            // arriba se pega al de abajo del original y solo se ve una franja que se desvanece.
            .overlay(alignment: .bottom) {
                content
                    .scaleEffect(x: 1, y: -1)
                    .blur(radius: DS.Collections.reflectionBlur)
                    .mask(alignment: .top) {
                        LinearGradient(colors: [DS.text.opacity(DS.Collections.reflectionOpacity), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: DS.Collections.reflection)
                    }
                    .alignmentGuide(.bottom) { d in d[.top] - DS.Collections.reflectionGap }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.bottom, DS.Collections.reflection + DS.Collections.reflectionGap)
    }
}

extension View {
    /// El reflejo de un póster (solo el arte, no la tarjeta con su texto, sus marcas ni su punto de zoom): una franja volteada
    /// que se desvanece, del ancho del póster.
    func posterReflection(_ url: String?, title: String, width: CGFloat) -> some View {
        overlay(alignment: .bottom) {
            PosterView(url: url, title: title).frame(width: width)
                .scaleEffect(x: 1, y: -1)
                .blur(radius: DS.Collections.reflectionBlur)
                .mask(alignment: .top) {
                    LinearGradient(colors: [DS.text.opacity(DS.Collections.reflectionOpacity), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: DS.Collections.reflection)
                }
                .alignmentGuide(.bottom) { d in d[.top] - DS.Collections.reflectionGap }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .padding(.bottom, DS.Collections.reflection + DS.Collections.reflectionGap)
    }

    /// Una sección cuya última fila lleva reflejo (sin texto debajo): la siguiente se monta sobre la parte desvanecida.
    func reflectionTail() -> some View { padding(.bottom, -DS.Collections.reflectionTail) }

    /// Con su reflejo debajo y, si se da, el peso de su color (Colecciones).
    func reflected(weight: Color? = nil) -> some View { modifier(Reflection(weight: weight)) }
}
