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
            ], selection: Binding(get: { tabs.current }, set: { tabs.select($0) }), mark: DS.eyebrow, adapts: false)
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
                // Sobre el mosaico de Explorar las pestañas se perdían entre los pósters: una sombra bajo la barra.
                .overlay(alignment: .top) {
                    ArtVeil(kind: .top, strength: .deep)
                        .frame(height: DS.Mac.topScrim).ignoresSafeArea(edges: .top).allowsHitTesting(false)
                }
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
