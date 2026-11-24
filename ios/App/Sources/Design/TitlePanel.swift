import SwiftUI
import OrbitalCore

// MARK: La ficha en un panel lateral (iPad, Mac)

/// Abrir una ficha en el panel de la derecha, sobre lo que estabas viendo (como el iPhone, que la empuja a pantalla completa).
/// Solo existe con ancho regular (iPad, Mac): lo pone `MainTabs`. En el iPhone es `nil` y todo navega como siempre.
/// Siempre igual a otro: la raíz lo arma en cada pasada (cambiar de pestaña, regresar de una ficha) y, como el cierre solo
/// toca su estado guardado, cambiarlo por uno nuevo no cambia nada; sin esto, todo lo que lo lee se volvía a pintar.
struct TitlePanelOpener: Equatable {
    /// La ficha y, si se sabe, el marco del póster que se tocó (en la ventana): de ahí sale el zoom hacia el panel. La acción
    /// vive en `AppUI.titlePanel` (V9, como `RemoteOpener`): con el cierre dentro, cada pasada de la raíz volvía a pintar cada
    /// póster que lee el entorno.
    /// De qué ventana es (su acción, en `AppUI.titlePanels`; se llama desde `Screens/EnvironmentActions.swift`).
    let window: Int
}

extension EnvironmentValues {
    @Entry var titlePanel: TitlePanelOpener? = nil
    /// Lo que se ve dentro del panel de la derecha (FI-B): la ficha va en su versión de una columna (`TitleView.sizeClass`).
    @Entry var titleInPanel = false
}

/// El enlace a una ficha del catálogo: con panel (iPad, Mac), la abre a la derecha; sin él (iPhone), navega como siempre.
struct TitleNavigationLink<Label: View>: View {
    let route: TitleRoute
    @ViewBuilder var label: () -> Label
    @Environment(\.titlePanel) private var panel
    @Environment(\.titleZoom) private var zoom
    /// Dónde está el póster en la ventana: el zoom hacia el panel sale de aquí. En una caja que SwiftUI no observa: cambia en
    /// cada cuadro al desplazar y, guardado como estado, volvía a pintar cada póster en cada cuadro (auditoría, A3).
    @State private var frame = FrameBox()
    /// El nombre de este enlace en el zoom (`TitleZoomID`): viaja en la navegación, así la ficha sale de este póster aunque el
    /// título se repita en otra fila. Antes se anotaba con un gesto de toque encima del póster, que a veces se comía el toque
    /// y la ficha no abría (Mi lista en Inicio).
    @State private var slot = UUID()

    var body: some View {
        Group {
            if let panel {
                Button { panel(route, from: frame.rect) } label: { label() }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.rect = $0 }
            } else if zoom != nil {
                NavigationLink(value: TitleZoomID(route: route, slot: slot)) { label() }
            } else {
                NavigationLink(value: route) { label() }
            }
        }
        .environment(\.titleZoomSlot, slot)
        .macPosterHover(route)   // RP2: en la Mac, al pasar el puntero crece con el marco de la TV y muestra ▶ y ＋
        .accessibilityIdentifier("title-link")   // para las pruebas de interfaz
    }
}

/// Un marco que se guarda sin avisar a SwiftUI (solo se lee al tocar).
@MainActor private final class FrameBox {
    var rect: CGRect?
}

/// Abre la ficha de un estado (`openTitle`): en el panel si lo hay; si no, como destino de la navegación.
private struct OpeningTitles: ViewModifier {
    @Binding var item: TitleRoute?
    @Environment(\.titlePanel) private var panel

    func body(content: Content) -> some View {
        content
            .navigationDestination(item: Binding(get: { panel == nil ? item : nil }, set: { item = $0 })) { TitleView(route: $0) }
            .onChange(of: item) { _, route in
                guard let route, let panel else { return }
                panel(route)
                item = nil
            }
    }
}

extension View {
    /// Receta: la ficha que pide `item` (en el panel en iPad y Mac; a pantalla completa en el iPhone).
    func openingTitles(item: Binding<TitleRoute?>) -> some View { modifier(OpeningTitles(item: item)) }
}

/// La ficha dentro del panel: la misma del iPhone, con su propia navegación (reparto, saga, otra película se abren dentro
/// del panel) y una ✕ para cerrarla.
struct TitlePanel: View {
    let route: TitleRoute
    let close: () -> Void
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            TitleView(route: route)
                .id(route)
                .titleDestinations()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cerrar", systemImage: "xmark", action: close).keyboardShortcut(.cancelAction).accessibilityIdentifier("title-panel-close")   // ds-exception: botón nativo de la barra de navegación (D7)
                    }
                }
        }
        .environment(\.titlePanel, nil)   // dentro del panel, las fichas navegan dentro de él
        .environment(\.titleInPanel, true)
        .onChange(of: route) { path = NavigationPath() }
    }
}

