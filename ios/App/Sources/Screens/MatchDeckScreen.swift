import SwiftUI
import OrbitalCore
import OrbitalModels

/// «¿Qué vemos hoy?» a pantalla completa (Para ti la presenta con `.fullScreenCover`): arriba los cuatro ánimos, en medio el
/// mazo y abajo ✕ ▶ ＋. `pool`: lo que Para ti ya tiene a la mano. Tocar una carta abre su ficha (`onOpenTitle`); ▶ avisa
/// con `onPlay` para que la pantalla de afuera la reproduzca.
struct MatchDeckScreen: View {
    let pool: [Suggestion]
    let onOpenTitle: (TitleRoute) -> Void
    let onPlay: (TitleRoute) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var model: MatchDeckModel?
    /// Lo que pidió un botón (la carta sale volando igual que al arrastrarla).
    @State private var command: MatchCommand?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Eyebrow(text: Text("Encuentra tu match perfecto"), reason: true)
                DSSheetHeader(title: Text("¿Qué vemos hoy?")) {
                    // Cuántas llevas guardadas en esta vuelta (en «Tu match perfecto» de Trakt, o en Mi lista).
                    if let model, !model.saved.isEmpty {
                        Label { Text(verbatim: "\(model.saved.count)").monospacedDigit() } icon: { Image(systemName: "bookmark.fill") }
                            .recipe(.label, color: DS.text).tint(DS.brandMoon)
                            .padding(.horizontal, DS.Space.s3).frame(minHeight: DS.Size.touchTarget)
                            .background(DS.fill, in: Capsule())
                            .contentTransition(.numericText())
                            .accessibilityLabel(model.savesToTrakt ? Text("\(model.saved.count) guardadas en Tu match perfecto") : Text("\(model.saved.count) guardadas en Mi lista"))
                            .accessibilityIdentifier("match-saved-count")
                    }
                    DSIconButton(symbol: "xmark", label: "Cerrar", size: .regular) { dismiss() }
                        .accessibilityIdentifier("match-close")
                }
            }
            if let model {
                let _ = model.track()
                if !model.loaded {
                    skeleton   // mientras llega lo visto: la forma de la carta, no una pantalla en blanco
                } else if model.cards.isEmpty {
                    emptyState(model).frame(maxHeight: .infinity)
                } else {
                    MatchDeck(cards: model.cards,
                              genres: { Vocabulary.genres($0.genres, language: env.services.appSettings.uiLanguage) },
                              command: $command,
                              onSave: { s in save(s, model) },
                              onDiscard: { model.discard($0) },
                              onOpen: { s in dismiss(); onOpenTitle(s.route) })
                        .frame(maxHeight: .infinity)
                    actions(model)
                }
            } else {
                skeleton
            }
        }
        .padding(DS.Space.gutter)
        .background(Backdrop())
        .task {
            if model == nil {
                let m = MatchDeckModel(env.services, pool: pool, titles: env.titles, watched: { [env] in await env.collections.watchedIDs() })
                model = m
                await m.load()
            }
        }
        // Las cartas que siguen, pedidas de antemano: al aventar una, la de abajo ya trae su póster (antes llegaba en blanco).
        .task(id: model?.cards.prefix(DS.Match.prefetch).map(\.imdb)) {
            guard let model else { return }
            ImagePipeline.shared.prefetchPosters(model.cards.prefix(DS.Match.prefetch).map(\.poster))
        }
        .accessibilityElement(children: .contain)   // cada botón conserva su identificador
        .accessibilityIdentifier("match-deck")
    }

    /// La carta en gris mientras carga.
    private var skeleton: some View {
        RoundedRectangle(cornerRadius: DS.Radius.xxl, style: .continuous).fill(DS.fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text("Cargando"))
    }

    /// Sin cartas: si nunca hubo propuestas lo dice así; si las recorriste o el ánimo no tiene, lo dice distinto.
    @ViewBuilder private func emptyState(_ model: MatchDeckModel) -> some View {
        if pool.isEmpty {
            DSEmptyState(symbol: "rectangle.stack", title: Text("Aún no hay propuestas"), message: Text("Cuando Para ti cargue sus listas, aquí salen."))
        } else if model.mood != nil, model.saved.isEmpty {
            DSEmptyState(symbol: "face.smiling", title: Text("Nada de este ánimo"), message: Text("Prueba con otro o con todos."))
        } else {
            DSEmptyState(symbol: "rectangle.stack", title: Text("Ya viste todo el mazo"),
                         message: model.saved.isEmpty ? Text("Vuelve mañana: el mazo cambia cada día.") : (model.savesToTrakt ? Text("Guardaste \(model.saved.count). Están en tu lista de Trakt «Tu match perfecto».") : Text("Guardaste \(model.saved.count). Están en Mi lista.")))
        }
    }

    /// Guarda (en «Tu match perfecto» de Trakt o en Mi lista) y lo dice, con «Deshacer» (antes el «+» la guardaba sin avisar y no se sabía qué había pasado).
    private func save(_ s: Suggestion, _ model: MatchDeckModel) {
        Task { await model.save(s) }
        env.notify(model.savesToTrakt ? "Guardada en Tu match perfecto" : "Guardada en Mi lista", detail: s.title, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
            Task { await model.undo(s) }
        }
    }

    /// Paso · Ver ya · Guardar, cada uno con su nombre debajo; Paso y Guardar hacen salir volando la carta.
    private func actions(_ model: MatchDeckModel) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s6) {
            action(Text("Paso"), id: "match-discard") {
                DSIconButton(symbol: "xmark", label: "Paso", size: .large) { command = .discard }
                    .font(DS.TextRecipe.title.font)
            }
            action(Text("Ver ya"), id: "match-play") {
                Button { if let s = model.cards.first { dismiss(); onPlay(s.route) } } label: { Image(systemName: "play.fill").font(DS.TextRecipe.title.font) }
                    .dsSolidPrimaryButton(shape: .circle).controlSize(.large)
            }
            action(Text("Guardar"), id: "match-save") {
                DSIconButton(symbol: "bookmark.fill", label: "Guardar", size: .large) { command = .save }
                    .font(DS.TextRecipe.title.font).foregroundStyle(DS.brandMoon)
            }
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.cards.first?.imdb)
    }

    private func action(_ name: Text, id: String, @ViewBuilder button: () -> some View) -> some View {
        VStack(spacing: DS.Match.actionLabelGap) {
            button().accessibilityLabel(name).accessibilityIdentifier(id)
                .frame(height: DS.Match.actionRow)   // el mismo renglón para los tres: los nombres quedan parejos
            name.recipe(.badge, color: DS.textMuted).accessibilityHidden(true)
        }
    }

}
