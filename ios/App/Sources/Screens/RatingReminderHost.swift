import SwiftUI
import OrbitalModels

/// La tarjeta de «¿Qué tal …?» dentro del scroll de Inicio (D2-A, 10 nov 2026: antes flotaba sobre la barra de pestañas y tapaba
/// lo de abajo en todas las pantallas), conectada a tus calificaciones (`RatingsModel`): calificar desde ahí, descartar o abrir
/// la fila completa en una hoja. Se queda en su lugar hasta que calificas o la cierras; calificar siempre se puede en la ficha.
struct RatingReminderHost: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQueue = false

    var body: some View {
        let model = env.ratings
        let _ = model.track()
        Group {
            if let item = model.current {
                RatingReminder(title: titleName(item.title, id: item.imdb, kind: item.kind), poster: URL(string: item.poster), more: model.more,
                               onRate: { stars in Task { await model.rate(imdb: item.imdb, kind: item.kind, stars: stars) } },
                               onDismiss: { model.dismiss(item.imdb) },
                               onOpenQueue: { showQueue = true })
                    .id(item.imdb)
                    .frame(maxWidth: DS.Toast.maxWidth, alignment: .leading)   // en el iPad y la Mac no cruza la pantalla
                    .padding(.horizontal, DS.Space.gutter)
                    .transition(DS.Motion.appear(reduceMotion))
            }
        }
        .animation(DS.Motion.enter(reduceMotion), value: model.current?.imdb)
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

/// Dentro del accesorio de la barra («Viendo en la TV»): avisa si va encima de la barra o a su lado (barra minimizada).
struct AccessoryPlacementReport: ViewModifier {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    func body(content: Content) -> some View {
        content.onChange(of: placement, initial: true) { _, now in AppEnvironment.shared.ui.tvAccessoryInline = now == .inline }
    }
}
