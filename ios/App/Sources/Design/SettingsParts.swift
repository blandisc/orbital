import SwiftUI

// Piezas de Ajustes: el renglón con su ícono de color (como las listas: solo el color, sin fondo), la tarjeta de perfil y
// las vistas previas de cada estilo de Inicio (se elige viéndolo, no por su nombre).

/// Un renglón de Ajustes que lleva a su página: ícono en su color, nombre y, a la derecha, cómo está ahora.
struct SettingsRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    var value: Text?
    /// Lleva a otra página (con flecha). Sin ella, el valor se corre para quedar en la misma columna.
    var linked = true

    var body: some View {
        LabeledContent {
            if let value { value.lineLimit(1).padding(.trailing, linked ? 0 : DS.SettingsLook.chevronSlot) }
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

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
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

/// Un renglón con palomita (en qué listas está un título, «Guardar en…»): su glifo de color, el nombre y ✓ si está.
struct CheckRow: View {
    let title: Text
    let symbol: String
    let color: Color
    let checked: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s3) {
                PanelIcon(symbol: symbol, color: color)
                title.recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)   // con letra grande no se corta
                Spacer(minLength: DS.Space.s2)
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(DS.TextRecipe.title.font.weight(.regular))
                    .foregroundStyle(checked ? DS.accent : DS.textFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(DS.Space.s3)
            .frame(minHeight: DS.Size.touchTarget)   // todo el renglón se toca, nunca menos que un objetivo táctil
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: checked)
    }
}

/// De qué temporadas sale «Un Simpson al azar»: dos atajos (las clásicas, todas) y una cápsula por temporada. Siempre queda
/// al menos una (quitar la última no hace nada).
struct SimpsonsSeasonsPicker: View {
    let selected: [Int]
    let available: [Int]
    let classics: [Int]
    let change: ([Int]) -> Void

    var body: some View {
        let chosen = Set(selected)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                PanelChip(title: Text("Las clásicas (\(Int(classics.first ?? 0))–\(Int(classics.last ?? 0)))"), selected: chosen == Set(classics)) { change(classics) }
                PanelChip(title: Text("Todas"), selected: Set(available).isSubset(of: chosen)) { change(available) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Size.touchTarget + DS.Space.s4), spacing: DS.Space.s2)], spacing: DS.Space.s2) {
                ForEach(available, id: \.self) { season in
                    PanelChip(title: Text(verbatim: "\(season)"), selected: chosen.contains(season)) {
                        var next = chosen
                        if next.contains(season) { next.remove(season) } else { next.insert(season) }
                        if !next.isEmpty { change(next.sorted()) }
                    }
                    .accessibilityLabel(Text("Temporada \(season)"))
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityIdentifier("simpsons-seasons")
    }
}
