import SwiftUI
import OrbitalCore

// MARK: La ficha en un panel lateral (iPad, Mac)

/// Abrir una ficha en el panel de la derecha, sobre lo que estabas viendo (como el iPhone, que la empuja a pantalla completa).
/// Solo existe con ancho regular (iPad, Mac): lo pone `MainTabs`. En el iPhone es `nil` y todo navega como siempre.
struct TitlePanelOpener {
    /// La ficha y, si se sabe, el marco del póster que se tocó (en la ventana): de ahí sale el zoom hacia el panel.
    let open: (TitleRoute, CGRect?) -> Void
    func callAsFunction(_ route: TitleRoute, from frame: CGRect? = nil) { open(route, frame) }
}

extension EnvironmentValues {
    @Entry var titlePanel: TitlePanelOpener? = nil
}

/// El enlace a una ficha del catálogo: con panel (iPad, Mac), la abre a la derecha; sin él (iPhone), navega como siempre.
struct TitleNavigationLink<Label: View>: View {
    let route: TitleRoute
    @ViewBuilder var label: () -> Label
    @Environment(\.titlePanel) private var panel
    /// Dónde está el póster en la ventana: el zoom hacia el panel sale de aquí.
    @State private var frame: CGRect?

    var body: some View {
        if let panel {
            Button { panel(route, from: frame) } label: { label() }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .accessibilityIdentifier("title-link")   // para las pruebas de interfaz
        } else {
            NavigationLink(value: route) { label() }.accessibilityIdentifier("title-link")
        }
    }
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
                        Button("Cerrar", systemImage: "xmark", action: close).accessibilityIdentifier("title-panel-close")
                    }
                }
        }
        .environment(\.titlePanel, nil)   // dentro del panel, las fichas navegan dentro de él
        .onChange(of: route) { path = NavigationPath() }
    }
}

// MARK: El zoom del póster hacia el panel

/// El póster que vuela desde donde lo tocaste hasta el arte de la ficha en el panel de la derecha (el zoom del iPhone,
/// hacia un panel). Mientras vuela el panel entra por la derecha; al llegar se desvanece y queda la ficha.
struct PosterFlight: Equatable {
    var poster: String?
    var title: String
    var from: CGRect
    var landed = false
    var fading = false
}

private struct PosterFlightLayer: ViewModifier {
    @Binding var flight: PosterFlight?
    /// El ancho del panel (el de `inspectorColumnWidth`).
    let panelWidth: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            if let flight {
                GeometryReader { geo in
                    let origin = geo.frame(in: .global).origin
                    let rect = flight.landed ? target(in: geo.size) : flight.from.offsetBy(dx: -origin.x, dy: -origin.y)
                    PosterView(url: flight.poster, title: flight.title, aspect: nil)
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .shadow(color: DS.scrimStrong, radius: DS.PlayerPanel.liftShadow)
                        .position(x: rect.midX, y: rect.midY)
                        .opacity(flight.fading ? 0 : 1)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    /// Donde cae: el arte de la ficha, arriba del panel (su proporción, `DS.TitleAction.heroAspect`).
    private func target(in size: CGSize) -> CGRect {
        let width = panelWidth - DS.Space.gutter * 2
        return CGRect(x: size.width - panelWidth + DS.Space.gutter, y: DS.TitleAction.panelArtTop,
                      width: width, height: width / DS.TitleAction.heroAspect)
    }
}

extension View {
    /// El zoom del póster hacia el panel de la derecha (ver `PosterFlight`). Una vez, donde vive el panel (`MainTabs`).
    func posterFlight(_ flight: Binding<PosterFlight?>, panelWidth: CGFloat) -> some View {
        modifier(PosterFlightLayer(flight: flight, panelWidth: panelWidth))
    }
}

/// Lanza el vuelo: sale de `from`, cae en el panel con un resorte y se desvanece. Sin «Reducir movimiento».
@MainActor
func launchPosterFlight(_ flight: Binding<PosterFlight?>, route: TitleRoute, from: CGRect?, reduceMotion: Bool) {
    guard let from, !reduceMotion else { return }
    flight.wrappedValue = PosterFlight(poster: route.poster, title: route.title, from: from)
    Task { @MainActor in
        await Task.yield()   // un cuadro en el lugar del póster, para que el resorte tenga de dónde salir
        withAnimation(.spring(duration: DesignTokens.Motion.slow, bounce: DS.TitleAction.flightBounce)) { flight.wrappedValue?.landed = true }
        try? await Task.sleep(for: .seconds(DesignTokens.Motion.slow))
        withAnimation(DS.Motion.base(false)) { flight.wrappedValue?.fading = true }
        try? await Task.sleep(for: .seconds(DesignTokens.Motion.base))
        flight.wrappedValue = nil
    }
}
