import SwiftUI
import OrbitalModels

/// Ajustes › Aprende Orbital (G3): todas las historias por tema (el punto de «nuevo» en las que no has visto), ver la guía
/// otra vez y «Volver a ver los avisos» (los avisos sobre la pantalla y los círculos de Inicio, desde cero).
struct LearnView: View {
    @State private var learn: ModelObserver<LearnModel>
    @State private var confirmReset = false
    @Environment(AppEnvironment.self) private var env

    init() { _learn = State(wrappedValue: ModelObserver(LearnModel(AppEnvironment.shared.services))) }

    private static let groups: [(title: LocalizedStringKey, ids: [String])] = [
        ("Para empezar", ["instant", "language"]),
        ("Cada día", ["discover", "watch", "thread"]),
        ("Con tu TV", ["tv"]),
    ]

    var body: some View {
        let model = learn.model
        let byID = Dictionary(model.stories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        List {
            ForEach(Self.groups, id: \.ids) { group in
                Section {
                    ForEach(group.ids.compactMap { byID[$0] }) { story in
                        Button { env.ui.openStory = story.id } label: {
                            LabeledContent {
                                if !model.seen(story.id) {
                                    Circle().fill(DS.fresh).frame(width: DS.Space.s2, height: DS.Space.s2).accessibilityLabel(Text("Sin ver"))
                                }
                            } label: {
                                Label { Text(LocalizedStringKey(story.title)).recipe(.body, color: DS.text) } icon: {
                                    DSIconTile(symbol: story.symbol, tint: DS.ListTint.named(story.tint), side: DS.SettingsLook.rowIcon)
                                }
                            }
                        }
                        .accessibilityIdentifier("learn-\(story.id)")
                    }
                } header: { Text(group.title) }
                .listRowBackground(DS.surface)
            }
            Section {
                Button { env.ui.showingGuide = true } label: {
                    SettingsRow(title: "Ver la guía otra vez", symbol: "play.circle", tint: DS.ListTint.spark, linked: false)
                }
                .accessibilityIdentifier("settings-guide")
                Button { confirmReset = true } label: {
                    SettingsRow(title: "Volver a ver los avisos", symbol: "arrow.counterclockwise", tint: DS.ListTint.addon, linked: false)
                }
                .accessibilityIdentifier("learn-reset")
            } footer: { Text("Los avisos sobre la pantalla y los círculos de Inicio vuelven a salir, uno a la vez.") }
            .listRowBackground(DS.surface)
        }
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Aprende Orbital").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .confirmationDialog("¿Volver a ver los avisos?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Volver a verlos") { model.reset() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Las historias vuelven a decir que no las has visto.") }
    }
}

/// Arriba de Inicio, si la guía quedó a medias hace más de un día: la invitación a terminarla (sin obligar). Los círculos de
/// «Aprende» viven en el encabezado (`HomeHeader`).
struct HomeLearnTop: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if OnboardingModel.unfinished(env.services) {
            HStack(spacing: DS.Space.s3) {
                DSIconTile(symbol: "sparkles", tint: DS.ListTint.spark)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Termina de preparar Orbital").recipe(.cardTitle, color: DS.text)
                    Text("Te faltan unos pasos de la guía.").recipe(.secondary, color: DS.textMuted)
                }
                Spacer(minLength: 0)
                Button("Seguir") { env.ui.showingGuide = true }.dsGlassButton()
                    .accessibilityIdentifier("home-finish-guide")
            }
            .padding(DS.Space.s4)
            .dsCard()
            .padding(.horizontal, DS.Space.gutter)
        }
    }
}
