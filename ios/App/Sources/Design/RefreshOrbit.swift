import SwiftUI

/// Tirar para actualizar con la marca de Orbital (en vez de la ruedita del sistema): mientras jalas, el anillo del planeta se
/// dibuja de una punta a la otra; al soltar pasado el umbral, la luna orbita alrededor del planeta hasta que termina. Con
/// «Reducir movimiento», la luna no gira: el planeta late con un fundido. VoiceOver tiene la acción «Actualizar».
struct RefreshOrbit: View {
    /// 0…1: cuánto has jalado hacia el umbral.
    let pull: CGFloat
    let refreshing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turn = false

    var body: some View {
        let size = DS.Refresh.mark
        let unit = size / DS.Brand.box
        ZStack {
            MarkPlanet()
            MarkRing().mask { MarkRingSpine().trim(from: 0, to: refreshing ? 1 : pull).stroke(style: MarkRingSpine.reveal(unit)) }
            if refreshing && !reduceMotion {
                // La luna sobre una elipse inclinada como el anillo: un círculo que gira, aplastado e inclinado.
                Circle().fill(DS.brandMoon).frame(width: DS.Refresh.moon, height: DS.Refresh.moon)
                    .offset(y: -size * DS.Refresh.orbit)
                    .rotationEffect(.degrees(turn ? 360 : 0))
                    .scaleEffect(x: 1, y: DS.Refresh.orbitSquash)
                    .rotationEffect(.degrees(DS.Brand.ringTilt))
            }
        }
        .foregroundStyle(DS.text)
        .frame(width: size, height: size)
        .opacity(refreshing ? (reduceMotion && turn ? DS.Opacity.dimmed : 1) : min(1, pull * 1.5))
        .scaleEffect(refreshing ? 1 : DS.Refresh.startScale + (1 - DS.Refresh.startScale) * pull)
        .onChange(of: refreshing, initial: true) { _, now in
            guard now else { turn = false; return }
            withAnimation(reduceMotion ? DS.Motion.fade.repeatForever() : .linear(duration: DS.Refresh.lap).repeatForever(autoreverses: false)) { turn = true }   // ds-exception: la luna da vueltas parejas
        }
        .accessibilityHidden(true)
    }
}

/// Cuánto se jala y si está actualizando: lo lleva la lista (`orbitalRefreshable`) y lo pinta su hueco (`RefreshOrbitSlot`).
@MainActor @Observable final class RefreshPull {
    /// 0…1 hacia el umbral, y los puntos jalados.
    var pull: CGFloat = 0
    var distance: CGFloat = 0
    var refreshing = false
}

/// El hueco de la luna, detrás del contenido de la lista (no alrededor de la lista: una capa encima o detrás de ella le impedía
/// a iOS esconder la barra de búsqueda al desplazar). Mientras jalas, la luna va al centro del espacio que se abre arriba; mientras
/// actualiza, el contenido baja un poco y la luna gira en ese hueco.
private struct RefreshOrbitHost: ViewModifier {
    @Environment(RefreshPull.self) private var state: RefreshPull?

    func body(content: Content) -> some View {
        let refreshing = state?.refreshing ?? false
        content
            .padding(.top, refreshing ? DS.Refresh.slot : 0)
            // Detrás del contenido (una capa encima, aunque vacía, se comía el arrastre de las filas de Inicio).
            .background(alignment: .top) {
                if let state, state.pull > 0 || refreshing {
                    RefreshOrbit(pull: state.pull, refreshing: refreshing)
                        .offset(y: refreshing ? DS.Space.s2 : -(state.distance + DS.Refresh.mark) / 2)
                        .allowsHitTesting(false)
                }
            }
    }
}

private struct OrbitalRefreshable: ViewModifier {
    let action: @Sendable () async -> Void
    @State private var state = RefreshPull()
    @State private var armed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(state)
            // Cuánto se jala por encima del inicio (en puntos), sin contar la barra de arriba.
            .onScrollGeometryChange(for: CGFloat.self) { geo in max(0, -(geo.contentOffset.y + geo.contentInsets.top)) } action: { _, distance in
                state.distance = distance
                state.pull = min(1, distance / DS.Refresh.threshold)
                if distance >= DS.Refresh.threshold, !state.refreshing { armed = true }
            }
            // Se actualiza al soltar (no en cuanto llega al umbral, como el sistema): da tiempo de arrepentirse.
            .onScrollPhaseChange { _, phase in
                guard armed, phase != .interacting else { return }
                armed = false
                start()
            }
            .sensoryFeedback(.impact(flexibility: .soft), trigger: armed) { old, new in !old && new }   // llegaste al umbral
            .accessibilityAction(named: Text("Actualizar")) { start() }
    }

    private func start() {
        guard !state.refreshing else { return }
        withAnimation(DS.Motion.snap(reduceMotion) ?? DS.Motion.fade) { state.refreshing = true }
        Task {
            await action()
            withAnimation(DS.Motion.snap(reduceMotion) ?? DS.Motion.fade) { state.refreshing = false }
        }
    }
}

extension View {
    /// Tirar para actualizar con la marca de Orbital (`RefreshOrbit`), en lugar de `.refreshable`, en la lista. Su contenido
    /// lleva `.refreshOrbitHost()`, donde se pinta la luna.
    func orbitalRefreshable(_ action: @escaping @Sendable () async -> Void) -> some View { modifier(OrbitalRefreshable(action: action)) }
    /// Donde se pinta la luna de `orbitalRefreshable`: el contenido de la lista (lo de adentro del `ScrollView`).
    func refreshOrbitHost() -> some View { modifier(RefreshOrbitHost()) }
}
