import SwiftUI

// Piezas del panel «Ajustes del video» y de los botones con nombre del reproductor.

/// Un botón del reproductor con su nombre («En la TV», «Ventana», «Audio y subtítulos»); si no cabe, solo el ícono
/// (VoiceOver siempre dice el nombre).
struct PlayerLabelButton: View {
    let title: LocalizedStringKey
    let symbol: String
    let action: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Button(action: action) { Label(title, systemImage: symbol).labelStyle(.titleAndIcon).lineLimit(1) }
            Button(action: action) { Label(title, systemImage: symbol).labelStyle(.iconOnly) }
        }
        .buttonStyle(.glass).controlSize(.large)
        .font(DS.TextRecipe.footnote.font.weight(.semibold))
    }
}

/// El ícono de un renglón del panel: el símbolo del sistema en su color, sin fondo (como los renglones de Ajustes).
struct PanelIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(color)
            .frame(width: DS.PlayerPanel.icon).accessibilityHidden(true)
    }
}

/// La velocidad en un solo control: − 1× + (un toque, el paso siguiente; el valor siempre a la vista).
struct SpeedStepper: View {
    let rates: [Float]
    let rate: Float
    let set: (Float) -> Void

    var body: some View {
        let index = rates.firstIndex(of: rate) ?? rates.firstIndex(of: 1) ?? 0
        HStack(spacing: 0) {
            step("minus", enabled: index > 0) { set(rates[index - 1]) }.accessibilityLabel(Text("Más lento"))
            Text(verbatim: rate == 1 ? "1×" : String(format: "%g×", rate)).font(DS.TextRecipe.secondary.font.weight(.semibold)).monospacedDigit()
                .foregroundStyle(DS.text).frame(minWidth: DS.PlayerPanel.speedValue)
                .contentTransition(.numericText())
            step("plus", enabled: index < rates.count - 1) { set(rates[index + 1]) }.accessibilityLabel(Text("Más rápido"))
        }
        .background(DS.fill, in: Capsule())
        .sensoryFeedback(.selection, trigger: rate)
        .accessibilityElement(children: .contain)
        .accessibilityValue(Text(verbatim: String(format: "%g×", rate)))
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(DS.TextRecipe.footnote.font.weight(.bold))
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget * 3 / 4)
        }
        .buttonStyle(.plain).foregroundStyle(enabled ? DS.text : DS.textFaint).disabled(!enabled)
    }
}

/// Un renglón del panel: ícono, nombre y cómo está ahora; con `action`, lleva a su página (chevron).
struct PanelRow<Value: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    var action: (() -> Void)?
    @ViewBuilder var value: () -> Value

    var body: some View {
        let row = HStack(spacing: DS.Space.s3) {
            PanelIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.secondary, color: DS.text).fontWeight(.semibold)
                value()
            }
            Spacer(minLength: DS.Space.s2)
            if action != nil { Image(systemName: "chevron.right").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textFaint) }
        }
        .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
        .contentShape(Rectangle())
        if let action { Button(action: action) { row }.buttonStyle(.plain) } else { row }
    }
}

/// Una opción en cápsula (subtítulos, velocidad, tamaño): la elegida en papel con ✓.
struct PanelChip: View {
    let title: Text
    let selected: Bool
    var font: Font = DS.TextRecipe.footnote.font
    /// Un glifo que acompaña al texto (los ánimos de «Decide por mí»); con él, elegirlo no agrega la palomita.
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s1) {
                if let symbol {
                    Image(systemName: symbol).font(font.weight(.semibold)).symbolVariant(selected ? .fill : .none)
                } else if selected { Image(systemName: "checkmark").font(DS.TextRecipe.caption.font.weight(.bold)) }
                title.font(font).fontWeight(selected ? .semibold : .regular).lineLimit(1)
            }
            .foregroundStyle(selected ? DS.backdropDeep : DS.text)
            .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
            .background(selected ? DS.paper : DS.fill, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Un rótulo de grupo dentro del panel («Tu idioma», «Otros», «Tamaño»).
struct PanelGroupTitle: View {
    let title: LocalizedStringKey
    var body: some View { Text(title).recipe(.caption, color: DS.textMuted).textCase(.uppercase).padding(.top, DS.Space.s2) }
}

/// Chips que se acomodan en renglones (los subtítulos de un idioma, las velocidades).
struct FlowChips: Layout {
    var spacing: CGFloat = DS.Space.s2
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}

/// El aviso de la app (una sola familia): arriba, en vidrio, con su glifo de color, el texto y, si la tiene, una acción
/// («Deshacer», «Ver»). Se va solo; tocarlo lo cierra.
struct Toast: View {
    let symbol: String
    let color: Color
    let title: Text
    var detail: Text?
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?
    var seconds: UInt64 = DS.Timing.banner
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: symbol).font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.backdropDeep)
                .frame(width: DS.PlayerPanel.icon, height: DS.PlayerPanel.icon).background(color, in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                title.recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(2)
                if let detail { detail.recipe(.footnote).lineLimit(1) }
            }
            Spacer(minLength: DS.Space.s2)
            if let actionTitle, let action {
                Button(actionTitle) { action(); dismiss() }.buttonStyle(.glassProminent).tint(DS.paper).foregroundStyle(DS.backdropDeep)
            }
        }
        .padding(.leading, DS.Space.s3).padding(.trailing, DS.Space.s2).padding(.vertical, DS.Space.s2)
        .frame(minHeight: DS.PlayerPanel.icon + 2 * DS.Space.s2)
        .glassEffect(.regular, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: dismiss)
        .padding(.horizontal, DS.Space.s4)
        .task { try? await Task.sleep(nanoseconds: seconds); dismiss() }
        .accessibilityElement(children: .contain)
    }
}
