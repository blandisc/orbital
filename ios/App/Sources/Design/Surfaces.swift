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

    /// La única manera de escribir en mayúsculas (rótulos, sellos, listones): el texto se escribe normal y se traduce normal.
    func dsCaps() -> some View { textCase(.uppercase) }

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

/// El encabezado de una hoja que no tiene barra de navegación: el título (siempre `title`), una línea debajo si hace falta,
/// lo de la derecha y el botón de cerrar (`DSIconButton` con «xmark»). Va dentro de `dsSheetContent()`.
struct DSSheetHeader<Trailing: View>: View {
    let title: Text
    var subtitle: Text?
    var close: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                title.recipe(.title).accessibilityAddTraits(.isHeader)
                if let subtitle { subtitle.recipe(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
            if let close { DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular, action: close).accessibilityIdentifier("sheet-close") }
        }
    }
}

extension DSSheetHeader where Trailing == EmptyView {
    init(title: Text, subtitle: Text? = nil, close: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, close: close) { EmptyView() }
    }
}

/// Algo que espera junto a lo que lo pidió («Conectando…», «Buscando tu Orbital…»): la ruedita chica y su texto, igual en
/// toda la app. Un área entera que carga es `DSLoadingState`; una lista, el esqueleto de su forma.
struct DSInlineProgress: View {
    let text: Text

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ProgressView().controlSize(.small)
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
        title.recipe(.groupLabel, color: color).dsCaps().tracking(DS.Chapter.tracking)
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
        .sensoryFeedback(.selection, trigger: selection)
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
    /// El valor actual como dato de la vista (ver `DSSegmented`).
    private let current: Int
    @State private var scrolled: Int?

    init(seasons: [Int], selection: Binding<Int>) {
        self.seasons = seasons; _selection = selection; current = selection.wrappedValue
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                    .buttonBorderShape(.capsule).controlSize(.regular)
                    .id(season)
                    .accessibilityLabel(season == 0 ? Text("Especiales") : Text("Temporada \(season)"))
                    .accessibilityAddTraits(season == current ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
        }
        .fixedSize(horizontal: false, vertical: true)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollPosition(id: $scrolled, anchor: .center)
        .onChange(of: current, initial: true) { _, season in scrolled = season }
        .sensoryFeedback(.selection, trigger: current)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("season-picker")
    }
}
