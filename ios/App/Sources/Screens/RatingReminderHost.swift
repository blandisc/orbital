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
        .appSheet(isPresented: $showQueue) {
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
        // Tampoco encima de una barra de abajo: en el Duo tapaba «Quitar» al elegir varios (27 nov 2026).
        if env.ui.handoff == nil, env.notices.current == nil, env.ui.bottomBars == 0 {
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

/// «¿Qué tal…?» flota abajo, encima de lo que haya: cada pestaña le aparta su alto al final (GD2, en Biblioteca desde el 9 nov;
/// en todas desde el 27 nov 2026: en el Duo cerrado tapaba la última fila de Ajustes y los botones de la ficha). Es espacio
/// seguro, no un margen: solo lo toma la lista de la pantalla, no los carruseles de adentro.
struct RatingReminderRoom: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    /// Lo que ya aparta la pantalla abajo (la barra de pestañas en el iPhone; casi nada en el iPad y la Mac, que la llevan arriba).
    @State private var below: CGFloat = 0

    func body(content: Content) -> some View {
        let height = env.ui.ratingReminderHeight
        // La pastilla flota a `DS.Toast.clearance` de la orilla (`dsNoticePlacement`): si la pantalla aparta menos que eso abajo
        // (iPad y Mac), se suma la diferencia; si no, en el iPad tapaba la última fila (revisión del 27 nov 2026).
        let extra = height > 0 && !WindowMetrics.sideBars ? max(0, DS.Toast.clearance - below) : 0
        content.safeAreaPadding(.bottom, height + extra)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom.rounded() } action: { if $0 != below { below = $0 } }
    }
}

/// Una barra de abajo (elegir varios, «Siguiente»): mientras se ve, «¿Qué tal…?» no flota encima de ella.
struct HoldsBottomBar: ViewModifier {
    func body(content: Content) -> some View {
        content.onAppear { AppEnvironment.shared.ui.bottomBars += 1 }
            .onDisappear { AppEnvironment.shared.ui.bottomBars = max(0, AppEnvironment.shared.ui.bottomBars - 1) }
    }
}

extension View {
    func ratingReminderRoom() -> some View { modifier(RatingReminderRoom()) }
    /// Receta: toda barra de abajo de una pantalla (no de una hoja) la lleva.
    func holdsBottomBar() -> some View { modifier(HoldsBottomBar()) }
}
