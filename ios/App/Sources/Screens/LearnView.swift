import SwiftUI
import OrbitalModels

/// Ajustes › Aprende: las cinco lecciones a fondo (AF4-B, 19 nov 2026; el punto de «nuevo» en las que no has visto), ver la
/// guía otra vez, «Volver a ver los avisos» (los avisos sobre la pantalla, desde cero) y, con tu TV, lo que se puede hacer con
/// ella. Una sola entrada en Ajustes (revisión del 11 nov: antes eran cuatro casi iguales).
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

    var body: some View {
        let model = learn.model
        List {
            Section {
                ForEach(model.lessons.compactMap(LessonCatalog.lesson)) { lesson in
                    Button { env.ui.openLesson = LessonRoute(id: lesson.id) } label: { LessonRowLabel(lesson: lesson, seen: model.seen("lesson.\(lesson.id)")) }
                        .accessibilityIdentifier("learn-\(lesson.id)")
                }
            } header: { Text("Lecciones") } footer: {   // no-es-título: el grupo de las lecciones
                Text("Unos dos minutos cada una. Avanzas tú y al final lo pruebas, sin tocar tus cuentas.")
            }
            .listRowBackground(DS.surface)
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
                    SettingsRow(title: "Volver a ver los avisos", symbol: "arrow.clockwise", tint: DS.ListTint.addon, linked: false)
                }
                .accessibilityIdentifier("learn-reset")
            } footer: { Text("Los avisos sobre la pantalla vuelven a salir, uno a la vez.") }
            .listRowBackground(DS.surface)
        }
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Aprende").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .appSheet(isPresented: $confirmReset) {
            ResetTipsCard(reset: { model.reset(); confirmReset = false }, cancel: { confirmReset = false })
        }
    }
}

/// Una lección en la lista de Aprende: su ícono en su color, su nombre, de qué trata y, a la derecha, el punto de «nuevo» si
/// no la has visto o la palomita si ya.
struct LessonRowLabel: View {
    let lesson: Lesson
    let seen: Bool

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            DSIconTile(symbol: lesson.symbol, tint: DS.ListTint.named(lesson.tint), side: DS.Lesson.rowIcon)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(LocalizedStringKey(lesson.title)).recipe(.body, color: DS.text)   // no-es-título: el nombre de la lección
                Text(LocalizedStringKey(lesson.blurb)).recipe(.footnote, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.s2)
            if seen {
                Image(systemName: "checkmark").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted).accessibilityLabel(Text("Vista"))
            } else {
                Circle().fill(DS.fresh).frame(width: DS.Space.s2, height: DS.Space.s2).accessibilityLabel(Text("Sin ver"))
            }
        }
        .padding(.vertical, DS.Space.s1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// «¿Volver a ver los avisos?» como tarjeta de Orbital, no el aviso del sistema (Fernando, 18 nov 2026: «que sea una
/// tarjeta la que salga, no el aviso nativo»).
struct ResetTipsCard: View {
    let reset: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s2) {
                DSIconTile(symbol: "arrow.clockwise", tint: DS.ListTint.addon)
                DSSheetHeader(title: Text("¿Volver a ver los avisos?"))
            }
            Text("Los avisos sobre la pantalla vuelven a salir, uno a la vez, y las lecciones de Aprende vuelven a decir que no las has visto.")
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
            HStack(spacing: DS.Space.s2) {
                DSIconTile(symbol: DS.Symbol.learn, tint: DS.ListTint.spark)
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
