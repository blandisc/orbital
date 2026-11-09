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
/// ese orden: las pestañas de texto con su ícono (`DSTextTabs`). Antes había cinco (cápsulas, un menú, solo íconos, un
/// segmentado y pestañas); Fernando, 30 oct 2026: un solo selector en toda la app. Va debajo del título de su sección, no
/// junto. `kind`: "" es todo, «movie» o «series». `counts`: cuántas hay de cada uno (Buscar).
struct DSKindFilter: View {
    @Binding var kind: String
    var includeAll = true
    var counts: (movies: Int, series: Int)?
    /// La pastilla chica junto al título (el Top 10, Fernando, 31 oct 2026): el segmentado con solo su ícono en cada opción
    /// (2 nov 2026, D1).
    var compact = false
    /// La rayita de la elegida: blanca (lo elegido) o turquesa en Inicio (Fernando, 31 oct 2026: Inicio se queda como estaba).
    var mark: Color = DS.text
    /// EH1 (Fernando, 9 nov): un menú chico «Todo ▾» junto al logo de Inicio, en vez de un renglón de pestañas.
    var menu = false
    /// SX1: si la pastilla está abierta (Inicio quita la cápsula mientras eliges, para que quepa).
    var open: Binding<Bool>? = nil

    var body: some View {
        if menu {
            KindPill(kind: $kind, open: open ?? .constant(false), options: options)
        } else if compact {
            // La pastilla propia: la nativa de iOS no pone ícono junto al texto.
            HStack(spacing: 0) {
                ForEach(options, id: \.0) { option in
                    let on = kind == option.0
                    Button { kind = option.0 } label: {
                        HStack(spacing: DS.Space.s1) {
                            Image(systemName: KindGlyph.symbol(option.0)).symbolVariant(on ? .fill : .none)
                            // Solo el ícono, sin el nombre (Fernando, 2 nov 2026, D1): el nombre va para VoiceOver.
                        }
                        .accessibilityLabel(Text(option.1))
                        .font(DS.TextRecipe.badge.font)   // chica: el título de al lado cabe en un renglón
                        .foregroundStyle(on ? DS.text : DS.textMuted)
                        .padding(.horizontal, DS.Space.s2)
                        .frame(maxHeight: .infinity)
                        .background(on ? DS.fillStrong : .clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)   // ds-exception: un segmento del control (no un botón suelto); el fondo marca el elegido
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(DS.Space.s1 / 2)
            .frame(height: DS.Size.touchTarget)
            .background(DS.fill, in: Capsule())
            .fixedSize()
            .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
            .sensoryFeedback(.selection, trigger: kind)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Series o películas"))
        } else {
            // Un grupo con su nombre; cada pestaña conserva el suyo (sin `.contain`, VoiceOver leía las tres como «Series o
            // películas»).
            DSTextTabs(options: options.map { DSTextTabs.Option(id: $0.0, title: Text($0.1), symbol: KindGlyph.symbol($0.0)) }, selection: $kind, mark: mark)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Series o películas"))
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
        ViewThatFits(in: .horizontal) {
            tabs(titles: true)
            tabs(titles: options.allSatisfy { $0.symbol == nil })
        }
        // Sin sombra (Fernando, 4 nov 2026): se veía como un halo sucio alrededor de las letras.
        .animation(DS.Motion.fade, value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func tabs(titles: Bool) -> some View {
        HStack(spacing: DS.Space.s5) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = selection == option.id
                Button { selection = option.id } label: {
                    VStack(spacing: DS.Space.s1) {
                        // El ícono es siempre el mismo trazo (antes la elegida se rellenaba: «folder.fill» al lado de una flecha
                        // que no tiene relleno) y el ancho es el de la letra gruesa en las dos: al cambiar de pestaña no cambia
                        // ningún ícono ni se recorre nada (Fernando, 4 nov 2026, la 1774: «cambian los íconos»).
                        ZStack {
                            label(option, titles: titles, bold: true).hidden()
                            label(option, titles: titles, bold: on)
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
    private func label(_ option: Option, titles: Bool, bold: Bool) -> some View {
        HStack(spacing: DS.Space.s1) {
            if let symbol = option.symbol { Image(systemName: symbol).fontWeight(.semibold) }   // ds-exception: el trazo fijo del ícono de la pestaña
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
        .sensoryFeedback(.selection, trigger: selection)
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
        .sensoryFeedback(.selection, trigger: selection)
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
                .accessibilityAddTraits(on ? .isSelected : [])
                .transition(.asymmetric(
                    insertion: .scale(scale: DS.KindPill.enterScale).combined(with: .opacity)
                        .animation(motion.delay(Double(index) * DS.Motion.entranceStep)),
                    removal: .opacity.animation(DS.Motion.snap(reduceMotion) ?? DS.Motion.fade)))   // se apaga en su lugar, sin flotar fuera
            }
        }
        .padding(DS.Space.s1 / 2)
        .glassEffect(.regular.interactive(), in: Capsule())
        .fixedSize()
        .sensoryFeedback(.selection, trigger: kind)
        .sensoryFeedback(.impact(weight: .light), trigger: open)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Series o películas"))
        #if DEBUG
        .task { if Demo.isOn, ProcessInfo.processInfo.arguments.contains("-demo-kind-open") { open = true } }   // capturas: abierta
        .task {   // capturas en video: abre, elige Series, y regresa a Todo
            guard Demo.isOn, ProcessInfo.processInfo.arguments.contains("-demo-kind-cycle") else { return }
            for next in ["series", ""] {
                try? await Task.sleep(for: .seconds(2)); choose(kind)   // ds-exception: guion de capturas, solo en DEBUG
                try? await Task.sleep(for: .seconds(1.2)); choose(next)   // ds-exception: guion de capturas, solo en DEBUG
            }
        }
        #endif
    }

    /// Cerrada abre; abierta, el círculo se desliza a lo elegido y, un instante después, se encoge con él.
    private func choose(_ option: String) {
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
