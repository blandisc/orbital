import SwiftUI

// Piezas de superficie del catálogo (auditoría de diseño del 31 oct 2026, D4–D8, D11, D19, D21): la caja, el encabezado de
// una hoja, la ruedita con texto, el anillo de lo elegido, el rótulo de un grupo, el brillo y el selector de temporada.
// Antes cada pantalla armaba la suya con otro radio, otro grosor u otro tamaño de letra.

/// Los dos niveles de caja de toda la app: un renglón o caja chica (`row`, esquina `lg`) y una tarjeta grande (`card`,
/// esquina `xl`). Siempre continua. Sobre la pantalla va en la superficie (blanca en claro); sobre arte, un fondo teñido o
/// dentro de otra caja, translúcida (`translucent`), que deja pasar el tono.
enum DSCardLevel {
    case row, card
    var radius: CGFloat { self == .row ? DS.Radius.lg : DS.Radius.xl }
}

extension View {
    /// Receta: el fondo de una caja (`DSCardLevel`). Solo el fondo: el aire de adentro lo pone quien la usa. `fill` cambia el
    /// relleno cuando la caja dice algo (elegida, la de ahora, la recomendada); sin él, el de siempre.
    func dsCard(_ level: DSCardLevel = .row, translucent: Bool = false, fill: Color? = nil) -> some View {
        background(fill ?? (translucent ? DS.fill : DS.surface), in: RoundedRectangle(cornerRadius: level.radius, style: .continuous))
    }

    /// Receta: el anillo de lo elegido (un avatar, una opción, una plataforma), en el color del texto y del grueso de lo
    /// elegido (`DS.Stroke.selected`); sin elegir, nada (el lugar no cambia). Por dentro de la forma: no la agranda.
    func dsSelectionRing<S: InsettableShape>(_ selected: Bool, in shape: S, width: CGFloat = DS.Stroke.selected) -> some View {
        overlay(shape.strokeBorder(selected ? DS.text : .clear, lineWidth: width))
    }

    /// Lo mismo en una caja de esquinas redondeadas (continuas).
    func dsSelectionRing(_ selected: Bool, radius: CGFloat, width: CGFloat = DS.Stroke.selected) -> some View {
        dsSelectionRing(selected, in: RoundedRectangle(cornerRadius: radius, style: .continuous), width: width)
    }

    /// Receta: un brillo del color de la pieza (`DS.Glow`), sin caída. `.clear` lo apaga sin mover nada.
    func glow(_ color: Color, _ strength: DS.Glow = .soft) -> some View {
        shadow(color: color, radius: strength.radius)
    }
}

/// Una caja con su aire de adentro (`DS.Space.s4`) y su fondo (`dsCard`).
struct DSCard<Content: View>: View {
    var level: DSCardLevel = .row
    var translucent = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().padding(DS.Space.s4).frame(maxWidth: .infinity, alignment: .leading).dsCard(level, translucent: translucent)
    }
}

/// El encabezado de una hoja que no tiene barra de navegación: el título (siempre `title`), una línea debajo si hace falta y
/// lo de la derecha. Va dentro de `dsSheetContent()`. Sin botón de cerrar: una hoja con asa se cierra jalándola hacia abajo y
/// la ✕ sobraba (Fernando, 4 nov 2026, la 1774: «tiene una X; quítala, ya tiene la barrita para jalarla»). La ✕ solo va
/// donde no se puede deslizar para cerrar: pantalla completa (`fullScreenCover`) y paneles (DesignRulesTests lo vigila).
struct DSSheetHeader<Trailing: View>: View {
    let title: Text
    var subtitle: Text?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                title.recipe(.title).accessibilityAddTraits(.isHeader)
                if let subtitle { subtitle.recipe(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
    }
}

/// SD3-A (Fernando, 26 nov 2026): la plantilla de toda hoja con su propio título. El título (con su subtítulo y lo de la
/// derecha) y, siempre a la misma distancia (`DS.Space.sheetHeaderGap`), el contenido con su ritmo (`spacing`). Antes cada
/// hoja ponía su propio aire entre el título y lo de abajo (s1, s2, s4 o el de las pantallas). `DesignTests` cuida que las
/// hojas usen esta y no un `DSSheetHeader` suelto.
struct DSSheet<Trailing: View, Content: View>: View {
    let title: Text
    var subtitle: Text?
    var spacing: CGFloat = DS.Space.s4
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSSheetHeader(title: title, subtitle: subtitle, trailing: trailing)
            VStack(alignment: .leading, spacing: spacing, content: content)
                .padding(.top, DS.Space.sheetHeaderGap)
        }
    }
}

extension DSSheet where Trailing == EmptyView {
    init(title: Text, subtitle: Text? = nil, spacing: CGFloat = DS.Space.s4, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, spacing: spacing, trailing: { EmptyView() }, content: content)
    }
}

extension DSSheetHeader where Trailing == EmptyView {
    init(title: Text, subtitle: Text? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Algo que espera junto a lo que lo pidió («Conectando…», «Buscando tu Orbital…»): la ruedita chica y su texto, igual en
/// toda la app. Un área entera que carga es `DSLoadingState`; una lista, el esqueleto de su forma.
struct DSInlineProgress: View {
    let text: Text

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ProgressView().dsControlSize(.small)
            text.recipe(.footnote)
        }
        .accessibilityElement(children: .combine)
    }
}

/// El rótulo de un grupo dentro de una hoja, un panel o una lista («Tu idioma», «Otras fuentes»): en mayúsculas chicas, en
/// gris. Uno solo; el texto se escribe normal (las mayúsculas las pone la pieza).
struct DSGroupLabel: View {
    let title: Text
    var color: Color = DS.textMuted

    var body: some View {
        // En letra normal, sin mayúsculas espaciadas (Fernando, 2 nov 2026, E3/G2/H2: «que todos los títulos de ese mismo estilo
        // tengan una regla en el sistema de diseño y que si cambiamos uno, cambiamos todos»).
        title.recipe(.groupLabel, color: color)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Las temporadas de una serie en una lista desplegable nativa («Temporada 3 ⌃⌄»), decisión de Fernando (1 nov 2026): en la
/// ficha, Mi media y la hoja de episodios. Las cápsulas «T1, T2…» quedan solo en el reproductor (`DSSeasonPicker`). Un
/// `Menu` con `Picker` (la elegida con su ✓), en la cápsula de los secundarios. `0` son los especiales.
struct DSSeasonMenu: View {
    let seasons: [Int]
    @Binding var selection: Int

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(seasons, id: \.self) { Self.name($0).tag($0) }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Self.name(selection).recipe(.labelLarge, color: DS.text).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
            }
        }
        .dsSecondaryButton()
        .dsFeedback(.selection, trigger: selection)
        .accessibilityIdentifier("season-menu")
    }

    static func name(_ season: Int) -> Text { season == 0 ? Text("Especiales") : Text("Temporada \(season)") }
}

/// Las temporadas en cápsulas «T1, T2…», solo en el panel de episodios del reproductor (sobre el video, siempre la versión
/// oscura). En la ficha, Mi media y la hoja de episodios va `DSSeasonMenu` (Fernando, 1 nov 2026). Botones nativos en
/// cápsula, la elegida resaltada; si no caben, se deslizan y la elegida queda a la vista. `0` son los especiales.
struct DSSeasonPicker: View {
    let seasons: [Int]
    @Binding var selection: Int
    /// El valor actual como dato de la vista: con un `Binding(get:set:)` SwiftUI no ve el cambio y no la vuelve a pintar.
    private let current: Int
    @State private var scrolled: Int?

    init(seasons: [Int], selection: Binding<Int>) {
        self.seasons = seasons; _selection = selection; current = selection.wrappedValue
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {   // sin flechas: temporadas en cápsulas
            HStack(spacing: DS.Space.s2) {
                ForEach(seasons, id: \.self) { season in
                    let label = season == 0 ? Text("Especiales") : Text("T\(season)")
                    Group {
                        if season == current {
                            Button { selection = season } label: { label.recipe(.label, color: DS.onPrimary) }
                                .buttonStyle(.borderedProminent).tint(DS.primary)
                        } else {
                            Button { selection = season } label: { label.recipe(.label, color: DS.text) }
                                .buttonStyle(.bordered).tint(DS.text)
                        }
                    }
                    .buttonBorderShape(.capsule).dsControlSize(.regular)
                    .id(season)
                    .accessibilityLabel(season == 0 ? Text("Especiales") : Text("Temporada \(season)"))
                    .accessibilityAddTraits(season == current ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
        }
        // Vive en la tarjeta de episodios del reproductor: con muchas temporadas las cápsulas se salían a los lados de la
        // tarjeta (Fernando, 25 nov 2026); se cortan en su orilla.
        .rowEdge(.inCard)
        .fixedSize(horizontal: false, vertical: true)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollPosition(id: $scrolled, anchor: .center)
        .onChange(of: current, initial: true) { _, season in scrolled = season }
        .dsFeedback(.selection, trigger: current)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("season-picker")
    }
}

/// Hasta dónde llega una fila que se desliza a lo ancho (Fernando, 22 nov 2026, en la Mac: «Lo nuevo de lo tuyo… sigue hacia
/// la derecha» y «todas las listas que siguen a la derecha, cortarlos a la misma altura… que el corte se vea estético»). Cada
/// fila lo dice: `.bleeds` es una fila suelta y `.inCard` va dentro de una tarjeta o un panel. En ventana ancha (iPad, Mac) las
/// dos terminan donde empiezan: en el margen de su contenido, el mismo a la izquierda y a la derecha, y la orilla por donde
/// sigue se desvanece (dice que hay más). En el iPhone, la suelta sigue hasta la orilla de la pantalla. Lo que crece al picarlo
/// (o al dejarlo apretado) no se corta arriba ni abajo. Nadie usa `scrollClipDisabled()` directo
/// (`DesignRulesTests.testRowsSayWhereTheyEnd`).
enum RowEdge { case bleeds, inCard }

extension View {
    func rowEdge(_ edge: RowEdge) -> some View { modifier(RowEdgeClip(edge: edge)) }
}

private struct RowEdgeClip: ViewModifier {
    let edge: RowEdge
    @State private var geo = RowGeo()
    /// Dónde queda la fila en la ventana: una fila suelta que lleva su margen como relleno de adentro (no como `contentMargins`)
    /// no lo dice en `contentInsets`, y llegaba a la orilla de la ventana (los episodios en la ficha, 22 nov 2026).
    @State private var span = ClosedRange<CGFloat>(uncheckedBounds: (0, 0))
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dónde empieza y termina el contenido (sus márgenes) y si hay más a cada lado.
    struct RowGeo: Equatable { var before = false, after = false, lead: CGFloat = 0, trail: CGFloat = 0 }

    func body(content: Content) -> some View {
        if edge == .bleeds && !WindowMetrics.roomy {
            content.scrollClipDisabled()
        } else {
            content.scrollClipDisabled()
                .onScrollGeometryChange(for: RowGeo.self) { g in
                    let offset = g.contentOffset.x + g.contentInsets.leading
                    let end = g.contentSize.width + g.contentInsets.leading + g.contentInsets.trailing - g.containerSize.width
                    return RowGeo(before: offset > 1, after: offset < end - 1, lead: g.contentInsets.leading, trail: g.contentInsets.trailing)
                } action: { _, now in
                    withAnimation(DS.Motion.base(reduceMotion)) { geo = now }
                }
                .onGeometryChange(for: ClosedRange<CGFloat>.self) { $0.frame(in: .global).minX...max($0.frame(in: .global).minX, $0.frame(in: .global).maxX) } action: { span = $0 }
                .mask {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: lead)
                        LinearGradient(colors: [geo.before ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: DS.Size.rowFade)
                        Color.black
                        LinearGradient(colors: [.black, geo.after ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: DS.Size.rowFade)
                        Color.clear.frame(width: trail)
                    }
                    .padding(.vertical, -DS.Space.s6)   // arriba y abajo, aire para lo que crece
                }
        }
    }

    /// Una fila suelta termina en el margen de la pantalla aunque su margen no venga en `contentInsets`; una de tarjeta, en el suyo.
    /// Al inicio de la fila no hay nada que esconder a la izquierda: sin corte ahí (en «Lo que ves», con el margen contado dos
    /// veces, el corte se comía el «1» y la orilla del primer póster, 22 nov 2026). Igual a la derecha al llegar al final.
    private var lead: CGFloat {
        guard geo.before else { return 0 }
        guard edge == .bleeds else { return geo.lead }
        return max(geo.lead, DS.Space.gutter - span.lowerBound, 0)
    }
    private var trail: CGFloat {
        guard geo.after else { return 0 }
        guard edge == .bleeds else { return geo.trail }
        return max(geo.trail, DS.Space.gutter - (WindowMetrics.column.width - span.upperBound), 0)
    }
}
