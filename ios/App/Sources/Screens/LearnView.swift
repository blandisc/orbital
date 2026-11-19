import SwiftUI
import OrbitalModels

/// Ajustes › Aprende (G3): todas las historias por tema (el punto de «nuevo» en las que no has visto), ver la guía otra vez,
/// «Volver a ver los avisos» (los avisos sobre la pantalla, desde cero) y, con tu TV, lo que se puede
/// hacer con ella. Una sola entrada en Ajustes (revisión del 11 nov: antes eran cuatro casi iguales).
struct LearnView: View {
    /// «Qué puedes hacer con la TV» (el recorrido de la TV), solo con tu Orbital prendida en Ajustes.
    let tvTutorial: (() -> Void)?
    @State private var learn: ModelObserver<LearnModel>
    @State private var confirmReset = false
    @Environment(AppEnvironment.self) private var env

    init(tvTutorial: (() -> Void)? = nil) {
        self.tvTutorial = tvTutorial
        _learn = State(wrappedValue: ModelObserver(LearnModel(AppEnvironment.shared.services)))
    }

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
                } header: { Text(group.title) }   // no-es-título: un tema de la guía
                .listRowBackground(DS.surface)
            }
            if let tvTutorial {
                Section {
                    Button(action: tvTutorial) {
                        SettingsRow(title: "Qué puedes hacer con la TV", symbol: "tv", tint: DS.ListTint.series, linked: false)
                    }
                    .accessibilityIdentifier("learn-tv-tutorial")
                }
                .listRowBackground(DS.surface)
            }
            Section {
                Button { env.ui.practiceGuide = true; env.ui.showingGuide = true } label: {
                    SettingsRow(title: "Ver la guía otra vez", symbol: "play.circle", tint: DS.ListTint.spark, linked: false)
                }
                .accessibilityIdentifier("settings-guide")
                Button { confirmReset = true } label: {
                    SettingsRow(title: "Volver a ver los avisos", symbol: "arrow.counterclockwise", tint: DS.ListTint.addon, linked: false)
                }
                .accessibilityIdentifier("learn-reset")
            } footer: { Text("Los avisos sobre la pantalla vuelven a salir, uno a la vez.") }
            .listRowBackground(DS.surface)
        }
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Aprende").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .sheet(isPresented: $confirmReset) {
            ResetTipsCard(reset: { model.reset(); confirmReset = false }, cancel: { confirmReset = false })
        }
    }
}

/// «¿Volver a ver los avisos?» como tarjeta de Orbital, no el aviso del sistema (Fernando, 18 nov 2026: «que sea una
/// tarjeta la que salga, no el aviso nativo»).
struct ResetTipsCard: View {
    let reset: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s3) {
                DSIconTile(symbol: "arrow.counterclockwise", tint: DS.ListTint.addon)
                DSSheetHeader(title: Text("¿Volver a ver los avisos?"))
            }
            Text("Los avisos sobre la pantalla vuelven a salir, uno a la vez, y las historias de Aprende vuelven a decir que no las has visto.")
                .recipe(.secondary, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: DS.Space.s2) {
                Button(action: reset) { Text("Volver a verlos").frame(maxWidth: .infinity) }
                    .dsPrimaryButton().dsControlSize(.large).accessibilityIdentifier("learn-reset-confirm")
                Button(action: cancel) { Text("Cancelar").frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted).accessibilityIdentifier("learn-reset-cancel")
            }
        }
        .dsSheetContent()
        .fittedSheet()
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
