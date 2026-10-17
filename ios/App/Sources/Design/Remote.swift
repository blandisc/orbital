import SwiftUI
import OrbitalCore

// El control completo de tu Orbital (la hoja de «Viendo en la TV» estirada hacia arriba): piezas del catálogo.

/// El pad táctil, como el del control del Apple TV: deslizar = flechas (una por cada `DS.Remote.swipeStep`, con toque
/// háptico; al seguir deslizando se repite), tocar = A (elegir). Se usa sin mirar.
struct TouchPad: View {
    let onAction: (OrbitalRemote.InputAction) -> Void
    @State private var origin: CGPoint?
    @State private var moved = false
    @State private var touch: CGPoint?
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous)
            .fill(DS.fill)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous).strokeBorder(DS.hairline, lineWidth: DS.Size.hairline))
            .overlay { hints }
            .overlay {
                if let touch {
                    Circle().fill(DS.fillStrong).frame(width: DS.Remote.touchGlow, height: DS.Remote.touchGlow)
                        .position(touch).allowsHitTesting(false)
                }
            }
            .frame(minHeight: DS.Remote.padHeight)
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        touch = value.location
                        let start = origin ?? value.startLocation
                        if origin == nil { origin = start }
                        let dx = value.location.x - start.x, dy = value.location.y - start.y
                        guard max(abs(dx), abs(dy)) >= DS.Remote.swipeStep else { return }
                        moved = true
                        fire(abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up))
                        origin = value.location   // la siguiente flecha cuenta desde aquí: seguir deslizando repite
                    }
                    .onEnded { value in
                        let total = hypot(value.translation.width, value.translation.height)
                        if !moved, total < DS.Remote.tapSlop { fire(.select) }
                        origin = nil; moved = false
                        withAnimation(DS.Motion.base(reduceMotion)) { touch = nil }
                    }
            )
            .sensoryFeedback(.selection, trigger: ticks)
            .accessibilityElement()
            .accessibilityLabel(Text("Pad de la TV"))
            .accessibilityHint(Text("Desliza para moverte; toca para elegir"))
            .accessibilityAction(named: Text("Arriba")) { onAction(.up) }
            .accessibilityAction(named: Text("Abajo")) { onAction(.down) }
            .accessibilityAction(named: Text("Izquierda")) { onAction(.left) }
            .accessibilityAction(named: Text("Derecha")) { onAction(.right) }
            .accessibilityAction { onAction(.select) }
    }

    private func fire(_ action: OrbitalRemote.InputAction) {
        ticks += 1
        onAction(action)
    }

    /// Las flechas apenas marcadas en las orillas y, al centro, qué hace tocar.
    private var hints: some View {
        ZStack {
            VStack { chevron("chevron.up"); Spacer(); chevron("chevron.down") }
            HStack { chevron("chevron.left"); Spacer(); chevron("chevron.right") }
            VStack(spacing: DS.Space.s1) {
                Text(verbatim: "A").recipe(.title, color: DS.textMuted)
                Text("Desliza · toca para elegir").recipe(.caption, color: DS.textFaint)
            }
        }
        .padding(DS.Space.s4)
        .allowsHitTesting(false)
    }

    private func chevron(_ name: String) -> some View {
        Image(systemName: name).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.textFaint)
    }
}

/// Una tecla de la consola en el control completo (Atrás, Inicio, Menú…): ícono y nombre, del mismo tamaño todas.
struct RemoteKey: View {
    let symbol: String
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button { taps += 1; action() } label: {
            VStack(spacing: DS.Space.s1) {
                Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font)
                Text(title).recipe(.caption, color: DS.textMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: DS.Remote.keyHeight)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(DS.text)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: taps)
    }
}

/// Escribir en la TV (la búsqueda de la consola): el campo con el estilo de las teclas del control.
struct RemoteTextField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "keyboard").foregroundStyle(DS.textMuted).accessibilityHidden(true)
            TextField("Escribir en la TV", text: $text)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(onSubmit)
                .foregroundStyle(DS.text)
        }
        .font(DS.TextRecipe.body.font)
        .padding(.horizontal, DS.Space.s4)
        .frame(minHeight: DS.Remote.keyHeight)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}
