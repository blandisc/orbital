import SwiftUI
import OrbitalCore

// Piezas de Proyección (el sistema visual del iPhone; ver docs/ios-interfaz.md y el canvas de diseño).
// Todas se arman con tokens (`DS.*`) y recetas de texto (`DS.TextRecipe`); las pantallas solo las componen.

extension Text {
    /// Aplica una receta de texto con su color por omisión.
    func recipe(_ recipe: DS.TextRecipe, color: Color? = nil) -> some View {
        font(recipe.font).foregroundStyle(color ?? recipe.defaultColor)
    }
}

extension DS.TextRecipe {
    var defaultColor: Color {
        switch self {
        case .display, .title, .section, .cardTitle, .body: DS.text
        case .secondary, .footnote, .caption, .eyebrow, .data: DS.textMuted
        }
    }
}

/// Una línea de datos con números tabulares (como `tabular-nums` en la TV): «T2 · E5 · quedan 20 min · termina a las 23:21».
/// Si no cabe completa, quita partes del final antes de cortar un número.
struct DataLine: View {
    let parts: [String]
    var color: Color?

    var body: some View {
        let shown = parts.filter { !$0.isEmpty }
        ViewThatFits(in: .horizontal) {
            ForEach(Array((1...max(1, shown.count)).reversed()), id: \.self) { count in
                Text(verbatim: shown.prefix(count).joined(separator: " · ")).recipe(.data, color: color).lineLimit(1)
            }
        }
    }
}

/// El rótulo pequeño sobre un título («Seguir viendo», «N.º 2 en Netflix esta semana»). Con `accent`, en el color de acento.
struct Eyebrow: View {
    let text: Text
    var accent = false
    /// Sobre el arte: más claro que el secundario de siempre.
    var onArt = false

    var body: some View {
        text.recipe(.eyebrow, color: accent ? DS.accent : onArt ? DS.onArtSecondary : nil).lineLimit(1)
            .shadow(color: onArt ? DS.scrim : .clear, radius: DS.Space.s1)   // sobre la parte clara del arte, como el logo
    }
}

/// Una acción de la rejilla de acciones de la ficha.
struct ProjectionAction: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let symbol: String
    var active = false
    var disabled = false
    let action: () -> Void
}

/// Las acciones secundarias de una ficha (Mi lista, Descargar, Fuentes…): botones nativos con relleno del sistema, del mismo
/// ancho, con ícono arriba y nombre abajo. Con letra de accesibilidad se apilan en renglones.
struct ActionGrid: View {
    let actions: [ProjectionAction]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.s2)) : AnyLayout(HStackLayout(spacing: DS.Space.s2))
        layout {
            ForEach(actions) { item in
                Button(action: item.action) {
                    VStack(spacing: DS.Space.s1) {
                        Image(systemName: item.symbol).font(DS.TextRecipe.cardTitle.font).symbolVariant(item.active ? .fill : .none)
                        Text(item.title).font(DS.TextRecipe.footnote.font).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                    .padding(.vertical, DS.Space.s2)
                }
                .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: DS.Radius.lg))
                .tint(item.active ? DS.accent : DS.text)
                .disabled(item.disabled)
                .sensoryFeedback(.selection, trigger: item.active)
            }
        }
    }
}

/// Una pieza ancha 16:9 de un riel (lo que tenías a medias, episodios nuevos): el arte con su avance y, debajo, el nombre y
/// una línea de datos.
struct StillCard: View {
    let title: String
    let art: String?
    var data: [String] = []
    var progress: Double?
    var width: CGFloat = DS.Poster.stillWidth

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ZStack(alignment: .bottom) {
                PosterView(url: art, title: title, aspect: DS.Poster.stillAspect)
                if let progress { DSProgress(fraction: progress).padding(.horizontal, DS.Space.s2).padding(.bottom, DS.Space.s2) }
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.cardTitle).lineLimit(1)
                if !data.isEmpty { DataLine(parts: data) }
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .combine)
    }
}

/// Los puntos de un carrusel (el nativo de las páginas de iOS, en pequeño): dónde estás y cuántas hay.
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: DS.Space.s2) {
                ForEach(0..<count, id: \.self) { i in
                    Circle().fill(i == index ? DS.text : DS.fillStrong).frame(width: DS.Size.pageDot, height: DS.Size.pageDot)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(index + 1) de \(count)"))
        }
    }
}

/// Elegir una opción de muchas (temporadas): el menú nativo, con la opción actual y su chevron, en un botón con relleno del sistema.
struct DSOptionMenu<Item: Hashable & Identifiable>: View {
    let items: [Item]
    let label: (Item) -> Text
    @Binding var selection: Item

    var body: some View {
        Menu {
            Picker(selection: $selection) { ForEach(items) { label($0).tag($0) } } label: { EmptyView() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                label(selection).recipe(.cardTitle)
                Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
            }
            .frame(minHeight: DS.Size.touchTarget)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(DS.text)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Un renglón con su puesto (lo más popular, la cartelera de una plataforma): el número en SF Mono, el póster chico, el nombre
/// y un dato; a la derecha, opcional, cuánto subió o bajó.
struct RankedRow: View {
    let rank: Int
    let title: String
    let poster: String?
    var detail: Text?
    /// Cuántos lugares subió (positivo) o bajó (negativo); nil si no se sabe.
    var movement: Int?
    var isNew = false

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: "\(rank)").recipe(.data).frame(minWidth: DS.Space.s5, alignment: .leading)
            PosterView(url: poster, title: title).frame(width: DS.Poster.rowWidth)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.body).lineLimit(1)
                if let detail { detail.recipe(.footnote).lineLimit(1) }
            }
            Spacer(minLength: DS.Space.s2)
            if isNew || movement != nil { MovementBadge(movement: movement, isNew: isNew) }
        }
        .frame(minHeight: DS.Size.touchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// ▲ 2 · ▼ 1 · = · Nuevo: cuánto se movió un título en su lista desde la foto anterior (el Top 10 real de la TV).
struct MovementBadge: View {
    let movement: Int?
    var isNew = false

    var body: some View {
        Group {
            if isNew { Text("Nuevo").recipe(.eyebrow, color: DS.accent) }
            else if let movement, movement == 0 { Text(verbatim: "=").recipe(.data) }
            else if let movement, movement > 0 { Label { Text(verbatim: "\(movement)") } icon: { Image(systemName: "arrowtriangle.up.fill") }.recipe(.data, color: DS.accent) }
            else if let movement { Label { Text(verbatim: "\(-movement)") } icon: { Image(systemName: "arrowtriangle.down.fill") }.recipe(.data) }
        }
        .labelStyle(.titleAndIcon)
    }
}

extension Label where Title == Text, Icon == Image {
    func recipe(_ recipe: DS.TextRecipe, color: Color? = nil) -> some View {
        font(recipe.font).foregroundStyle(color ?? recipe.defaultColor)
    }
}

/// Un mosaico con arte y un nombre encima (géneros de Explora): el arte se tiñe de oscuro abajo para que el nombre se lea.
struct ArtTile: View {
    let title: Text
    /// El arte: una imagen del catálogo de la app (los géneros, `scripts/genre_art.py`) o, si no, una de internet.
    var asset: String? = nil
    var art: String? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let asset { Image(asset).resizable().scaledToFill() }
                else { PosterView(url: art, title: "", aspect: nil, bleed: true, maxPoints: DS.Image.card) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .overlay(LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .top, endPoint: .bottom))
            title.recipe(.cardTitle).padding(DS.Space.s3).onArt()
        }
        .frame(height: DS.Size.artTileHeight)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(asset.map { "art-tile-\($0)" } ?? "art-tile")
    }
}

/// Lo que suena en tu Orbital, en el accesorio de la barra de pestañas (como el MiniPlayer de Música): el póster, el nombre,
/// «En la TV · T1 E5» y pausa / reanudar. Vive en toda la app mientras la TV reproduce algo.
struct TVAccessory: View {
    let now: OrbitalRemote.NowPlaying
    var busy = false
    let toggle: () -> Void
    /// Abre el control remoto completo (también con VoiceOver: es un botón).
    let openRemote: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// El arte y el nombre (lo que se toca para abrir el control remoto).
    private var info: some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: now.poster, title: now.title, aspect: 1).frame(width: DS.Size.accessoryArt).clipShape(Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(now.live ? (now.channel ?? now.title) : now.title).recipe(.cardTitle).lineLimit(1)
                if placement != .inline {
                    Text(now.live ? "En la TV · En vivo" : "En la TV").recipe(.footnote, color: now.live ? DS.live : DS.textMuted).lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Button(action: openRemote) { info }.buttonStyle(.plain).accessibilityHint(Text("Control remoto"))
            Spacer(minLength: DS.Space.s2)
            if !now.live {
                Button(action: toggle) { Image(systemName: now.paused ? "play.fill" : "pause.fill") }
                    .buttonStyle(.plain).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                    .disabled(busy)
                    .accessibilityLabel(now.paused ? Text("Reanudar") : Text("Pausa"))
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// El accesorio de la barra de pestañas solo mientras hay algo que enseñar (`isEnabled` es de iOS 26.1; en 26.0 no se pone).
    @ViewBuilder func bottomAccessory<Content: View>(isEnabled: Bool, @ViewBuilder content: @escaping () -> Content) -> some View {
        if #available(iOS 26.1, *) { tabViewBottomAccessory(isEnabled: isEnabled, content: content) } else { self }
    }
}

// MARK: Póster → ficha con la transición de zoom nativa

private struct TitleZoomKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }

extension EnvironmentValues {
    /// El espacio de la transición de zoom de la pantalla (lo pone `titleDestinations()`).
    var titleZoom: Namespace.ID? {
        get { self[TitleZoomKey.self] }
        set { self[TitleZoomKey.self] = newValue }
    }
}

/// La receta de cada pantalla que abre fichas: la navegación a `TitleRoute` y el zoom desde el póster que se tocó.
private struct TitleDestinations: ViewModifier {
    @Namespace private var zoom

    func body(content: Content) -> some View {
        content
            .environment(\.titleZoom, zoom)
            .navigationDestination(for: TitleRoute.self) { route in
                TitleView(route: route).navigationTransition(.zoom(sourceID: route, in: zoom))
            }
    }
}

private struct TitleZoomSource: ViewModifier {
    let route: TitleRoute
    @Environment(\.titleZoom) private var zoom

    func body(content: Content) -> some View {
        if let zoom { content.matchedTransitionSource(id: route, in: zoom) } else { content }
    }
}

extension View {
    /// Abre fichas desde esta pantalla, con zoom desde el póster.
    func titleDestinations() -> some View { modifier(TitleDestinations()) }
    /// Este póster es el origen del zoom al abrir su ficha.
    func titleZoomSource(_ route: TitleRoute) -> some View { modifier(TitleZoomSource(route: route)) }
}

/// La pieza enfocada del mosaico, contada bajo él (el mosaico solo enseña pósters del mismo tamaño): por qué te la sugiere
/// (en el acento), su nombre, sus datos en SF Mono y Ver / Más. Aparece y se va con el foco (en ambiente no hay).
struct MosaicCaption<More: View>: View {
    let reason: Text
    let title: String
    /// El logo del título (como en la pieza enfocada de la TV); si no carga, su nombre.
    var logo: String?
    let data: [String]
    /// Los colores del arte de la pieza: «Ver» toma su color claro, como en la TV.
    var accent: ArtColors?
    /// Una serie abre su ficha («Ver la serie»).
    var isSeries = false
    let watch: () -> Void
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var more: () -> More

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Eyebrow(text: reason, accent: true)
                // Los logos de metahub son claros: sobre el papel del modo claro, el nombre en texto.
                TitleLogo(url: scheme == .dark ? logo : nil, title: title).frame(maxHeight: DS.Size.captionLogo, alignment: .leading)
                if !data.isEmpty { DataLine(parts: data) }
            }
            Spacer(minLength: DS.Space.s2)
            Menu { more() } label: { Image(systemName: "ellipsis") }
                .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.large).tint(DS.text)
                .accessibilityLabel(Text("Más"))
            Button(action: watch) { Image(systemName: isSeries ? "chevron.right" : "play.fill") }
                .dsArtButton(accent).buttonBorderShape(.circle).controlSize(.large)
                .accessibilityLabel(isSeries ? Text("Ver la serie") : Text("Ver"))
        }
        .accessibilityElement(children: .contain)
    }
}

/// Da a su contenido los colores del arte de una URL (`ArtPalette`, con caché): para que cada botón tome el color de su propio
/// título, no el del que está al frente.
struct WithArtColors<Content: View>: View {
    let url: String?
    @ViewBuilder let content: (ArtColors?) -> Content
    @StateObject private var tint = ArtTint()

    var body: some View { content(tint.colors).task(id: url) { await tint.load(url) } }
}

/// Las acciones de un destacado (el botón principal y los secundarios): en un renglón; si no caben (letra grande, iPhone
/// chico), una debajo de la otra, sin cortar «Continuar» a media palabra.
struct HeroActions<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s3) { content() }
            VStack(alignment: .leading, spacing: DS.Space.s2) { content() }
        }
    }
}

/// Una hoja tan alta como lo que trae (el control remoto de la TV, avisos cortos): mide su contenido y lo usa de alto, en
/// vez de media pantalla con un hueco abajo. Si el contenido cambia de alto, la hoja lo sigue.
private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = DS.Size.touchTarget * 6

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Receta: hoja a la medida de su contenido (ver `FittedSheet`).
    func fittedSheet() -> some View { modifier(FittedSheet()) }
}
