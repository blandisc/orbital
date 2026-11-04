import SwiftUI
import OrbitalModels

/// Un aviso sobre la pantalla de «Aprende» (F3) en una pantalla: pregunta a `LearnModel` si toca (nunca el mismo día de la
/// guía, uno cada vez que abres la app, nunca si ya usaste la función), lo enseña y lo cierra. «Ver la historia» abre la de
/// esa función. Lo que señala lleva `.coachAnchor(id.rawValue)`.
struct LearnCoach: ViewModifier {
    let id: LearnModel.CoachID
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var used = false
    @State private var showing = false
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content
            .coachHost(showing ? CoachContent(id: id.rawValue, title: title, detail: detail, spotlight: id.spotlight) : nil,
                       story: { showing = false; env.ui.openStory = id.story },
                       done: { showing = false },
                       skipAll: { LearnModel(env.services).skipAllCoach(); showing = false })
            .task {
                try? await Task.sleep(for: DS.Coach.wait)
                guard !Task.isCancelled else { return }
                let learn = LearnModel(env.services)
                guard learn.shouldCoach(id.rawValue, used: used) else { return }
                learn.coached(id.rawValue)
                showing = true
            }
    }
}

extension View {
    func learnCoach(_ id: LearnModel.CoachID, title: LocalizedStringKey, detail: LocalizedStringKey, used: Bool = false) -> some View {
        modifier(LearnCoach(id: id, title: title, detail: detail, used: used))
    }
}
