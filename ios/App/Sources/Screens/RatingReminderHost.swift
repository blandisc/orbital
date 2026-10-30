import SwiftUI
import OrbitalModels

/// La pastilla de «¿Qué tal …?» sobre la barra de pestañas, conectada a tus calificaciones (`RatingsModel`): calificar
/// desde ahí, descartar o abrir la fila completa en una hoja. Aparece al abrir la app y se va sola a los pocos segundos;
/// calificar siempre se puede en la ficha (la película, la serie y cada capítulo visto).
struct RatingReminderHost: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showQueue = false
    /// Se va sola a los pocos segundos (para no tapar nada) y vuelve la próxima vez que abras la app.
    @State private var tucked = false

    var body: some View {
        let model = env.ratings
        let _ = model.track()
        Group {
            if let item = model.current, !tucked {
                RatingReminder(title: item.title, poster: URL(string: item.poster), more: model.more,
                               onRate: { stars in Task { await model.rate(imdb: item.imdb, kind: item.kind, stars: stars) } },
                               onDismiss: { model.dismiss(item.imdb) },
                               onOpenQueue: { showQueue = true })
                    .id(item.imdb)
                    .padding(.horizontal, DS.Space.gutter)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(DS.Motion.base(reduceMotion), value: model.current?.imdb)
        .animation(DS.Motion.base(reduceMotion), value: tucked)
        // Cada título nuevo en la pastilla (o volver a la app) le da otra vez su tiempo; con la fila abierta no se va.
        .task(id: "\(model.current?.imdb ?? "")|\(tucked)|\(showQueue)") {
            guard model.current != nil, !tucked, !showQueue else { return }
            try? await Task.sleep(for: DS.Rating.reminderHold)
            if !Task.isCancelled { tucked = true }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { tucked = false } }
        .sheet(isPresented: $showQueue) {
            NavigationStack {
                RatingQueue(rows: model.queue.map { .init(id: $0.imdb, title: $0.title, poster: URL(string: $0.poster)) },
                            onRate: { imdb, stars in
                                let kind = model.queue.first { $0.imdb == imdb }?.kind ?? "movie"
                                Task { await model.rate(imdb: imdb, kind: kind, stars: stars) }
                            },
                            onDismiss: { model.dismiss($0) })
            }
            .presentationDetents([.medium, .large])
        }
    }
}
