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

/// «Un Simpson al azar»: de qué temporadas sale el episodio, con lo guardado en Ajustes. La misma pieza en Ajustes y en la hoja
/// que abre la dona de Inicio (déjala picada › Temporadas…). Las temporadas que existen llegan de Cinemeta al abrirla.
struct SimpsonsSeasonsSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selected = AppEnvironment.shared.services.appSettings.simpsonsSeasons
    @State private var available = Array(1...AppEnvironment.simpsonsKnownSeasons)
    /// Cómo se guarda (Ajustes lo pasa por su modelo para que su renglón se ponga al día); sin él, directo a los ajustes.
    var save: (([Int]) -> Void)?

    var body: some View {
        Section {
            SimpsonsSeasonsPicker(selected: selected, available: available, classics: AppEnvironment.simpsonsClassics) { seasons in
                selected = seasons
                if let save { save(seasons) } else { env.services.settings.update { $0.simpsonsSeasons = seasons }; env.services.settingsDidChange() }
                env.simpsonsSeasonsChanged()
            }
            .padding(.vertical, DS.Space.s2)
            .task { available = await env.simpsonsSeasonNumbers() }
        } header: { Text("Temporadas") } footer: { Text("La dona de Inicio elige un episodio de estas temporadas.") }
        .listRowBackground(DS.surface)
    }

    /// Lo elegido en pocas palabras, para el renglón de Ajustes: «Las clásicas», «Temporada 4» o «12 temporadas».
    static func summary(_ seasons: [Int]) -> Text {
        if Set(seasons) == Set(AppEnvironment.simpsonsClassics) { return Text("Las clásicas") }
        if seasons.count == 1, let only = seasons.first { return Text("Temporada \(only)") }
        return Text("\(seasons.count) temporadas")
    }
}

/// La hoja de la dona de Inicio (déjala picada › Temporadas…): las mismas temporadas que en Ajustes.
struct SimpsonsSeasonsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form { SimpsonsSeasonsSection() }
                .tint(DS.accent)
                .scrollContentBackground(.hidden).background(Backdrop())
                .navigationTitle("Un Simpson al azar").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
