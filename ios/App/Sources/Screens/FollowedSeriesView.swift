import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes › Avisos › «Series que sigues»: todas las series que has visto en Trakt, cada una con su interruptor. Apagada,
/// ya no sale en tus estrenos ni te avisa (lo mismo que «Siguiendo» en su ficha, que se guarda en Trakt). Fernando, 2 nov
/// 2026: «que pudiera editar dentro de la aplicación qué series sigo y qué no, porque me llegan notificaciones de series que
/// ya no me interesan».
struct FollowedSeriesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    var body: some View {
        let follow = env.follow
        let _ = follow.track()
        let shown = follow.series.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
        List {
            if follow.series.isEmpty {
                if follow.loadingSeries { DSLoadingState().listRowBackground(Color.clear) }
                else if let problem = follow.seriesProblem { Text(problem).recipe(.footnote).listRowBackground(Color.clear) }
                else { Text("Todavía no has visto series en Trakt.").recipe(.footnote).listRowBackground(Color.clear) }
            } else {
                Section {
                    ForEach(shown, id: \.imdb) { row(follow, $0) }
                } footer: {
                    Text("Apagada, ya no sale en tus estrenos ni te avisa. Lo que viste no cambia; la vuelves a prender aquí o en su ficha.")
                }
                .listRowBackground(DS.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Backdrop())
        .searchable(text: $query, prompt: Text("Buscar una serie"))
        .navigationTitle(Text("Series que sigues")).navigationBarTitleDisplayMode(.inline)
        .task { await follow.loadSeries() }
        .refreshable { await follow.loadSeries() }
    }

    private func row(_ follow: FollowModel, _ show: TraktWatchedTitle) -> some View {
        let name = Strings.tr(show.title, language: env.services.appSettings.uiLanguage)
        return Toggle(isOn: Binding(get: { follow.isFollowing(show.imdb) }, set: { on in
            Task { if let problem = await follow.setFollowing(show.imdb, on) { env.notify(problem, tone: .error) } }
        })) {
            HStack(spacing: DS.Space.s3) {
                PosterView(url: String(format: ForYou.metahubPoster, show.imdb), title: name, maxPoints: DS.Decide.listPoster)
                    .frame(width: DS.Decide.listPoster)
                Text(verbatim: name).recipe(.cardTitle).lineLimit(2)
            }
        }
        .accessibilityLabel(Text(verbatim: name))
    }
}
