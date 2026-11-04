import SwiftUI
import OrbitalModels

/// Los avisos sobre la pantalla (F3, Fernando, 3 nov 2026), la primera vez que entras a algo propio de Orbital. Dos formas:
/// con foco (el velo oscurece todo menos el botón señalado, un anillo se dibuja una vez y no late, y la burbuja sube junto
/// a él) para «Ver» en la ficha y la búsqueda avanzada; y el aviso chico, sin oscurecer, arriba de la pantalla. Cada uno
/// dice qué hace, lleva «Ver la historia» (la de esa función en «Aprende») y se cierra con «Entendido»; «Saltar avisos» los
/// apaga todos. VoiceOver lo anuncia y se cierra con el gesto de escape. Recibe sus datos: no lee el estado de la app.
struct CoachContent: Equatable {
    let id: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    /// Con foco (oscurece todo menos `id`) o aviso chico.
    let spotlight: Bool
    /// La escena en miniatura con su dedo fantasma (la misma de su historia, en chico).
    var scene: LearnStory.Scene?

    static func == (a: CoachContent, b: CoachContent) -> Bool { a.id == b.id && a.spotlight == b.spotlight }
}

/// Dónde está lo que señala un aviso con foco (solo mientras el aviso está a la vista: fuera de eso no hay preferencia).
struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension EnvironmentValues {
    /// El aviso con foco que está a la vista (su id): solo lo que él señala publica dónde está.
    @Entry var coachShowing: String?
}

/// Publica dónde está lo que señala el aviso `id`, solo mientras ese aviso está a la vista.
private struct CoachAnchor: ViewModifier {
    let id: String
    @Environment(\.coachShowing) private var showing

    func body(content: Content) -> some View {
        if showing == id { content.anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [id: $0] } } else { content }
    }
}

extension View {
    /// Marca lo que señala el aviso `id`.
    func coachAnchor(_ id: String) -> some View { modifier(CoachAnchor(id: id)) }

    /// Pone encima de la pantalla el aviso `coach` (nil: ninguno).
    func coachHost(_ coach: CoachContent?, story: @escaping () -> Void, done: @escaping () -> Void, skipAll: @escaping () -> Void) -> some View {
        environment(\.coachShowing, coach?.id).overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            if let coach {
                GeometryReader { geo in
                    CoachOverlay(coach: coach, target: anchors[coach.id].map { geo[$0] }, size: geo.size, story: story, done: done, skipAll: skipAll)
                }
            }
        }
    }
}

struct CoachOverlay: View {
    let coach: CoachContent
    let target: CGRect?
    let size: CGSize
    let story: () -> Void
    let done: () -> Void
    let skipAll: () -> Void
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let hole = target?.insetBy(dx: -DS.Coach.hole, dy: -DS.Coach.hole)
        ZStack(alignment: .topLeading) {
            if coach.spotlight, let hole {
                // El velo con el hueco del botón; tocar el velo cierra (como «Entendido»).
                Rectangle().fill(DS.backdropDeep.opacity(DS.Coach.veil))
                    .reverseMask { RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).frame(width: hole.width, height: hole.height).position(x: hole.midX, y: hole.midY) }
                    .ignoresSafeArea()
                    .onTapGesture(perform: done)
                    .accessibilityHidden(true)
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .trim(from: 0, to: shown || reduceMotion ? 1 : 0)
                    .stroke(DS.fresh, lineWidth: DS.Coach.ring)
                    .frame(width: hole.width, height: hole.height).position(x: hole.midX, y: hole.midY)
                    .accessibilityHidden(true)
            }
            bubble
                .frame(maxWidth: min(DS.Coach.bubble, size.width - 2 * DS.Space.gutter))
                .position(x: size.width / 2, y: bubbleY(hole))
                .offset(y: shown || reduceMotion ? 0 : DS.Space.s2)
                .opacity(shown || reduceMotion ? 1 : 0)
        }
        .task { withAnimation(DS.Motion.enter(reduceMotion)) { shown = true } }
        .onAppear { UIAccessibility.post(notification: .announcement, argument: nil) }
    }

    /// Debajo de lo señalado si cabe; si no, arriba. El aviso chico va arriba de la pantalla.
    private func bubbleY(_ hole: CGRect?) -> CGFloat {
        guard let hole else { return DS.Space.s14 }
        let below = hole.maxY + DS.Space.s4 + DS.Space.s14
        return below < size.height - DS.Space.s14 ? below : hole.minY - DS.Space.s4 - DS.Space.s14
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let scene = coach.scene {
                StorySceneView(scene: scene, tint: DS.ListTint.spark).frame(height: DS.Coach.scene).accessibilityHidden(true)
            }
            Text(coach.title).recipe(.cardTitle, color: DS.text).fixedSize(horizontal: false, vertical: true)
            Text(coach.detail).recipe(.secondary, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s3) {
                Button("Ver la historia", action: story).buttonStyle(.borderless).foregroundStyle(DS.eyebrow)
                    .accessibilityIdentifier("coach-story")
                Spacer(minLength: 0)
                Button("Entendido", action: done).dsPrimaryButton(size: .small)
                    .accessibilityIdentifier("coach-done")
            }
            Button(action: skipAll) { Text("Saltar avisos").recipe(.footnote, color: DS.textMuted) }.buttonStyle(.borderless)
                .accessibilityIdentifier("coach-skip-all")
        }
        .padding(DS.Space.s4)
        .dsCard(.card)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape, done)
        .accessibilityIdentifier("coach-\(coach.id)")
    }
}

private extension View {
    /// Lo de `mask` queda transparente (el hueco del foco).
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask { Rectangle().overlay { mask().blendMode(.destinationOut) }.compositingGroup() }
    }
}
