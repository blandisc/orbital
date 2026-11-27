import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una lección abierta (desde Aprende, un aviso o un «?»): marca vista al terminarla y el botón del final lleva a la función
/// de verdad. `close` la quita de la pantalla.
struct LessonScreen: View {
    let route: LessonRoute
    let close: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let lesson = LessonCatalog.lesson(route.id) {
            LessonView(lesson: lesson, startAt: route.step, connected: env.hasWhatLessonOffers(lesson.id),
                       finish: { seen in
                           if seen { LearnModel(env.services).markSeen("lesson.\(lesson.id)") }
                           close()
                       },
                       act: { destination in Task { try? await Task.sleep(for: DS.Motion.tabSettle); env.open(destination) } })
        }
    }
}

/// El «?» donde la gente se atora (AF2-B, Fernando, 19 nov 2026): abre la lección justo en la pantalla que contesta la duda
/// y «Cerrar» te regresa adonde estabas. Solo sale si la lección existe en esta versión de Orbital.
struct LessonHelpButton: View {
    let lesson: String
    let step: Int
    let label: LocalizedStringKey
    @State private var route: LessonRoute?
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if LearnModel(env.services).lessons.contains(lesson) {
            Button { route = LessonRoute(id: lesson, step: step) } label: {
                Image(systemName: "questionmark.circle").font(DS.TextRecipe.section.font)
            }
            .buttonStyle(.plain).foregroundStyle(DS.textMuted)
            .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
            .accessibilityLabel(Text(label))
            .accessibilityIdentifier("lesson-help-\(lesson)")
            .fullScreenCover(item: $route) { r in LessonScreen(route: r) { route = nil }.environment(env).duoBars() }
        }
    }
}
