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
                    Text("Encuentra tu match perfecto").recipe(.eyebrow, color: DS.eyebrow)
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
                if model.cards.isEmpty, model.loaded {
                    ContentUnavailableView {
                        Label("Ya viste todo el mazo", systemImage: "rectangle.stack")
                    } description: {
                        model.saved.isEmpty ? Text("Cambia de ánimo o vuelve mañana.") : Text("Guardaste \(model.saved.count). Están en tu lista.")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    MatchDeck(cards: model.cards,
                              onSave: { s in Task { await model.save(s) } },
                              onDiscard: { model.discard($0) },
                              onOpen: { s in dismiss(); onOpenTitle(s.route) })
                        .frame(maxHeight: .infinity)
                    actions(model)
                }
            } else {
                Spacer()
            }
        }
        .padding(DS.Space.gutter)
        .background(Backdrop())
        .task {
            if model == nil {
                let m = MatchDeckModel(env.services, pool: pool, watched: { [env] in await env.collections.watchedIDs() })
                model = m
                await m.load()
            }
        }
        .accessibilityIdentifier("match-deck")
    }

    private func actions(_ model: MatchDeckModel) -> some View {
        HStack(spacing: DS.Space.s6) {
            Button { if let s = model.cards.first { model.discard(s) } } label: { Image(systemName: "xmark").font(DS.TextRecipe.title.font) }
                .buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                .accessibilityLabel(Text("Descartar")).accessibilityIdentifier("match-discard")
            Button { if let s = model.cards.first { dismiss(); onPlay(s.route) } } label: { Image(systemName: "play.fill").font(DS.TextRecipe.title.font) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle).controlSize(.large).tint(DS.solidPrimary).foregroundStyle(DS.onSolidPrimary)
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
