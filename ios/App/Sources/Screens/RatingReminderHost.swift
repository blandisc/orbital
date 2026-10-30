import SwiftUI
import OrbitalModels

/// La pastilla de «¿Qué tal …?» sobre la barra de pestañas, conectada a tus calificaciones (`RatingsModel`): calificar
/// desde ahí, descartar o abrir la fila completa en una hoja.
struct RatingReminderHost: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQueue = false

    var body: some View {
        let model = env.ratings
        let _ = model.track()
        Group {
            if let item = model.current {
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
