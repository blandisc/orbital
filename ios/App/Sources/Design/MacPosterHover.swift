import SwiftUI

/// RP2 (Fernando, 16 nov 2026: «hazlo de acuerdo a tus sugerencias»): en la Mac el puntero es la forma principal de moverse.
/// Al pasar sobre un enlace con póster (`TitleNavigationLink`, `TmdbPoster`), la tarjeta crece un poco y el póster lleva el
/// marco crema del foco de la TV; si el póster es grande (`DS.Mac.quickMinWidth`), muestra ▶ (ver) y ＋ (guardar en Mi lista)
/// en su esquina, sin abrir la ficha. Lo mismo está en VoiceOver y en el menú del póster. En iPhone y iPad no cambia nada.
/// Regla en docs/ios-interfaz.md § «El replanteamiento de la Mac».
extension EnvironmentValues {
    /// Ver y guardar desde un póster (▶ y ＋ al pasar el puntero en la Mac). Lo pone la raíz; sin él no salen los botones.
    @Entry var posterQuick: PosterQuick?
}

/// Lo que hacen ▶ y ＋ sobre un póster: la raíz lo conecta con la app (las piezas del catálogo no tocan su estado).
/// Se compara por `id` (la app que lo armó): con cierres nuevos en cada pasada de la raíz, cada póster se volvía a pintar
/// (lo mismo que se corrigió en `TitlePanelOpener`).
/// Solo datos (V9, como `RemoteOpener`): con las acciones dentro, SwiftUI daba el valor por cambiado en cada pasada de la raíz
/// (cada cambio de pestaña) aunque `==` dijera igual, y volvía a pintar cada póster de las cuatro pestañas (22 nov 2026). Lo
/// que hacen ▶ y ＋ vive en `PosterQuick+App.swift`.
struct PosterQuick: Equatable {
    let id: ObjectIdentifier
}

/// Dónde está el póster dentro del enlace: el marco y ▶ ＋ van sobre él, no sobre toda la tarjeta (una tarjeta ancha
/// tiene su insignia a la derecha; un renglón, su flecha).
struct PosterBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

extension View {
    /// El póster avisa dónde está (solo en la Mac), para que su enlace le dibuje el marco y ▶ ＋ encima.
    func macPosterBounds() -> some View {
        anchorPreference(key: PosterBoundsKey.self, value: .bounds) { ThisDevice.isMac ? $0 : nil }
    }

    /// El enlace de un póster responde al puntero en la Mac. Sin `route` (un título de TMDB sin IMDb) solo lleva el marco.
    func macPosterHover(_ route: TitleRoute?) -> some View { modifier(MacPosterHover(route: route)) }
}

private struct MacPosterHover: ViewModifier {
    let route: TitleRoute?
    @State private var hovering = false
    /// El póster de este enlace es de los grandes (se sabe al pasar el puntero): crece la tarjeta y salen ▶ ＋.
    @State private var large = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.posterQuick) private var quick

    func body(content: Content) -> some View {
        if ThisDevice.isMac {
            content
                .overlayPreferenceValue(PosterBoundsKey.self) { anchor in
                    if hovering, let anchor {
                        GeometryReader { proxy in
                            let rect = proxy[anchor]
                            let big = rect.width >= DS.Mac.quickMinWidth
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .strokeBorder(DS.paper, lineWidth: DS.Mac.hoverRing)
                                    .allowsHitTesting(false)
                                if big, let quick, let route {
                                    PosterQuickActions(route: route, quick: quick).padding(DS.Space.s2)
                                }
                            }
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .onAppear { large = big }
                        }
                        .transition(.opacity)
                    }
                }
                // Crece la tarjeta entera (póster, insignias y barra de avance juntos); un renglón con póster chico no.
                .scaleEffect(hovering && large ? DS.Mac.hoverScale : 1)
                .zIndex(hovering ? 1 : 0)   // lo que crece pasa por encima del vecino, no por debajo
                // Solo cuando el puntero se mueve: al deslizar con la rueda el puntero se queda quieto y los pósters pasan por
                // debajo; cada uno crecía, se encogía y armaba su marco, decenas por segundo (el deslizar se sentía trabado,
                // 25 nov 2026). Al dejar de deslizar, el póster bajo el puntero se marca en cuanto lo mueves.
                .onContinuousHover(coordinateSpace: .global) { phase in
                    switch phase {
                    case .active(let at):
                        MacPointer.note(at)
                        if !hovering, MacPointer.isMoving { withAnimation(DS.Motion.fold(reduceMotion)) { hovering = true } }
                    case .ended:
                        if hovering { withAnimation(DS.Motion.fold(reduceMotion)) { hovering = false } }
                    }
                }
                .modifier(QuickAccessibility(route: route, quick: quick))
        } else {
            content
        }
    }
}

/// Cuándo se movió el puntero por última vez (lo anota toda la ventana, `macPointerWatch`, y cada póster): si un póster
/// «entra» con el puntero quieto, es que el contenido se deslizó por debajo. Sin observar: nada se vuelve a pintar.
@MainActor enum MacPointer {
    private static var last: CGPoint?
    private static var movedAt: CFTimeInterval = 0
    static func note(_ point: CGPoint) {
        if let last, abs(last.x - point.x) <= 0.5, abs(last.y - point.y) <= 0.5 { return }
        last = point
        movedAt = CACurrentMediaTime()
    }
    static var isMoving: Bool { CACurrentMediaTime() - movedAt < DS.Mac.pointerMoving }
}

extension View {
    /// Toda la ventana anota cuándo se mueve el puntero (`MacPointer`); en iPhone y iPad, nada.
    @ViewBuilder func macPointerWatch() -> some View {
        if ThisDevice.isMac {
            onContinuousHover(coordinateSpace: .global) { phase in if case .active(let at) = phase { MacPointer.note(at) } }
        } else { self }
    }
}

/// ▶ y ＋ también sin puntero: VoiceOver los ofrece como acciones del póster (las cuatro superficies).
private struct QuickAccessibility: ViewModifier {
    let route: TitleRoute?
    let quick: PosterQuick?
    func body(content: Content) -> some View {
        if let route, let quick {
            content
                .accessibilityAction(named: Text("Ver")) { quick.play(route) }
                .accessibilityAction(named: Text("Guardar en Mi lista")) { quick.save(route) }
        } else {
            content
        }
    }
}

/// ▶ y ＋ sobre un póster en la Mac: ver (donde ibas, o desde el principio) y guardar en Mi lista, con su aviso que se deshace.
private struct PosterQuickActions: View {
    let route: TitleRoute
    let quick: PosterQuick

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            DSIconButton(symbol: "play.fill", label: "Ver", prominent: true, size: .regular) { quick.play(route) }
            DSIconButton(symbol: "plus", label: "Guardar en Mi lista", size: .regular) { quick.save(route) }
        }
    }
}
