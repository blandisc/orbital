import SwiftUI

// Piezas de Ajustes: el renglón con su ícono de color (como las listas: solo el color, sin fondo), la tarjeta de perfil y
// las vistas previas de cada estilo de Inicio (se elige viéndolo, no por su nombre).

/// Un renglón de Ajustes que lleva a su página: ícono en su color, nombre y, a la derecha, cómo está ahora.
struct SettingsRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    var value: Text?

    var body: some View {
        LabeledContent {
            if let value { value.lineLimit(1) }
        } label: {
            Label {
                Text(title).foregroundStyle(DS.text)
            } icon: {
                Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(tint)
                    .frame(width: DS.SettingsLook.rowIcon)
            }
        }
    }
}

/// Arriba de Ajustes: tu avatar (con un lápiz: se ve que se toca), tu nombre y qué está conectado.
struct ProfileCard: View {
    let avatar: String
    let title: Text
    let detail: Text
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            HStack(spacing: DS.Space.s4) {
                AvatarImage(id: avatar, size: DS.SettingsLook.profileAvatar)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil").font(DS.TextRecipe.caption.font.weight(.bold)).foregroundStyle(DS.onPrimary)
                            .frame(width: DS.SettingsLook.editBadge, height: DS.SettingsLook.editBadge)
                            .background(DS.primary, in: Circle())
                    }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    title.recipe(.cardTitle).fontWeight(.semibold)
                    detail.recipe(.footnote, color: DS.textMuted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Cambiar avatar"))
    }
}

/// Una opción con su vista previa y su nombre; la elegida, con el borde del acento.
struct StyleOption<Preview: View>: View {
    let label: LocalizedStringKey
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s2) {
                preview().frame(maxWidth: .infinity).clipped()
                Text(label).recipe(.footnote, color: selected ? DS.text : DS.textMuted).fontWeight(selected ? .semibold : .regular)
            }
            .padding(DS.Space.s2)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.SettingsLook.optionRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.SettingsLook.optionRadius, style: .continuous)
                .stroke(selected ? DS.accent : .clear, lineWidth: DS.SettingsLook.optionRing))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// El carrusel en chiquito: tres tarjetas que se deslizan solas de ida y vuelta con el efecto del estilo (el mismo
/// `deckEffect` de Inicio). Con «Reducir movimiento», quietas con la del centro al frente.
struct DeckStylePreview: View {
    let style: DeckStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let art = ["genre-drama", "genre-scifi", "genre-action"]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            // De −0.6 a 0.6 lugares y de vuelta: se ve cómo pasan las de los lados al frente.
            let shift = reduceMotion ? 0 : sin(context.date.timeIntervalSinceReferenceDate * DS.SettingsLook.deckPreviewSpeed) * 0.6   // ds-exception: amplitud del vaivén, en lugares
            ZStack {
                ForEach(Array(Self.art.enumerated()), id: \.offset) { index, art in
                    let value = Double(index - 1) - shift
                    Image(art).resizable().scaledToFill()
                        .frame(width: DS.SettingsLook.deckPreviewCard.width, height: DS.SettingsLook.deckPreviewCard.height)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .deckEffect(style, value: max(-1, min(1, value)), blur: DS.SettingsLook.deckPreviewBlur, drop: DS.SettingsLook.deckPreviewDrop)
                        .offset(x: value * DS.SettingsLook.deckPreviewStep)
                        .zIndex(-abs(value))
                }
            }
            .frame(height: DS.SettingsLook.deckPreviewHeight)
        }
        .accessibilityHidden(true)
    }
}

/// Cuánto falta en chiquito: una tarjeta del tamaño real (el indicador sale igual que en Inicio), reducida.
struct TimeStylePreview: View {
    let style: TimeStyle
    private let minutes = 32, fraction = 0.62   // ds-exception: datos de muestra de la vista previa

    var body: some View {
        let card = DS.SettingsLook.timePreviewCard, scale = DS.SettingsLook.timePreviewScale
        ZStack(alignment: .bottomLeading) {
            Image("genre-drama").resizable().scaledToFill().frame(width: card.width, height: card.height).clipped()
            LinearGradient(colors: [.clear, DS.scrimStrong], startPoint: .center, endPoint: .bottom)
            if style == .fill {
                ProgressFillLabel(text: Text("Continuar"), minutes: minutes, fraction: fraction).padding(DS.Space.s4)
            }
            TimeBadge(style: style, minutes: minutes, fraction: fraction)
        }
        .frame(width: card.width, height: card.height)
        .clipShape(RoundedRectangle(cornerRadius: DS.Deck.radius, style: .continuous))
        .scaleEffect(scale)
        .frame(width: card.width * scale, height: card.height * scale)
        .accessibilityHidden(true)
    }
}

/// Un renglón con palomita (en qué listas está un título, «Guardar en…»): su glifo de color, el nombre y ✓ si está.
struct CheckRow: View {
    let title: Text
    let symbol: String
    let color: Color
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                PanelIcon(symbol: symbol, color: color)
                title.recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: DS.Space.s2)
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(DS.TextRecipe.title.font.weight(.regular))
                    .foregroundStyle(checked ? DS.accent : DS.textFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(DS.Space.s3)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: checked)
    }
}

