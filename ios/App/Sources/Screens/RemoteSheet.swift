import SwiftUI
import OrbitalCore
import OrbitalModels

/// El control de tu Orbital, en una hoja con dos alturas (como el reproductor de Música): corta, el control de lo que se
/// ve en la TV (pausa, ±10, siguiente…); estirada hacia arriba, además el control completo de la consola: el pad
/// (`TouchPad`), sus teclas (`RemoteKey`) y «Escribir» cuando la TV tiene dónde.
struct RemoteSheet: View {
    @ObservedObject var tvNow: ModelObserver<TVNowModel>
    @Binding var large: Bool
    let onContinueHere: (OrbitalRemote.NowPlaying) -> Void
    @State private var compactHeight: CGFloat = DS.Remote.padHeight
    @State private var text = ""

    var body: some View {
        let model = tvNow.model
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                header(model)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { compactHeight = $0 + DS.Space.s6 + DS.Space.s10 }
                if large { full(model).transition(.opacity.combined(with: .move(edge: .bottom))) }
                else {
                    Label("Estira hacia arriba para el control completo", systemImage: "chevron.compact.up")
                        .recipe(.caption, color: DS.textFaint).frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, DS.Space.gutter).padding(.top, DS.Space.s6).padding(.bottom, DS.Space.s4)
        }
        .scrollDisabled(!large)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(compactHeight), .large], selection: Binding(
            get: { large ? .large : .height(compactHeight) },
            set: { large = $0 == .large }))
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.disabled)
        .animation(DS.Motion.base(false), value: large)
    }

    /// Lo que se ve en la TV (el control de siempre) o, si nada se reproduce, solo el nombre de tu Orbital.
    @ViewBuilder private func header(_ model: TVNowModel) -> some View {
        if let now = model.now {
            NowPlayingCard(now: now, fetchedAt: model.fetchedAt, busy: model.busy,
                           onAction: { action, delta in Task { await model.control(action, delta: delta) } },
                           onContinueHere: { onContinueHere(now) }, framed: false)
        } else {
            Label("Tu Orbital", systemImage: "tv").recipe(.section)
        }
    }

    /// El control completo: el pad, las teclas de la consola y escribir.
    @ViewBuilder private func full(_ model: TVNowModel) -> some View {
        VStack(spacing: DS.Space.s4) {
            if model.remoteOutdated { DSNotice(text: "Actualiza tu Orbital para usar el control completo.", tone: .warn) }
            TouchPad { action in Task { await model.press(action) } }
                .containerRelativeFrame(.vertical) { length, _ in max(DS.Remote.padHeight, length * DS.Remote.padShare) }
            HStack(spacing: DS.Space.s2) {
                RemoteKey(symbol: "chevron.backward", title: "Atrás") { Task { await model.press(.back) } }
                RemoteKey(symbol: "house", title: "Inicio") { Task { await model.press(.home) } }
                RemoteKey(symbol: "line.3.horizontal", title: "Menú") { Task { await model.press(.menu) } }
                RemoteKey(symbol: "magnifyingglass", title: "Buscar") { Task { await model.press(.search) } }
                RemoteKey(symbol: "ellipsis", title: "Opciones") { Task { await model.press(.options) } }
            }
            // Siempre: si la TV no tiene un campo abierto, escribir abre su búsqueda con ese texto.
            RemoteTextField(text: $text) { let typed = text; Task { await model.type(typed, submit: true) } }
                .task(id: text) {
                    // Mientras escribes, la TV lo va enseñando (sin mandar cada letra por separado).
                    guard !text.isEmpty else { return }
                    try? await Task.sleep(nanoseconds: DS.Remote.typeDebounce)
                    guard !Task.isCancelled else { return }
                    await model.type(text, submit: false)
                }
        }
    }
}
