import SwiftUI

/// Las pestañas de la Mac en el renglón del logo (MAC-A, Fernando, 16 nov 2026: «el dock de Inicio, Explorar, Biblioteca crea
/// como otro carril artificial arriba de orbital y el selector»). En la Mac no hay barra de pestañas del sistema ni barra
/// lateral (la lateral salía vacía, tapaba el contenido y ahí tronaba): cada pantalla de arriba lleva estas pestañas en su
/// propio renglón, junto al logo, como la barra de la tele. iPhone y iPad no cambian: siguen con la barra del sistema.
struct MacTabs: Equatable {
    let current: Int
    let select: (Int) -> Void
    /// Lo que baja (descargas y pedidos a la nube): el numerito de Biblioteca.
    let libraryBadge: Int
    /// RN2: «Buscar» junto al logo pone el cursor en el campo (lo hace la raíz: la pieza no toca el estado de la app).
    var focusSearch: () -> Void = {}
    /// Sin la acción (cambia en cada pasada): así la tira solo se repinta si cambia la pestaña o el numerito.
    static func == (a: MacTabs, b: MacTabs) -> Bool { a.current == b.current && a.libraryBadge == b.libraryBadge }
}

extension EnvironmentValues {
    /// Solo existe en la Mac (lo pone `RootView`); en iPhone y iPad es nil y nadie dibuja la tira.
    @Entry var macTabs: MacTabs?
}

/// RN2 (Fernando, 16 nov 2026: «hazlo de acuerdo a tus sugerencias»): Inicio · Explorar · Biblioteca en una cápsula al
/// centro, como la barra de la tele, con la elegida en crema (`DS.paper`). Buscar va aparte, junto al logo (`MacSearchChip`),
/// como el «Buscar» de la tele.
struct MacTabStrip: View {
    /// En una ventana angosta va junto al logo y solo con íconos (el nombre lo dice VoiceOver y la ayuda del puntero).
    var compact = false
    @Environment(\.macTabs) private var tabs

    /// La ventana alcanza para la cápsula al centro sin encimarse con el logo, «Buscar» y lo de la derecha.
    /// En el iPad (C1) la letra no crece como en la Mac, pero «Buscar» y la cápsula son más anchos que el umbral de la Mac: a
    /// 1032 pt (iPad de pie) se encimaban; ahí la cápsula va junto al logo.
    static var centered: Bool { WindowMetrics.column.width >= (ThisDevice.isMac ? DS.Mac.centeredTabsFrom : DS.HomeBoard.padCenteredTabsFrom) }

    var body: some View {
        if let tabs {
            // En el orden del menú «Ir» (⌘1 Inicio, ⌘2 Explorar, ⌘3 Biblioteca).
            HStack(spacing: DS.Space.s1) {
                MacTabButton(title: Text("Inicio"), symbol: "house", on: tabs.current == 0, compact: compact) { MacTabSwitch.go(tabs, 0) }
                MacTabButton(title: Text("Explorar"), symbol: "sparkles", on: tabs.current == 1, compact: compact) { MacTabSwitch.go(tabs, 1) }
                MacTabButton(title: Text("Biblioteca"), symbol: "rectangle.stack", on: tabs.current == 3, badge: tabs.libraryBadge, compact: compact) { MacTabSwitch.go(tabs, 3) }
            }
            .padding(DS.Space.s1)
            .background(Capsule().fill(DS.surfaceRaised))
            .overlay(Capsule().strokeBorder(DS.hairline, lineWidth: DS.Size.hairline))
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mac-tabs")
        }
    }
}

/// «Buscar» junto al logo en la Mac (RN2): una cápsula con la lupa que abre Buscar y pone el cursor en su campo (⌘F también).
struct MacSearchChip: View {
    var compact = false
    @Environment(\.macTabs) private var tabs

    var body: some View {
        if let tabs {
            Button {
                MacTabSwitch.go(tabs, 2)
                tabs.focusSearch()
            } label: {
                Label("Buscar", systemImage: "magnifyingglass").recipe(DS.Mac.topBarText, color: tabs.current == 2 ? DS.bg : DS.text)
                    .macTabLabel(compact: compact)
                    // Tan alto como la cápsula de las pestañas (su aire de adentro más el de su orilla) y más ancho: antes se veía
                    // más chico que ellas (Fernando, 22 nov 2026: «buscar lo haría un poquito más grande»).
                    // DK (22 nov 2026: «el dock de arriba un poquito más grande»): crece junto con las pestañas y tu foto.
                    .padding(.horizontal, compact ? DS.Space.s6 : DS.Space.s8).padding(.vertical, DS.Mac.topBarPadV + DS.Space.s1)
                    .background(Capsule().fill(tabs.current == 2 ? DS.text : DS.surfaceRaised))
                    .overlay(Capsule().strokeBorder(DS.hairline, lineWidth: DS.Size.hairline))
            }
            .buttonStyle(.plain)
            .help(Text("Buscar"))
            .fixedSize()
            .accessibilityIdentifier("mac-search-chip")
        }
    }
}

extension View {
    /// El nombre y el ícono (en la barra del sistema el nombre se quitaba); en una ventana angosta, solo el ícono, con su
    /// nombre en la ayuda del puntero.
    @ViewBuilder fileprivate func macTabLabel(compact: Bool) -> some View {
        if compact { labelStyle(.iconOnly) } else { labelStyle(.titleAndIcon) }
    }
}

/// Una pestaña de la cápsula de la Mac: la elegida, llena con la letra al revés (como el foco de la tele).
private struct MacTabButton: View {
    let title: Text
    let symbol: String
    let on: Bool
    var badge = 0
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label { title } icon: { Image(systemName: symbol) }
                .recipe(DS.Mac.topBarText, color: on ? DS.bg : DS.textMuted)
                .macTabLabel(compact: compact)
                .padding(.horizontal, DS.Space.s6).padding(.vertical, DS.Mac.topBarPadV)
                // La elegida, llena del color del texto con la letra del fondo: crema y oscura en modo oscuro (el foco de la tele), oscura
                // y clara en modo claro (crema sobre la cápsula casi blanca no se distinguía).
                .background { if on { Capsule().fill(DS.text) } }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 { Circle().fill(DS.accent).frame(width: DS.Mac.tabBadge, height: DS.Mac.tabBadge) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(badge > 0 ? Text("\(badge) bajando") : Text(verbatim: ""))
    }
}

/// El cambio de pestaña en la Mac, al momento (MC1, Fernando, 16 nov 2026: con el fundido se veían las dos pantallas
/// encimadas un instante y se sentía lenta). El fundido lo pone UIKit al cambiar de pestaña: se apagan sus animaciones mientras.
enum MacTabSwitch {
    @MainActor static func go(_ tabs: MacTabs, _ id: Int) {
        guard tabs.current != id else { return }
        UIView.setAnimationsEnabled(false)
        var instant = Transaction(); instant.disablesAnimations = true
        withTransaction(instant) { tabs.select(id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + DS.Mac.tabSwitchQuiet) { UIView.setAnimationsEnabled(true) }
    }
}

extension View {
    /// En la Mac, el renglón de arriba de una pantalla de arriba (Explorar, Biblioteca, Buscar), dibujado por la pantalla como
    /// en Inicio (`HomeHeader`): el logo y «Buscar» a la izquierda, las pestañas al centro y `trailing` (sus botones y tu perfil)
    /// a la derecha. Antes iban en la barra del sistema (`.toolbar`) y UIKit las soltaba: al entrar a Buscar, al regresar de una
    /// ficha o al volver a Explorar la pantalla se quedaba sin pestañas o sin logo; además, lo de la barra a veces se armaba sin
    /// el entorno de la app (17 nov 2026). Regla «Las pestañas de la Mac no dependen de la barra del sistema». La barra del
    /// sistema se esconde solo aquí, en la pantalla de arriba: las de adentro (la ficha) traen la suya, con «‹». En iPhone y
    /// iPad, nada.
    @ViewBuilder func macOwnTopRow(@ViewBuilder trailing: () -> some View) -> some View {
        if TopRow.tabsInLogoRow {   // C1: también el iPad con espacio
            toolbarVisibility(.hidden, for: .navigationBar)
                .macTopShade()
                .safeAreaBar(edge: .top) { MacTopRow(trailing: trailing()) }
        } else {
            self
        }
    }
}

/// El renglón de `macOwnTopRow`, con las mismas medidas que el de Inicio: al cambiar de pestaña nada brinca.
struct MacTopRow<Trailing: View>: View {
    let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            // Solo el logo de Inicio dice dónde está: dos que lo dijeran se pelean y la app se traba redibujando.
            AppMark(small: true, reportsFrame: false)
            MacSearchChip(compact: !MacTabStrip.centered).padding(.leading, DS.Space.s6)
            // En una ventana angosta la cápsula va aquí, solo con íconos: al centro se encimaba.
            if !MacTabStrip.centered { MacTabStrip(compact: true).padding(.leading, DS.Space.s2) }
            Spacer(minLength: DS.Space.s2)
            trailing
                .buttonStyle(.plain).foregroundStyle(DS.text)
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s2)
                .glassEffect(.regular.interactive(), in: Capsule())
                .macPillBase(Capsule())
        }
        // RN2: las pestañas en su cápsula, al centro del renglón (como la tele).
        .overlay { if MacTabStrip.centered { MacTabStrip() } }
        .padding(.horizontal, DS.Space.gutter)
        .padding(.bottom, DS.Space.s1)
        .containerRelativeFrame(.horizontal)   // ds-exception: en la barra de arriba (safeAreaBar) el panel no cuenta, como en Inicio
    }
}

/// iPhone: la barra de abajo. iPad: la barra de arriba que se abre como barra lateral. Mac: solo pestañas (y escondidas: las
/// dibuja `MacTabStrip` en el renglón del logo); la barra lateral en la Mac salía vacía y tapaba el contenido (16 nov 2026).
struct TabStyle: ViewModifier {
    func body(content: Content) -> some View {
        // C1: el iPad con espacio, como la Mac (escondida, la barra adaptable del iPad seguía tomando los toques de la franja de arriba).
        if TopRow.tabsInLogoRow { content.tabViewStyle(.tabBarOnly) } else { content.tabViewStyle(.sidebarAdaptable) }
    }
}

extension View {
    /// En la Mac, una sombra bajo la barra de arriba: sobre el mosaico de Explorar o la portada de Inicio las pestañas se
    /// perdían entre los pósters. En iPhone y iPad, nada (ahí la barra del sistema ya tiene su desvanecido).
    @ViewBuilder func macTopShade() -> some View {
        if ThisDevice.isMac {
            overlay(alignment: .top) {
                ArtVeil(kind: .top, strength: .deep)
                    .frame(height: DS.Mac.topScrim).ignoresSafeArea(edges: .top).allowsHitTesting(false)
            }
        } else {
            self
        }
    }

    /// En la Mac la barra de pestañas del sistema no se ve (las pestañas van en el renglón del logo, `MacTabStrip`).
    /// C1: también en el iPad con espacio (`TopRow`), con sus pestañas en el renglón del logo.
    func macHidesTabBar() -> some View {
        toolbarVisibility(TopRow.tabsInLogoRow ? .hidden : .automatic, for: .tabBar)
    }

    /// La escala de la Mac, una sola vez para toda la app (en `RootView`): lo que no trae su propia letra arranca con el cuerpo
    /// de la Mac (`DS.styled(.body)`), la letra del sistema (formularios, menús, botones nativos) crece como la de `DS.styled`
    /// y los controles sin tamaño propio van en `DS.Mac.controlDefault`. macOS dibuja la app al 77 % y salían diminutos (MAC-A;
    /// sistema de tamaños, 16 nov 2026). En iPhone y iPad, nada: cada quien con su Dynamic Type.
    @ViewBuilder func macDefaults() -> some View {
        if ThisDevice.isMac {
            font(DS.styled(.body)).dynamicTypeSize(DS.Mac.systemType)
                .controlSize(DS.Mac.controlDefault)   // ds-exception: la escala de la Mac se pone aquí y solo aquí
        } else { self }
    }

}

/// MS1 (Fernando, 16 nov 2026): en la Mac, Buscar trae su campo grande al centro en vez de la rayita de la barra del sistema.
struct MacSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: "magnifyingglass").font(DS.TextRecipe.title.font).foregroundStyle(DS.textMuted)
            TextField("Películas y series", text: $text)
                .textFieldStyle(.plain).font(DS.TextRecipe.title.font).foregroundStyle(DS.text)
                .focused(focused).submitLabel(.search).autocorrectionDisabled()
            if !text.isEmpty {
                DSIconButton(symbol: DS.Symbol.remove, label: "Borrar la búsqueda", size: .regular) { text = "" }
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .frame(maxWidth: .infinity, minHeight: DS.Mac.searchFieldHeight)   // BU-A: de orilla a orilla, alineado con la cuadrícula
        .background(DS.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(focused.wrappedValue ? DS.accent : DS.hairline, lineWidth: focused.wrappedValue ? DS.Stroke.selected : DS.Stroke.hairline))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mac-search-field")
    }
}
