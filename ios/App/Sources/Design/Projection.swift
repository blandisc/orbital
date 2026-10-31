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
    /// Es el porqué del título (la portada de Inicio): en el turquesa de los porqués, como el de cada sección.
    var reason = false

    var body: some View {
        text.recipe(.eyebrow, color: reason ? DS.eyebrow : accent ? DS.accent : onArt ? DS.onArtSecondary : nil).lineLimit(1)
            .shadow(DS.Elevation.low.color(onArt ? DS.scrim : .clear))   // sobre la parte clara del arte, como el logo
    }
}



/// Una pieza ancha 16:9 de un riel (lo que tenías a medias, episodios nuevos): el arte con su avance y, debajo, el nombre y
/// una línea de datos.
struct StillCard: View {
    let title: String
    let art: String?
    var data: [String] = []
    var progress: Double?
    /// `nil`: el ancho de su columna (la cuadrícula de «Todo lo que sigues»).
    var width: CGFloat? = DS.Poster.stillWidth
    /// Si `art` no carga (`PosterView.fallback`).
    var fallback: String? = nil

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            ZStack(alignment: .bottom) {
                PosterView(url: art, title: title, aspect: DS.Poster.stillAspect, fallback: fallback)
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

/// Los puntos de un carrusel: dónde estás (una gota alargada que brinca de punto a punto) y cuántas hay.
struct PageDots: View {
    let count: Int
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if count > 1 {
            // El activo es una gota alargada (como el de la TV) que brinca de punto a punto con un resorte: se estira al
            // salir y se asienta al llegar.
            HStack(spacing: DS.Space.s2) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i == index ? DS.text : DS.fillStrong)
                        .frame(width: i == index ? DS.Size.pageDot * DS.Size.pageDotStretch : DS.Size.pageDot, height: DS.Size.pageDot)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: DS.Size.pageDotSpring, dampingFraction: DS.Size.pageDotDamping), value: index)
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
    /// Del alto de un control (en una fila con otra cápsula, como en la ficha): sin el mínimo de 44 pt encima del relleno del
    /// estilo, que la dejaba de ~56 pt con mucho aire arriba y abajo.
    var compact = false

    var body: some View {
        Menu {
            Picker(selection: $selection) { ForEach(items) { label($0).tag($0) } } label: { EmptyView() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                if compact { label(selection).recipe(.secondary, color: DS.text).fontWeight(.semibold) } else { label(selection).recipe(.cardTitle) }
                Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textMuted)
            }
            .frame(minHeight: compact ? nil : DS.Size.touchTarget)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(DS.text)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// ▲ 2 · ▼ 1 · Nuevo (sin cambio, nada): cuánto se movió un título en su lista desde la foto anterior (el Top 10 real de la TV).
struct MovementBadge: View {
    let movement: Int?
    var isNew = false

    var body: some View {
        Group {
            if isNew { Text("Nuevo").recipe(.eyebrow, color: DS.accent) }
            // Sin cambio: nada a la vista (un «=» suelto bajo el póster parecía un error); el renglón guarda su alto.
            else if let movement, movement == 0 { Text("Nuevo").recipe(.eyebrow).hidden().accessibilityHidden(true) }
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
    /// El arte: una imagen del catálogo de la app (los géneros: arte de Grok Imagine, dirección cinematográfica) o, si no, una de internet.
    var asset: String? = nil
    var art: String? = nil

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        ZStack(alignment: .bottomLeading) {
            // El arte va dentro de un `overlay` de un `Color.clear`: una imagen `scaledToFill` se pide su ancho de alto × proporción
            // y empujaba la columna más allá del margen (en un iPhone de 375 pt las dos columnas se salían y se pegaban entre sí).
            Color.clear.overlay {
                if let asset { Image(asset).resizable().scaledToFill() }
                else { PosterView(url: art, title: "", aspect: nil, bleed: true, maxPoints: DS.Image.card) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            .overlay(ArtVeil(at: 0))
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
            // El póster como póster (vertical, esquinas suaves); el logo de un canal en vivo, cuadrado. Nunca en círculo.
            // Completo, con su propia forma: el arte de la TV no siempre es vertical y antes se recortaba.
            PosterView(url: now.art, title: now.title, aspect: now.live ? 1 : DS.Poster.aspect, whole: true)
                .frame(height: DS.Size.accessoryArt)
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
                    .accessibilityLabel(now.paused ? Text("Continuar") : Text("Pausa"))
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
            .navigationDestination(for: TmdbRoute.self) { TmdbTitleView(title: $0.title) }   // recomendaciones, saga, filmografía
            .navigationDestination(for: PersonRoute.self) { PersonView(route: $0) }
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
    /// Tocar el logo o los datos abre la ficha (serie o película).
    var open: (() -> Void)?
    let watch: () -> Void
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var more: () -> More
    @State private var opened = 0

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Eyebrow(text: reason, accent: true)
                // Los logos de metahub son claros: sobre el papel del modo claro, el nombre en texto.
                TitleLogo(url: scheme == .dark ? logo : nil, title: title).frame(maxHeight: DS.Size.captionLogo, alignment: .leading)
                if !data.isEmpty { DataLine(parts: data) }
            }
            // Un toque, no un arrastre: arrastrar desde el pie sigue moviendo el mosaico de atrás.
            .onTapGesture { opened += 1; open?() }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: opened)
            .accessibilityAddTraits(open == nil ? [] : .isButton)
            .accessibilityHint(open == nil ? Text(verbatim: "") : Text("Abre la ficha"))
            .accessibilityIdentifier("mosaic-caption-open")
            Spacer(minLength: DS.Space.s2)
            DSMoreMenu {
                // La ficha también a la vista en «Más» (tocar el nombre la abre, pero no se adivinaba).
                if let open { Button("Ver la ficha", systemImage: "info.circle", action: open) }
                more()
            }
            Button(action: watch) { Image(systemName: "play.fill") }   // como en toda la app (antes, una flecha en las series)
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
    @State private var tint = ArtTint()

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
            .fittedFormSizing()
    }
}

/// Como `FittedSheet` pero para una hoja cuya raíz es un `ScrollView`: la altura sale del contenido de la lista, sin
/// `fixedSize`. Con `fixedSize` la lista larga medía más que la pantalla, la hoja se topaba y lo de abajo quedaba fuera
/// sin poder recorrerse (p. ej. «Fuente» en el reproductor). Así, si no cabe, la hoja llega al tope y la lista se desplaza.
private struct FittedScrollSheet: ViewModifier {
    @State private var height: CGFloat = DS.Size.touchTarget * 6

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom } action: { _, h in height = h }
            .presentationDetents([.height(height)])
            .presentationDragIndicator(.visible)
            .fittedFormSizing(idealHeight: height)
    }
}

extension View {
    /// En ventanas anchas (iPad, Mac) iOS no usa las alturas de la hoja (`presentationDetents`): la muestra como tarjeta
    /// centrada. Con esto la tarjeta mide lo que trae, como la hoja del iPhone. En el iPhone no cambia nada.
    /// `idealHeight`: el alto medido de una hoja cuya raíz se desplaza (lista, `NavigationStack`), que sola diría «casi nada».
    func fittedFormSizing(idealHeight: CGFloat? = nil) -> some View {
        frame(idealHeight: idealHeight).presentationSizing(.form.fitted(horizontal: false, vertical: true))
    }
    /// Receta: hoja a la medida de su lista, que se desplaza si no cabe (ver `FittedScrollSheet`). Va sobre el `ScrollView`.
    func fittedScrollSheet() -> some View { modifier(FittedScrollSheet()) }
    /// Receta: hoja a la medida de su contenido (ver `FittedSheet`).
    func fittedSheet() -> some View { modifier(FittedSheet()) }
    /// Receta: el aire de una hoja con encabezado propio (sin barra de navegación): `DS.Space.sheetTop` arriba, para que el
    /// título no se pegue al asa, y el margen de siempre a los lados y abajo. `sides: false` si su contenido llega a las
    /// orillas (un carrusel) y pone su propio margen. DesignTests lo exige en toda hoja sin barra.
    func dsSheetContent(sides: Bool = true) -> some View {
        padding(.horizontal, sides ? DS.Space.gutter : 0).padding(.top, DS.Space.sheetTop).padding(.bottom, DS.Space.s4)
    }
}

extension View {
    /// Receta: el subtítulo de la barra solo cuando dice algo («3 cambios por subir», el espacio de Descargas). Sin él, el
    /// título se queda grande y todas las pestañas arrancan igual (con subtítulo iOS lo encoge).
    @ViewBuilder func subtitle(_ text: Text?) -> some View {
        if let text { navigationSubtitle(text) } else { self }
    }
}

/// Cómo responde una pieza tocable al puntero (mouse o trackpad en el iPad y la Mac). En el iPhone no hay puntero: no hace nada.
enum PointerHover {
    /// Tarjetas y pósters: se elevan un poco, como en tvOS.
    case lift
    /// Teclas, renglones y chips: se iluminan.
    case highlight
}

extension View {
    /// Receta: la respuesta al puntero de las piezas del catálogo (`PosterCard`, `RemoteKey`…), con su esquina redondeada.
    @ViewBuilder func pointerHover(_ kind: PointerHover) -> some View {
        switch kind {
        // Sin `focusable` aquí: hacía tronar la app en iOS 26.3 al dibujar los pósters (29 oct) y en el simulador no movía
        // el foco del teclado de todos modos.
        case .lift: contentShape(.hoverEffect, .rect(cornerRadius: DS.Radius.lg)).hoverEffect(.lift)
        case .highlight: contentShape(.hoverEffect, .rect(cornerRadius: DS.Radius.md)).hoverEffect(.highlight)
        }
    }
}

/// Listas y formularios a un ancho de lectura en ventanas anchas (iPad, Mac): el contenido al centro, el fondo y la barra
/// de desplazamiento a todo lo ancho. Solo actúa cuando la pantalla mide más que el ancho de lectura de la ficha
/// (`DS.TitleAction.readableWidth`): en el iPhone nunca se activa y quedan los márgenes de siempre.
private struct ReadableListWidth: ViewModifier {
    /// El ancho visible y lo que tapa la barra lateral del iPad (en horizontal se dibuja encima: cuenta como área segura).
    @State private var visible: CGFloat = 0
    @State private var sidebar: CGFloat = 0

    func body(content: Content) -> some View {
        let margin = (visible - DS.TitleAction.readableWidth) / 2
        Group {
            // El margen de la izquierda no se suma al de la barra lateral (queda el mayor): se le agrega a mano para que
            // la lista quede al centro de lo visible y no cargada a un lado.
            if margin > 0 {
                content.contentMargins(.leading, sidebar + margin, for: .scrollContent)
                    .contentMargins(.trailing, margin, for: .scrollContent)
            } else { content }
        }
        .onGeometryChange(for: CGSize.self) { CGSize(width: $0.size.width, height: $0.safeAreaInsets.leading) } action: {
            visible = $0.width; sidebar = $0.height
        }
    }
}

extension View {
    /// Receta: lista o formulario a un ancho de lectura en ventana ancha (ver `ReadableListWidth`).
    func readableListWidth() -> some View { modifier(ReadableListWidth()) }
}
