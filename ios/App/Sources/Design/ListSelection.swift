import SwiftUI
import OrbitalCore

/// Elegir varios a la vez (G3-A, Fernando, 10 nov 2026: «Vamos con tus sugerencias»). En Guardado, «Editar» ya no pone un «−»
/// en cada póster: cada toque elige (`DSSelectMark`), deslizar el dedo de lado elige de corrido (como en Fotos), «Todas» junto a
/// la cifra (`SelectionHeader`) y abajo la barra de esa pantalla (`DSSelectionBar`), encima de las pestañas (que nunca se esconden).
/// Teclado y puntero: ⌘E entra y sale, ⌘A elige todas, Esc sale; el botón «Quitar» responde a ⌫.
/// docs/producto/live-activity-2026-11-08/gestor-ola2.html
@MainActor @Observable
final class ListSelection {
    var editing = false { didSet { if !editing { chosen = [] } } }
    private(set) var chosen: Set<String> = []
    /// Dónde está cada póster (para elegir de corrido al deslizar).
    @ObservationIgnored var frames: [String: CGRect] = [:]
    /// El deslizamiento en curso: si elige o quita, o si empezó de arriba abajo (entonces es scroll y no se toca).
    @ObservationIgnored private var drag: (adds: Bool, ignore: Bool)?

    func toggle(_ id: String) { if chosen.contains(id) { chosen.remove(id) } else { chosen.insert(id) } }
    func set(_ ids: Set<String>) { chosen = ids }
    func clear() { chosen = [] }

    func dragChanged(start: CGPoint, location: CGPoint, translation: CGSize) {
        if drag == nil {
            let sideways = abs(translation.width) > abs(translation.height)
            let first = frames.first { $0.value.contains(start) }?.key
            drag = (adds: first.map { !chosen.contains($0) } ?? true, ignore: !sideways || first == nil)
        }
        guard let drag, !drag.ignore, let id = frames.first(where: { $0.value.contains(location) })?.key else { return }
        if drag.adds { chosen.insert(id) } else { chosen.remove(id) }
    }
    func dragEnded() { drag = nil }

    static let space = "list-selection"
}

/// El círculo de un póster mientras eliges: vacío o lleno con la palomita.
struct DSSelectMark: View {
    let selected: Bool
    var body: some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .symbolRenderingMode(selected ? .palette : .monochrome)
            .foregroundStyle(selected ? DS.onPrimary : DS.paper, DS.accent)
            .font(DS.TextRecipe.section.font)
            .background(Circle().fill(DS.scrim).opacity(selected ? 0 : 1))
            .padding(DS.Space.s2)
            .contentTransition(.symbolEffect(.replace))
    }
}

extension View {
    /// Un póster que se puede elegir: mientras eliges, un toque lo elige (ya no abre la ficha), los no elegidos se apagan un
    /// poco y VoiceOver dice «elegida» o «no elegida».
    func selectable(_ selection: ListSelection, id: String, title: String) -> some View {
        modifier(SelectableModifier(selection: selection, id: id, title: title))
    }

    /// Deslizar el dedo de lado sobre los pósters los elige de corrido; de arriba abajo sigue siendo scroll.
    func selectionDrag(_ selection: ListSelection) -> some View {
        coordinateSpace(.named(ListSelection.space))
            .simultaneousGesture(
                DragGesture(minimumDistance: DS.Space.s3, coordinateSpace: .named(ListSelection.space))
                    .onChanged { v in if selection.editing { selection.dragChanged(start: v.startLocation, location: v.location, translation: v.translation) } }
                    .onEnded { _ in selection.dragEnded() },
                isEnabled: selection.editing)
    }
}

private struct SelectableModifier: ViewModifier {
    let selection: ListSelection
    let id: String
    let title: String

    func body(content: Content) -> some View {
        let editing = selection.editing, on = selection.chosen.contains(id)
        content
            .allowsHitTesting(!editing)
            .opacity(editing && !on ? DS.Opacity.dimmed : 1)
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button { selection.toggle(id) } label: {
                        Color.clear.contentShape(Rectangle()).overlay(alignment: .topTrailing) { DSSelectMark(selected: on) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: title))
                    .accessibilityValue(on ? Text("Elegida") : Text("No elegida"))
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("poster-select")
                    .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ListSelection.space)) } action: { selection.frames[id] = $0 }
            .dsFeedback(.selection, trigger: on)
    }
}

/// «Editar» · «Listo» y «+» arriba (⌘E, ⌘N); mientras eliges, ⌘A elige todas y Esc sale.
struct ListSelectToolbar: ToolbarContent {
    let selection: ListSelection
    var add: (() -> Void)?
    var all: [String] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let add {
                Button(action: add) { Label("Agregar", systemImage: "plus") }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("list-add")
            }
            Button { withAnimation(DS.Motion.base(reduceMotion)) { selection.editing.toggle() } } label: {
                Text(selection.editing ? "Listo" : "Editar").fontWeight(selection.editing ? .semibold : .regular)
            }
            .keyboardShortcut("e", modifiers: .command)
            .accessibilityIdentifier("list-edit")
            .background {
                if selection.editing {
                    // ds-exception: atajos de teclado sin botón propio (⌘A, Esc); invisibles a propósito
                    Button("Elegir todas") { selection.set(Set(all)) }.keyboardShortcut("a", modifiers: .command).opacity(0).accessibilityHidden(true)   // ds-exception: atajo ⌘A sin botón visible
                    Button("Listo") { selection.editing = false }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)   // ds-exception: Esc sale de elegir
                }
            }
        }
    }
}

/// «3 elegidas de 124 · Todas» (o «Ninguna» si ya están todas).
struct SelectionHeader: View {
    let selection: ListSelection
    let all: [String]

    var body: some View {
        let count = selection.chosen.count, every = !all.isEmpty && Set(all).isSubset(of: selection.chosen)
        HStack(spacing: DS.Space.s3) {
            Text(count == 0 ? "Toca para elegir" : "\(count) elegidas de \(all.count)").recipe(.footnote, color: DS.textMuted)
                .contentTransition(.numericText())
            Button { every ? selection.clear() : selection.set(Set(all)) } label: {
                Label(every ? "Ninguna" : "Todas", systemImage: every ? "circle" : "checkmark.circle")
            }
            .font(DS.TextRecipe.label.font).foregroundStyle(DS.accent)
            .frame(minHeight: DS.Size.touchTarget)
            .accessibilityIdentifier("select-all")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.gutter)
        .accessibilityElement(children: .contain)
    }
}

/// La barra de abajo mientras eliges: ícono con su nombre debajo, en vidrio, encima de las pestañas. Sin nada elegido, sus
/// botones se ven apagados.
struct DSSelectionBar<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 0) { content }
            .padding(.vertical, DS.Space.s2)
            .padding(.horizontal, DS.Space.s3)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, DS.Space.gutter)
            .padding(.bottom, DS.Space.s2)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("selection-bar")
    }
}

/// Un botón de `DSSelectionBar`: ícono arriba, nombre abajo.
struct DSSelectionBarLabel: View {
    let title: LocalizedStringKey
    let symbol: String
    var destructive = false
    var body: some View {
        VStack(spacing: DS.Space.s1) {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).frame(height: DS.Space.s6)   // misma altura: los textos quedan en línea
            Text(title).font(DS.TextRecipe.caption.font).lineLimit(1)
        }
        .foregroundStyle(destructive ? DS.danger : DS.text)
        .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .top)
        .contentShape(Rectangle())
    }
}
