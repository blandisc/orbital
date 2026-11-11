import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Filtrar por tipo (series o películas) y las filas de fichas.
/// Los íconos de los tipos, los mismos en toda la app (menús, la cápsula de lo elegido, los chips de filtros, el mosaico):
/// Todo, Películas y Series. «tv» no: ese es «Ver en la TV».
enum KindGlyph {
    static let all = "square.grid.2x2", movie = "film", series = "play.rectangle.on.rectangle"
    /// "" o nil es todo, «movie» o «series».
    static func symbol(_ kind: String?) -> String {
        switch kind { case "movie": movie; case "series": series; default: all }
    }
}

/// El filtro de tipo de toda la app: Todo · Películas · Series (o solo Películas · Series), siempre el mismo control y en
/// ese orden. I8 (revisión del 10 nov): había tres caras (la pastilla de Inicio, pestañas de texto en Explorar y Buscar, y
/// un segmentado de íconos en el Top 10); ahora es una sola pieza, `KindPill`: los tres íconos en una pastilla de vidrio y
/// lo elegido en el círculo blanco (Fernando: íconos, no cápsulas de texto). En Inicio va recogida junto al logo (solo lo
/// que ves; al tocarla se abre, SX1); en las demás pantallas, siempre abierta. `kind`: "" es todo, «movie» o «series».
/// `counts`: cuántas hay de cada uno (Buscar), para VoiceOver y al dejar el dedo encima.
struct DSKindFilter: View {
    @Binding var kind: String
    var includeAll = true
    var counts: (movies: Int, series: Int)?
    /// EH1 (Fernando, 9 nov): recogida junto al logo de Inicio; se abre al tocarla.
    var menu = false
    /// SX1: si la pastilla está abierta (Inicio quita la cápsula mientras eliges, para que quepa).
    var open: Binding<Bool>? = nil

    var body: some View {
        if menu {
            KindPill(kind: $kind, open: open ?? .constant(false), options: options)
        } else {
            KindPill(kind: $kind, open: .constant(true), options: options, alwaysOpen: true)
                .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
        }
    }

    private var options: [(String, LocalizedStringKey)] {
        let movies: LocalizedStringKey = counts.map { "Películas \($0.movies)" } ?? "Películas"
        let series: LocalizedStringKey = counts.map { "Series \($0.series)" } ?? "Series"
        return (includeAll ? [("", "Todo")] : []) + [("movie", movies), ("series", series)]
    }
}

/// Pestañas de texto, la misma pieza en toda la app (Todo · Películas · Series, Semana · Mes · Año · Siempre): la elegida en
/// blanco y negrita con una rayita blanca debajo, las otras en gris; con ícono si lo traen. Sin cápsula (Fernando, 30 oct
/// 2026). Se lee sobre el arte con su sombra.
struct DSTextTabs<ID: Hashable>: View {
    struct Option { let id: ID; let title: Text; var symbol: String? = nil }
    let options: [Option]
    @Binding var selection: ID
    /// La rayita de la elegida (blanca; turquesa solo en Inicio).
    var mark: Color = DS.text

    var body: some View {
        // Si con la letra grande no caben los nombres, solo los íconos (cada uno con su nombre para VoiceOver): nunca se sale
        // de la pantalla (antes «T… Pe…» quedaba cortado por la orilla izquierda).
        // I13 · antes de quedarse solo con íconos, los nombres sin ícono: en un SE «Descargas · Mi media · Guardado» no cabía
        // con ícono y la Biblioteca se quedaba sin palabras.
        ViewThatFits(in: .horizontal) {
            tabs(titles: true)
            tabs(titles: true, icons: false)
            tabs(titles: options.allSatisfy { $0.symbol == nil })
        }
        // Sin sombra (Fernando, 4 nov 2026): se veía como un halo sucio alrededor de las letras.
        .animation(DS.Motion.fade, value: selection)
        .dsFeedback(.selection, trigger: selection)
    }

    private func tabs(titles: Bool, icons: Bool = true) -> some View {
        HStack(spacing: DS.Space.s5) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = selection == option.id
                Button { selection = option.id } label: {
                    VStack(spacing: DS.Space.s1) {
                        // El ícono es siempre el mismo trazo (antes la elegida se rellenaba: «folder.fill» al lado de una flecha
                        // que no tiene relleno) y el ancho es el de la letra gruesa en las dos: al cambiar de pestaña no cambia
                        // ningún ícono ni se recorre nada (Fernando, 4 nov 2026, la 1774: «cambian los íconos»).
                        ZStack {
                            label(option, titles: titles, icons: icons, bold: true).hidden()
                            label(option, titles: titles, icons: icons, bold: on)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(option.title)
                        .font(DS.TextRecipe.cardTitle.font)
                        .foregroundStyle(on ? DS.text : DS.textMuted)
                        Capsule().fill(on ? mark : .clear).frame(width: DS.Filter.tabMark, height: DS.Filter.tabMarkHeight)
                    }
                    .padding(.vertical, DS.Space.s1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// El ícono con el mismo trazo siempre; solo el nombre cambia de peso.
    private func label(_ option: Option, titles: Bool, icons: Bool, bold: Bool) -> some View {
        HStack(spacing: DS.Space.s1) {
            if icons, let symbol = option.symbol { Image(systemName: symbol).fontWeight(.semibold) }   // ds-exception: el trazo fijo del ícono de la pestaña
            if titles { option.title.lineLimit(1).fontWeight(bold ? .bold : .medium) }   // ds-exception: la pestaña elegida se distingue por el peso
        }
    }
}

/// La cápsula del sistema (`.button`) o nada (`.title`: el menú sin el azul de iOS).
private struct ChoiceMenuLook<ID: Hashable>: ViewModifier {
    let style: DSChoiceMenu<ID>.Style
    func body(content: Content) -> some View {
        if style == .title { content.buttonStyle(.plain) } else { content.dsSecondaryButton() }   // ds-exception: el título que abre su menú no es un botón suelto
    }
}

/// Un género en una lista desplegable nativa («Género ⌃⌄», o el elegido): la misma cápsula y el mismo `Menu` con `Picker`
/// que las temporadas (`DSSeasonMenu`). El mazo de «¿Qué vemos hoy?» (Fernando, 3 nov 2026). `name`: cómo se llama cada uno.
struct DSGenreMenu: View {
    let genres: [String]
    @Binding var selection: String?
    var name: (String) -> String = { $0 }

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                Text("Todos los géneros").tag(String?.none)
                ForEach(genres, id: \.self) { Text(verbatim: name($0)).tag(String?.some($0)) }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: FilterPage.genre.symbol).font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted).accessibilityHidden(true)
                (selection.map { Text(verbatim: name($0)) } ?? Text("Género")).recipe(.labelLarge, color: DS.text).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
            }
        }
        .dsSecondaryButton()
        .dsFeedback(.selection, trigger: selection)
        .accessibilityLabel(Text("Género"))
        .accessibilityValue(selection.map { Text(verbatim: name($0)) } ?? Text("Todos los géneros"))
        .accessibilityIdentifier("genre-menu")
    }
}

/// Una lista desplegable nativa con lo elegido a la vista («Mi lista ⌃⌄»): la misma cápsula y el mismo `Menu` con `Picker`
/// que las temporadas (`DSSeasonMenu`) y los géneros (`DSGenreMenu`), para elegir uno entre opciones que cambian y no caben
/// como pestañas: la lista de Biblioteca › Guardado (Mi lista o una tuya de Trakt; Fernando, 3 nov 2026, BI1-A).
struct DSChoiceMenu<ID: Hashable>: View {
    struct Option { let id: ID; let title: Text; var symbol: String? = nil }
    let options: [Option]
    @Binding var selection: ID
    /// Qué se elige (para VoiceOver): «Lista».
    let label: Text
    /// `.button`: la cápsula con su ícono. `.title`: el nombre como título de la pantalla con ⌃⌄, sin cápsula, al ras del margen
    /// (Guardado, «Mi lista ⌃⌄»; Fernando, 4 nov 2026: «estilízalo un poco más»; la cápsula lo metía del margen).
    enum Style { case button, title }
    var style: Style = .button

    private var current: Option? { options.first { $0.id == selection } }

    var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Label { option.title } icon: { if let symbol = option.symbol { Image(systemName: symbol) } }.tag(option.id)
                }
            } label: { EmptyView() }
        } label: {
            if style == .title {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                    (current?.title ?? Text(verbatim: "")).recipe(.section, color: DS.text).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
                }
                .frame(minHeight: DS.Size.touchTarget)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: DS.Space.s2) {
                    if let symbol = current?.symbol {
                        Image(systemName: symbol).font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted).accessibilityHidden(true)
                    }
                    (current?.title ?? Text(verbatim: "")).recipe(.labelLarge, color: DS.text).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
                }
            }
        }
        .modifier(ChoiceMenuLook(style: style))
        .dsFeedback(.selection, trigger: selection)
        .accessibilityLabel(label)
        .accessibilityValue(current?.title ?? Text(verbatim: ""))
    }
}

/// SX1 (Fernando, 9 nov): el selector de Inicio es solo el ícono de lo que ves. Al tocarlo, la misma pastilla crece con un
/// resorte (los íconos un poco más grandes, para tocarlos fácil), los otros dos salen uno tras otro y la cápsula de al lado
/// se recoge a la derecha hasta quedar solo tu foto. Al elegir, el círculo blanco se desliza al nuevo y la pastilla se encoge con él. Dejar el dedo
/// encima dice su nombre; VoiceOver lo lee siempre. Con «Reducir movimiento», fundido.
struct KindPill: View {
    @Binding var kind: String
    @Binding var open: Bool
    let options: [(String, LocalizedStringKey)]
    /// I8 · fuera de Inicio la pastilla está siempre abierta: tocar un ícono lo elige y nada se recoge.
    var alwaysOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var mark

    private var motion: Animation { DS.Motion.morph(reduceMotion) ?? DS.Motion.fade }

    var body: some View {
        let shown = open ? options : options.filter { $0.0 == kind }
        HStack(spacing: open ? DS.Space.s1 : 0) {
            ForEach(Array(shown.enumerated()), id: \.element.0) { index, option in
                let on = kind == option.0
                Button { choose(option.0) } label: {
                    Image(systemName: KindGlyph.symbol(option.0)).symbolVariant(.fill)   // siempre relleno: el ícono no cambia de dibujo al cerrar
                        .font(DS.TextRecipe.section.font)
                        .scaleEffect(option.0 == "series" ? DS.KindPill.seriesOptical : 1)   // el de series es más ancho: se ve del mismo peso que los otros
                        // el mismo tamaño abierto: así el círculo cubre hasta el ícono más ancho (series)
                        .foregroundStyle(on && open ? DS.bg : DS.text)
                        .frame(width: open ? DS.KindPill.open : DS.KindPill.closed, height: open ? DS.KindPill.open : DS.KindPill.closed)
                        .background {
                            if on && open { Circle().fill(DS.text).matchedGeometryEffect(id: "mark", in: mark) }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(KindPillPress())
                .help(Text(option.1))
                .accessibilityLabel(open ? Text(option.1) : Text(option.1) + Text(". Cambiar entre todo, películas y series"))
                .accessibilityIdentifier("kind-\(option.0.isEmpty ? "all" : option.0)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .transition(.asymmetric(
                    insertion: .scale(scale: DS.KindPill.enterScale).combined(with: .opacity)
                        .animation(motion.delay(Double(index) * DS.Motion.entranceStep)),
                    removal: .opacity.animation(DS.Motion.snap(reduceMotion) ?? DS.Motion.fade)))   // se apaga en su lugar, sin flotar fuera
            }
        }
        .padding(DS.Space.s1 / 2)
        // Los círculos son de tamaño fijo: el ícono crece hasta xxxLarge y no más (con letra de accesibilidad se salía del
        // círculo); el nombre lo dice VoiceOver y la vista grande al mantener el dedo.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer()
        .glassEffect(.regular.interactive(), in: Capsule())
        .fixedSize()
        .dsFeedback(.selection, trigger: kind)
        .dsFeedback(.impact(weight: .light), trigger: open)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Series o películas"))
        #if DEBUG
        .task { if Demo.isOn, Demo.has("-demo-kind-open") { open = true } }   // capturas: abierta
        .task {   // capturas en video: abre, elige Series, y regresa a Todo
            guard Demo.isOn, Demo.has("-demo-kind-cycle") else { return }
            for next in ["series", ""] {
                try? await Task.sleep(for: .seconds(2)); choose(kind)   // ds-exception: guion de capturas, solo en DEBUG
                try? await Task.sleep(for: .seconds(1.2)); choose(next)   // ds-exception: guion de capturas, solo en DEBUG
            }
        }
        #endif
    }

    /// Cerrada abre; abierta, el círculo se desliza a lo elegido y, un instante después, se encoge con él.
    private func choose(_ option: String) {
        if alwaysOpen { withAnimation(DS.Motion.snap(reduceMotion) ?? DS.Motion.fade) { kind = option }; return }
        guard open else { withAnimation(motion) { open = true }; return }
        guard option != kind else { withAnimation(motion) { open = false }; return }
        withAnimation(DS.Motion.snap(reduceMotion) ?? DS.Motion.fade) { kind = option }
        Task {
            try? await Task.sleep(for: DS.KindPill.settle)
            withAnimation(motion) { open = false }
        }
    }
}

/// Al apretar, el ícono se hunde tantito.
private struct KindPillPress: ButtonStyle {   // ds-exception: el hundido del segmento; la pastilla es vidrio nativo
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? DS.KindPill.pressed : 1)
            .animation(DS.Motion.snap(false), value: configuration.isPressed)   // ds-exception: el hundido al apretar es inmediato y breve
    }
}
