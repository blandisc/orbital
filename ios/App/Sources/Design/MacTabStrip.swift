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
    /// Sin la acción (cambia en cada pasada): así la tira solo se repinta si cambia la pestaña o el numerito.
    static func == (a: MacTabs, b: MacTabs) -> Bool { a.current == b.current && a.libraryBadge == b.libraryBadge }
}

extension EnvironmentValues {
    /// Solo existe en la Mac (lo pone `RootView`); en iPhone y iPad es nil y nadie dibuja la tira.
    @Entry var macTabs: MacTabs?
}

/// Inicio · Explorar · Biblioteca · Buscar con la misma pieza de pestañas de texto de toda la app (`DSTextTabs`).
struct MacTabStrip: View {
    @Environment(\.macTabs) private var tabs

    var body: some View {
        if let tabs {
            DSTextTabs(options: [
                .init(id: 0, title: Text("Inicio"), symbol: "house"),
                .init(id: 1, title: Text("Explorar"), symbol: "sparkles"),
                .init(id: 3, title: Text("Biblioteca"), symbol: "rectangle.stack", badge: tabs.libraryBadge),
                .init(id: 2, title: Text("Buscar"), symbol: "magnifyingglass"),
            ], selection: Binding(get: { tabs.current }, set: { id in
                // MC1 (Fernando, 16 nov 2026): la pestaña cambia al momento, como en Safari; con el fundido se veían las dos
                // pantallas encimadas un instante y se sentía lenta.
                // El fundido lo pone UIKit al cambiar de pestaña (no SwiftUI): se apagan sus animaciones mientras cambia.
                UIView.setAnimationsEnabled(false)
                var instant = Transaction(); instant.disablesAnimations = true
                withTransaction(instant) { tabs.select(id) }
                DispatchQueue.main.asyncAfter(deadline: .now() + DS.Mac.tabSwitchQuiet) { UIView.setAnimationsEnabled(true) }
            }), mark: DS.eyebrow, adapts: false)
            .accessibilityIdentifier("mac-tabs")
        }
    }
}

extension View {
    /// En la Mac, la barra de navegación de una pantalla de arriba (Explorar, Biblioteca, Buscar): el logo y las pestañas a la
    /// izquierda, en el mismo renglón que sus botones, sin el título grande (las pestañas ya dicen dónde estás). En iPhone y
    /// iPad, nada.
    @ViewBuilder func macTopBar() -> some View {
        if ThisDevice.isMac {
            toolbar(removing: .title)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: DS.Space.s6) { AppMark(small: true, reportsFrame: false); MacTabStrip() }
                            .fixedSize()   // la barra le ofrece poco ancho y los nombres se recortaban hasta desaparecer
                    }
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

    /// En la Mac, lo que no trae su propia letra (los botones del sistema como «Ver», textos sin receta) arranca con el cuerpo
    /// de la Mac (`DS.styled(.body)`) y los controles en tamaño grande: macOS los dibuja al 77 % y salían diminutos (MAC-A).
    @ViewBuilder func macDefaults() -> some View {
        if ThisDevice.isMac { font(DS.styled(.body)).controlSize(.large) } else { self }
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
