import SwiftUI
import OrbitalModels

/// La pastilla de «¿Qué tal …?» sobre la barra de pestañas, conectada a tus calificaciones (`RatingsModel`): calificar
/// desde ahí, descartar o abrir la fila completa en una hoja. Aparece al abrir la app y se va sola a los pocos segundos;
/// calificar siempre se puede en la ficha (la película, la serie y cada capítulo visto).
struct RatingReminderHost: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var showQueue = false
    /// Se va sola a los pocos segundos (para no tapar nada) y vuelve la próxima vez que abras la app.
    @State private var tucked = false
    /// El dedo en las estrellas: mientras, no corre su tiempo (se iba a media calificación).
    @State private var busy = false

    var body: some View {
        let model = env.ratings
        let _ = model.track()
        Group {
            if let item = model.current, !tucked {
                RatingReminder(title: titleName(item.title, id: item.imdb, kind: item.kind), poster: URL(string: item.poster), more: model.more,
                               onRate: { stars in Task { await model.rate(imdb: item.imdb, kind: item.kind, stars: stars) } },
                               onDismiss: { model.dismiss(item.imdb) },
                               onOpenQueue: { showQueue = true }, onBusy: { busy = $0 })
                    .id(item.imdb)
                    .frame(maxWidth: DS.Toast.maxWidth)   // en el iPad y la Mac no cruza la pantalla, como los avisos
                    .padding(.horizontal, DS.Space.gutter)
                    .transition(DS.Motion.notice(reduceMotion))
                    // Lo que mide a la vista (con su aire hasta la barra): Guardado le aparta ese lugar abajo para que no tape la
                    // última fila (GD2, 13 nov 2026). Al irse, cero.
                    .onGeometryChange(for: CGFloat.self) { $0.size.height + DS.Toast.gap } action: { report($0) }
                    .onDisappear { report(0) }
            }
        }
        .animation(DS.Motion.enter(reduceMotion), value: model.current?.imdb)
        .animation(DS.Motion.base(reduceMotion), value: tucked)
        // Cada título nuevo en la pastilla (o volver a la app) le da otra vez su tiempo; con la fila abierta no se va.
        .task(id: "\(model.current?.imdb ?? "")|\(tucked)|\(showQueue)|\(busy)") {
            guard model.current != nil, !tucked, !showQueue, !busy else { return }
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

extension RatingReminderHost {
    /// Cuánto mide la pastilla a la vista (0 si no está): `AppUI.ratingReminderHeight`.
    fileprivate func report(_ height: CGFloat) {
        if env.ui.ratingReminderHeight != height { env.ui.ratingReminderHeight = height }
    }
}

/// La pastilla en la raíz: pegada a la barra de pestañas (y encima de «Viendo en la TV» cuando está, `lift`), en el mismo
/// lugar que los avisos (`dsNoticePlacement`) y solo cuando no hay otro aviso.
struct FloatingRatingReminder: View {
    @Environment(AppEnvironment.self) private var env
    let lift: CGFloat

    var body: some View {
        if env.ui.handoff == nil, env.notices.current == nil {
            RatingReminderHost().dsNoticePlacement(lift: lift)
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
