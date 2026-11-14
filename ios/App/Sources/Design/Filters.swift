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
    /// En el renglón de controles de una lista (R1): un poco más compacta, para que con el nombre de lo elegido (KT1) quepa
    /// junto a ⊜, ＋ y elegir varios.
    var dense = false

    var body: some View {
        if menu {
            KindPill(kind: $kind, open: open ?? .constant(false), options: options)
        } else {
            // KT2 (Fernando, 13 nov 2026): el nombre de lo elegido va adentro de la pastilla, a la izquierda de los íconos.
            KindPill(kind: $kind, open: .constant(true), options: options, alwaysOpen: true, dense: dense)
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
    /// `badge`: cuántos hay (Descargas bajando), en un numerito sobre el ícono. Va aparte del nombre para que la barra no
    /// cambie de forma: con «Descargas · 3» no cabían los íconos y desaparecían (revisión del 11 nov).
    struct Option { let id: ID; let title: Text; var symbol: String? = nil; var badge: Int? = nil }
    let options: [Option]
    @Binding var selection: ID
    /// La rayita de la elegida (blanca; turquesa solo en Inicio).
    var mark: Color = DS.text
    /// Sin `ViewThatFits` (`adapts` en falso): dos o tres pestañas cortas que caben con su ícono hasta xxxLarge; con letra de
    /// accesibilidad, solo los íconos (con su nombre para VoiceOver). Para encabezados que se miden muy seguido, como el de
    /// una hoja que cambia de alto (Decide por mí): ahí medir cinco formas en cada pasada colgaba la app.
    var adapts = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// La rayita es una sola y viaja a la elegida (antes saltaba: se apagaba en una y se encendía en la otra).
    @Namespace private var markSpace

    var body: some View {
        // Si con la letra grande no caben los nombres, solo los íconos (cada uno con su nombre para VoiceOver): nunca se sale
        // de la pantalla (antes «T… Pe…» quedaba cortado por la orilla izquierda).
        // I13 · antes de quedarse solo con íconos, los nombres sin ícono: en un SE «Descargas · Mi media · Guardado» no cabía
        // con ícono y la Biblioteca se quedaba sin palabras.
        Group {
            if adapts { fitted } else { tabs(titles: !typeSize.isAccessibilitySize) }
        }
        // Sin sombra (Fernando, 4 nov 2026): se veía como un halo sucio alrededor de las letras.
        .animation(DS.Motion.fade, value: selection)
        .dsFeedback(.selection, trigger: selection)
    }

    private var fitted: some View {
        ViewThatFits(in: .horizontal) {
            tabs(titles: true)
            // R4: antes de soltar los íconos, más juntas (en el SE «Descargas · Mi media · Guardado» con ícono cabe así).
            tabs(titles: true, spacing: DS.Space.s3)
            // Con numerito (Descargas) no hay versión sin íconos: el numerito va en la esquina del ícono y nunca junto al
            // nombre, donde tapaba la «s» o ensanchaba la barra (R4, 11 nov). Sin numerito, los nombres solos (I13).
            if !hasBadge {
                tabs(titles: true, icons: false)
                tabs(titles: true, icons: false, spacing: DS.Space.s3)
            }
            if options.allSatisfy({ $0.symbol == nil }) {
                // Sin íconos a dónde bajar (Semana · Mes · Año · Siempre): se deslizan enteras en vez de cortarse en «Se…»
                // (revisión 2 del 11 nov, letra grande en el SE).
                ScrollView(.horizontal, showsIndicators: false) { tabs(titles: true, icons: false, spacing: DS.Space.s3) }
                .scrollClipDisabled()   // lo que crece al picarlo (o al dejarlo apretado) no se corta en la orilla del listón
            } else {
                tabs(titles: false)
            }
        }
    }

    private func tabs(titles: Bool, icons: Bool = true, spacing: CGFloat = DS.Space.s5) -> some View {
        HStack(spacing: spacing) {
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
                        .accessibilityValue(option.badge.flatMap { $0 > 0 ? Text("\($0) bajando") : nil } ?? Text(verbatim: ""))
                        .font(DS.TextRecipe.cardTitle.font)
                        .foregroundStyle(on ? DS.text : DS.textMuted)
                        ZStack {
                            Capsule().fill(.clear)
                            // Con «Reducir movimiento» no viaja: se enciende en la nueva.
                            if on { Capsule().fill(mark).matchedGeometryEffect(id: reduceMotion ? AnyHashable(option.id) : AnyHashable("mark"), in: markSpace) }
                        }
                        .frame(width: DS.Filter.tabMark, height: DS.Filter.tabMarkHeight)
                    }
                    .padding(.vertical, DS.Space.s1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// Alguna pestaña lleva numerito (aunque hoy valga cero): así la barra elige la misma forma con y sin él.
    private var hasBadge: Bool { options.contains { $0.badge != nil && $0.symbol != nil } }

    /// El numerito de cuántos hay: en la esquina de arriba del ícono, sin ocupar lugar en el renglón (la barra no cambia de
    /// forma al aparecer o irse). Con la letra más grande se queda en su tamaño de insignia para no tapar el ícono entero.
    private func countBadge(_ count: Int) -> some View {
        Text(verbatim: "\(count)").recipe(.badge, color: DS.onFresh).monospacedDigit()
            .padding(.horizontal, DS.Space.s1)
            .background(DS.fresh, in: Capsule())
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .scaleEffect(DS.Filter.tabBadgeScale)   // chico: tapa solo la esquina del ícono, como en iOS
            .fixedSize()
            .offset(x: DS.Space.s1, y: -DS.Space.s2)
    }

    /// El ícono con el mismo trazo siempre; solo el nombre cambia de peso.
    private func label(_ option: Option, titles: Bool, icons: Bool, bold: Bool) -> some View {
        HStack(spacing: DS.Space.s1) {
            // El numerito va siempre sobre la esquina del ícono (sobre el nombre tapaba la «s» de «Descargas»).
            let badge = option.badge.flatMap { $0 > 0 ? $0 : nil }
            if icons, let symbol = option.symbol {
                Image(systemName: symbol).fontWeight(.semibold)   // ds-exception: el trazo fijo del ícono de la pestaña
                    .overlay(alignment: .topTrailing) { if let badge { countBadge(badge) } }
            }
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
    /// `badge`: cuántos hay (Descargas bajando), en un numerito sobre el ícono. Va aparte del nombre para que la barra no
    /// cambie de forma: con «Descargas · 3» no cabían los íconos y desaparecían (revisión del 11 nov).
    struct Option { let id: ID; let title: Text; var symbol: String? = nil; var badge: Int? = nil }
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

/// SX1 (Fernando, 9 nov): el selector de Inicio es solo el ícono de lo que ves. Al tocarlo, la misma pastilla crece desde
/// donde está con un resorte que se asienta sin pasarse (`DS.Motion.grow`; los íconos un poco más grandes, para tocarlos
/// fácil) mientras la cápsula de al lado ya se hizo a un lado (`DS.Motion.fold`, más rápido): lo que crece no choca. Las
/// otras dos opciones nacen junto a lo que ves y entran una tras otra. Al elegir, el círculo blanco viaja al nuevo con el
/// mismo resorte y la pastilla se recoge con él, más rápido de lo que abrió; las que sobran se apagan antes de que se
/// cierre. Todo se puede interrumpir (otro toque a medio camino retoma desde donde va). Dejar el dedo encima dice su
/// nombre; VoiceOver lo lee siempre. Con «Reducir movimiento», solo fundidos. Fernando, 13 nov 2026: «rebota de inmediato
/// en los botones de arriba a la derecha… que la animación sea más suave, que tenga un poquito de física».
struct KindPill: View {
    @Binding var kind: String
    @Binding var open: Bool
    let options: [(String, LocalizedStringKey)]
    /// I8 · fuera de Inicio la pastilla está siempre abierta: tocar un ícono lo elige y nada se recoge.
    var alwaysOpen = false
    var dense = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var mark
    private var cell: CGFloat { open ? (dense ? DS.KindPill.dense : DS.KindPill.open) : DS.KindPill.closed }
    /// El cierre que espera a que el círculo llegue: otro toque lo cancela (nunca se cierra encima de lo que acabas de hacer).
    @State private var folding: Task<Void, Never>?
    /// Recién elegido: las otras dos se van y en su lugar se lee el nombre de lo que elegiste, un momento, antes de recogerse
    /// (Fernando, 13 nov 2026: «si ves el ícono no sabes qué estás escogiendo»).
    @State private var naming = false

    var body: some View {
        let shown = open && !naming ? options : options.filter { $0.0 == kind }
        let picked = options.firstIndex { $0.0 == kind } ?? 0
        let spacing = open ? DS.Space.s1 : 0
        HStack(spacing: spacing) {
            nameSlot(picked: picked, spacing: spacing)
            ForEach(Array(shown.enumerated()), id: \.element.0) { _, option in
                let on = kind == option.0
                let index = options.firstIndex { $0.0 == option.0 } ?? 0
                Button { choose(option.0) } label: {
                    HStack(spacing: 0) {
                        Image(systemName: KindGlyph.symbol(option.0)).symbolVariant(.fill)   // siempre relleno: el ícono no cambia de dibujo al cerrar
                            .font(DS.TextRecipe.section.font)
                            .scaleEffect(option.0 == "series" ? DS.KindPill.seriesOptical : 1)   // el de series es más ancho: se ve del mismo peso que los otros
                            // el mismo tamaño abierto: así el círculo cubre hasta el ícono más ancho (series)
                            .frame(width: cell, height: cell)
                    }
                    .foregroundStyle(on && open ? DS.bg : DS.text)
                    .matchedGeometryEffect(id: option.0, in: mark)   // dónde va el círculo cuando es lo elegido
                    .contentShape(Capsule())
                }
                .buttonStyle(KindPillPress())
                .help(Text(option.1))
                .accessibilityLabel(open ? Text(option.1) : Text(option.1) + Text(". Cambiar entre todo, películas y series"))
                .accessibilityIdentifier("kind-\(option.0.isEmpty ? "all" : option.0)")
                .accessibilityAddTraits(on ? .isSelected : [])
                .transition(arrival(index: index, picked: picked))
            }
        }
        // Un solo círculo blanco que viaja al elegido (antes eran dos que se cruzaban apagándose: a medio camino se veía gris).
        // Con «Reducir movimiento» no viaja: se apaga en uno y se enciende en el otro.
        .background {
            if open {
                Capsule().fill(DS.text)   // el círculo de lo elegido (el nombre va aparte, a su izquierda: KT2)
                    .padding(DS.KindPill.markInset)   // el círculo cabe holgado en su lugar: nunca toca la orilla de la pastilla
                    .matchedGeometryEffect(id: kind, in: mark, isSource: false)
                    .id(reduceMotion ? kind : "")
                    .transition(.opacity.animation(DS.Motion.fadeQuick))
            }
        }
        .padding(DS.Space.s1 / 2)
        .clipShape(Capsule())   // ni a medio viaje ni con el resorte: el círculo no se sale de la pastilla
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
        .onDisappear { folding?.cancel() }
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

    /// KT2 (Fernando, 13 nov 2026: «que diga adentro de la pastilla película, todo, serie… que sea a la izquierda del
    /// punto», y que con Series el ícono no se vaya hasta la izquierda): el nombre de lo elegido, adentro de la pastilla y a la
    /// izquierda de los íconos, en toda la app.
    /// - Siempre abierta: su lugar está apartado para el nombre más largo, así que al elegir nada se mueve; el nombre nuevo se
    ///   funde sobre el anterior.
    /// - Inicio, recién elegido: las otras opciones se van y el nombre ocupa su lugar a la izquierda de lo elegido, con al menos
    ///   el ancho de lo que había a su izquierda: el círculo se queda donde lo tocaste (con Series, ya no brinca hasta la
    ///   orilla) y después la pastilla se recoge con él.
    @ViewBuilder private func nameSlot(picked: Int, spacing: CGFloat) -> some View {
        let names = Self.names.filter { name in options.contains { $0.0 == name.0 } }
        let chosen = names.first { $0.0 == kind }?.1
        if alwaysOpen {
            ZStack(alignment: .trailing) {
                ForEach(names, id: \.0) { Text($0.1).hidden() }
                if let chosen {
                    Text(chosen).id(kind).transition(.opacity.animation(DS.Motion.fade))
                }
            }
            .modifier(KindName())
        } else if open, naming, let chosen {
            let left = max(0, CGFloat(picked) * (cell + spacing) - spacing - DS.KindPill.nameInset)
            Text(chosen)
                .frame(minWidth: left, alignment: .trailing)
                .modifier(KindName())
                .transition(.asymmetric(
                    insertion: .scale(scale: DS.KindPill.enterScale, anchor: .trailing).combined(with: .opacity)
                        .animation(DS.Motion.fade),
                    removal: .opacity.animation(DS.Motion.fadeQuick)))
        }
    }

    /// Los nombres sin cifras («Películas 12» es para VoiceOver en Buscar; adentro de la pastilla solo el nombre).
    private static let names: [(String, LocalizedStringKey)] = [("", "Todo"), ("movie", "Películas"), ("series", "Series")]

    /// Las que llegan nacen un poco más chicas del lado de lo que ves (no de la nada ni del centro) y entran una tras otra, la
    /// más cercana primero, con el mismo resorte que abre. Las que se van solo se apagan, rápido: ya no están cuando la
    /// pastilla termina de recogerse, así no se enciman con la que se queda.
    private func arrival(index: Int, picked: Int) -> AnyTransition {
        // Con «Reducir movimiento» la pastilla cambia de tamaño de una vez: lo que llega se enciende con un fundido y lo que se
        // va se quita en el acto (apagándose quedaba encima de la cápsula, que ya regresó).
        guard let grow = DS.Motion.grow(reduceMotion)?.speed(DS.KindPill.pace) else { return .asymmetric(insertion: .opacity.animation(DS.Motion.fade), removal: .identity) }
        let order = max(0, abs(index - picked) - 1)
        return .asymmetric(
            insertion: .scale(scale: DS.KindPill.enterScale, anchor: index < picked ? .trailing : .leading).combined(with: .opacity)
                .animation(grow.delay(Double(order) * DS.KindPill.stagger)),
            removal: .opacity.animation(DS.Motion.fadeQuick))
    }

    /// Cerrada abre; abierta, el círculo viaja a lo elegido y, cuando llega, la pastilla se recoge con él.
    private func choose(_ option: String) {
        folding?.cancel()
        // Más suave (Fernando, 13 nov 2026: «que le hagas un poquito más suave la transición»): las mismas curvas, más pausadas.
        let grow = DS.Motion.grow(reduceMotion)?.speed(DS.KindPill.pace), fold = DS.Motion.fold(reduceMotion)?.speed(DS.KindPill.pace)
        // Con «Reducir movimiento» el círculo no viaja: se apaga en uno y se enciende en el otro.
        let pick = grow ?? DS.Motion.fade
        if alwaysOpen { withAnimation(pick) { kind = option }; return }
        guard open else { withAnimation(grow) { naming = false; open = true }; return }
        guard option != kind else { withAnimation(fold) { open = false; naming = false }; return }
        withAnimation(pick) { kind = option; naming = true }
        folding = Task {
            try? await Task.sleep(for: DS.KindPill.settle)
            guard !Task.isCancelled else { return }
            withAnimation(fold) { open = false; naming = false }
        }
    }
}

/// La letra del nombre de lo elegido adentro de la pastilla de tipo (KT2): la misma en Inicio y en las demás pantallas.
private struct KindName: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.TextRecipe.label.font).fontWeight(.semibold)   // ds-exception: el nombre de lo elegido, como la elegida del selector
            .foregroundStyle(DS.text)
            .lineLimit(1).fixedSize()
            .padding(.leading, DS.KindPill.nameInset)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("kind-name")
    }
}

/// «Filtros» (Fernando, 13 nov 2026: un solo botón en lugar de cuatro íconos): el mismo círculo de vidrio y tamaño que el
/// selector de tipo (`KindPill`), para que el renglón se lea como una familia. Con algo puesto, el círculo se llena de su
/// tinte (`tint`) creciendo con un resorte corto, lleva cuántos hay en un numerito y el teléfono da un toque ligero; el
/// símbolo salta cuando cambia la cuenta. Abre la hoja de filtros. Con «Reducir movimiento», el relleno solo se funde.
struct DSFiltersButton: View {
    /// Cuántos filtros hay puestos (0: ninguno).
    let count: Int
    var tint: Color = DS.DecideLive.refine
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let on = count > 0
        Button(action: action) {
            Image(systemName: DS.Symbol.refine).font(DS.TextRecipe.section.font)
                .foregroundStyle(on ? DS.DecideLive.onTint : DS.text)
                .symbolEffect(.bounce, options: .nonRepeating, value: reduceMotion ? 0 : count)
                .frame(width: DS.KindPill.open, height: DS.KindPill.open)
                .background {
                    Circle().fill(tint)
                        .scaleEffect(on || reduceMotion ? 1 : DS.DecideLive.fillFrom)
                        .opacity(on ? 1 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    if on {
                        Text(verbatim: "\(count)").recipe(.badge, color: DS.bg).monospacedDigit()
                            .padding(.horizontal, DS.Space.s1)
                            .background(DS.text, in: Capsule())
                            .fixedSize()
                            .offset(x: DS.Space.s1, y: -DS.Space.s1)
                            .contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(DS.Motion.grow(reduceMotion) ?? DS.Motion.fade, value: on)
                .animation(DS.Motion.fade, value: count)
                .contentShape(Circle())
        }
        .buttonStyle(KindPillPress())
        .padding(DS.Space.s1 / 2)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // círculo de tamaño fijo, como los del tipo
        .accessibilityShowsLargeContentViewer()
        .glassEffect(.regular.interactive(), in: Circle())
        .fixedSize()
        .dsFeedback(.impact(weight: .light), trigger: on)
        .accessibilityLabel(Text("Filtros"))
        .accessibilityValue(on ? Text("\(count) puestos") : Text("Sin filtro"))
    }
}

/// Al apretar, el ícono se hunde tantito, en cuanto lo tocas.
private struct KindPillPress: ButtonStyle {   // ds-exception: el hundido del segmento; la pastilla es vidrio nativo
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? DS.KindPill.pressed : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}
