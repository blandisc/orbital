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
    static var centered: Bool { WindowMetrics.column.width >= DS.Mac.centeredTabsFrom }

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
                Label("Buscar", systemImage: "magnifyingglass").recipe(.label, color: tabs.current == 2 ? DS.bg : DS.text)
                    .macTabLabel(compact: compact)
                    .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
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
                .recipe(.label, color: on ? DS.bg : DS.textMuted)
                .macTabLabel(compact: compact)
                .padding(.horizontal, DS.Space.s4).padding(.vertical, DS.Space.s2)
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
    /// En la Mac, la barra de navegación de una pantalla de arriba (Explorar, Biblioteca, Buscar): el logo y «Buscar» a la
    /// izquierda y las pestañas al centro, en el mismo renglón que sus botones, sin el título grande (las pestañas ya dicen dónde estás). En iPhone y
    /// iPad, nada.
    @ViewBuilder func macTopBar() -> some View {
        if ThisDevice.isMac {
            toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: DS.Space.s6) {
                            AppMark(small: true, reportsFrame: false)
                            MacSearchChip(compact: !MacTabStrip.centered)
                            // En una ventana angosta la cápsula va aquí, solo con íconos: al centro se encimaba.
                            if !MacTabStrip.centered { MacTabStrip(compact: true) }
                        }
                        .fixedSize()   // la barra le ofrece poco ancho y los nombres se recortaban hasta desaparecer
                    }
                    .sharedBackgroundVisibility(.hidden)
                    // RN2: las pestañas en su cápsula, al centro de la barra (como la tele).
                    ToolbarItem(placement: .principal) { if MacTabStrip.centered { MacTabStrip() } }
                        .sharedBackgroundVisibility(.hidden)
                }
                .macTopShade()
        } else {
            self
        }
    }
}

/// iPhone: la barra de abajo. iPad: la barra de arriba que se abre como barra lateral. Mac: solo pestañas (y escondidas: las
/// dibuja `MacTabStrip` en el renglón del logo); la barra lateral en la Mac salía vacía y tapaba el contenido (16 nov 2026).
struct TabStyle: ViewModifier {
    func body(content: Content) -> some View {
        if ThisDevice.isMac { content.tabViewStyle(.tabBarOnly) } else { content.tabViewStyle(.sidebarAdaptable) }
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
    @ViewBuilder func macHidesTabBar() -> some View {
        if ThisDevice.isMac { toolbarVisibility(.hidden, for: .tabBar) } else { self }
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

/// MB1 (Fernando, 16 nov 2026): en la Mac, las partes de una pantalla (Descargas · Mi media · Guardado) en una columna a la
/// izquierda, como Música o Fotos, en vez de una segunda fila de pestañas que se sentía puesta a la fuerza. La elegida con su
/// relleno; el numerito de lo que baja a la derecha.
struct MacSidebar<ID: Hashable>: View {
    struct Option { let id: ID; let title: Text; let symbol: String; var badge: Int = 0 }
    let options: [Option]
    @Binding var selection: ID

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            ForEach(options, id: \.id) { option in
                let on = option.id == selection
                Button { selection = option.id } label: {
                    HStack(spacing: DS.Space.s3) {
                        Image(systemName: option.symbol).font(DS.TextRecipe.cardTitle.font)
                            .foregroundStyle(on ? DS.text : DS.textMuted).frame(width: DS.SettingsLook.rowIcon)
                        option.title.bold(on).recipe(.cardTitle, color: on ? DS.text : DS.textMuted)
                        Spacer(minLength: 0)
                        if option.badge > 0 { Text(verbatim: "\(option.badge)").recipe(.badge, color: DS.textMuted).monospacedDigit() }
                    }
                    .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s3)
                    .dsCard(fill: on ? DS.surfaceRaised : .clear)
                    .contentShape(RoundedRectangle(cornerRadius: DSCardLevel.row.radius, style: .continuous))
                }
                .buttonStyle(.plain)
                .pointerHover(.highlight)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s3).padding(.top, DS.Space.s3)
        .frame(width: DS.Mac.sidebarWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: DS.Stroke.hairline) }
        .dsFeedback(.selection, trigger: selection)
    }
}

/// MS1 (Fernando, 16 nov 2026): en la Mac, Buscar trae su campo grande al centro en vez de la rayita de la barra del sistema.
struct MacSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "magnifyingglass").font(DS.TextRecipe.title.font).foregroundStyle(DS.textMuted)
            TextField("Películas y series", text: $text)
                .textFieldStyle(.plain).font(DS.TextRecipe.title.font).foregroundStyle(DS.text)
                .focused(focused).submitLabel(.search).autocorrectionDisabled()
            if !text.isEmpty {
                DSIconButton(symbol: "xmark", label: "Borrar la búsqueda", size: .regular) { text = "" }
            }
        }
        .padding(.horizontal, DS.Space.s6)
        .frame(maxWidth: DS.Mac.searchFieldWidth, minHeight: DS.Mac.searchFieldHeight)
        .background(DS.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(focused.wrappedValue ? DS.accent : DS.hairline, lineWidth: focused.wrappedValue ? DS.Stroke.selected : DS.Stroke.hairline))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mac-search-field")
    }
}
