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

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Eyebrow(text: Text("Encuentra tu match perfecto"), reason: true)
                    Text("¿Qué vemos hoy?").recipe(.title)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.glass).buttonBorderShape(.circle)
                    .accessibilityLabel(Text("Cerrar")).accessibilityIdentifier("match-close")
            }
            if let model {
                let _ = model.track()
                HStack(spacing: DS.Space.s2) {
                    ForEach(DecideModel.Mood.allCases, id: \.self) { mood in
                        MoodTile(symbol: Self.symbol(mood), title: Self.name(mood), selected: model.mood == mood) { model.mood = model.mood == mood ? nil : mood }
                    }
                }
                if !model.loaded {
                    skeleton   // mientras llega lo visto: la forma de la carta, no una pantalla en blanco
                } else if model.cards.isEmpty {
                    emptyState(model).frame(maxHeight: .infinity)
                } else {
                    MatchDeck(cards: model.cards,
                              onSave: { s in Task { await model.save(s) } },
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
                         message: model.saved.isEmpty ? Text("Vuelve mañana: el mazo cambia cada día.") : Text("Guardaste \(model.saved.count). Están en Mi lista."))
        }
    }

    private func actions(_ model: MatchDeckModel) -> some View {
        HStack(spacing: DS.Space.s6) {
            Button { if let s = model.cards.first { model.discard(s) } } label: { Image(systemName: "xmark").font(DS.TextRecipe.title.font) }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .accessibilityLabel(Text("Descartar")).accessibilityIdentifier("match-discard")
            Button { if let s = model.cards.first { dismiss(); onPlay(s.route) } } label: { Image(systemName: "play.fill").font(DS.TextRecipe.title.font) }
                .dsSolidPrimaryButton(shape: .circle).controlSize(.large)
                .accessibilityLabel(Text("Ver")).accessibilityIdentifier("match-play")
            Button { if let s = model.cards.first { Task { await model.save(s) } } } label: { Image(systemName: "plus").font(DS.TextRecipe.title.font) }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .accessibilityLabel(Text("Guardar")).accessibilityIdentifier("match-save")
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: model.cards.first?.imdb)
    }

    static func symbol(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "sun.max"; case .intense: "bolt"; case .think: "lightbulb"; case .together: "heart" }
    }
    static func name(_ m: DecideModel.Mood) -> Text {
        switch m { case .light: Text("Ligero"); case .intense: Text("Intenso"); case .think: Text("Para pensar"); case .together: Text("En pareja") }
    }
}
