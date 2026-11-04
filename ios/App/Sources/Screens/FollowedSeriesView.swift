import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes › Avisos › «Series que sigues»: todas las series que has visto en Trakt, cada una con su interruptor. Apagada,
/// ya no sale en tus estrenos ni te avisa (lo mismo que «Siguiendo» en su ficha, que se guarda en Trakt). Fernando, 2 nov
/// 2026: «que pudiera editar dentro de la aplicación qué series sigo y qué no, porque me llegan notificaciones de series que
/// ya no me interesan».
///
/// «Esconder» (SS1-A, Fernando, 3 nov 2026: «Vamos con SS1A»): deslizar el renglón (o su menú, con el puntero o el teclado en
/// el iPad y la Mac) la esconde en Trakt: sale de aquí, de tus estrenos, de «Sigue viendo» y de los avisos, con «Deshacer».
/// Lo que viste se queda. Al final, «Escondidas» para mostrarlas otra vez.
struct FollowedSeriesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var query = ""

    var body: some View {
        let follow = env.follow
        let _ = follow.track()
        let shown = follow.visibleSeries.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
        let hiddenCount = follow.hiddenSeries.count
        List {
            if follow.series.isEmpty && hiddenCount == 0 {
                if follow.loadingSeries { DSLoadingState().listRowBackground(Color.clear) }
                else if let problem = follow.seriesProblem { Text(problem).recipe(.footnote).listRowBackground(Color.clear) }
                else { Text("Todavía no has visto series en Trakt.").recipe(.footnote).listRowBackground(Color.clear) }
            } else {
                Section {
                    ForEach(shown, id: \.imdb) { row(follow, $0) }
                } footer: {
                    Text("Escóndela y deja de salir aquí, en tus estrenos y en Sigue viendo. Lo que viste se queda.")
                }
                .listRowBackground(DS.surface)
                if hiddenCount > 0 {
                    Section {
                        NavigationLink { HiddenSeriesView() } label: { Text("Escondidas · \(hiddenCount)").recipe(.cardTitle) }
                    }
                    .listRowBackground(DS.surface)
                }
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
            SeriesLabel(imdb: show.imdb, name: name)
        }
        .accessibilityLabel(Text(verbatim: name))
        // Touch: deslizar. Puntero y teclado (iPad, Mac): el menú del renglón. VoiceOver: su acción.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Esconder", systemImage: "eye.slash") { hide(follow, show.imdb) }.tint(DS.danger)   // rojo, como los demás deslizables
        }
        .contextMenu { Button("Esconder", systemImage: "eye.slash") { hide(follow, show.imdb) } }
        .accessibilityAction(named: Text("Esconder")) { hide(follow, show.imdb) }
    }

    /// Se va al momento; el aviso ofrece «Deshacer». Sus avisos que ya llegaron (o esperaban la mañana) también se van.
    private func hide(_ follow: FollowModel, _ imdb: String) {
        Task {
            if let problem = await follow.hide(imdb) { env.notify(problem, tone: .error); return }
            await ReleaseNotifier.forget(imdb)
            env.notify("Escondida", tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
                Task { if let problem = await follow.undoHide() { env.notify(problem, tone: .error) } }
            }
        }
    }
}

/// «Escondidas»: las series que escondiste (aquí, en la TV o en trakt.tv), cada una con «Mostrar otra vez».
struct HiddenSeriesView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let follow = env.follow
        let _ = follow.track()
        let hidden = follow.hiddenSeries
        List {
            if hidden.isEmpty {
                Text("No has escondido ninguna serie.").recipe(.footnote).listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(hidden, id: \.imdb) { show in
                        let name = Strings.tr(show.title, language: env.services.appSettings.uiLanguage)
                        HStack(spacing: DS.Space.s3) {
                            SeriesLabel(imdb: show.imdb, name: name)
                            Spacer(minLength: DS.Space.s2)
                            Button {
                                Task { if let problem = await follow.unhide(show.imdb) { env.notify(problem, tone: .error) } }
                            } label: { Text("Mostrar otra vez").recipe(.footnote) }
                            .buttonStyle(.borderless)
                        }
                    }
                } footer: {
                    Text("Vuelve a tu lista, a tus estrenos y a Sigue viendo.")
                }
                .listRowBackground(DS.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Backdrop())
        .navigationTitle(Text("Escondidas")).navigationBarTitleDisplayMode(.inline)
        .refreshable { await follow.loadSeries() }
    }
}

/// El póster chico y el nombre de una serie (los renglones de «Series que sigues» y de «Escondidas»).
private struct SeriesLabel: View {
    let imdb: String
    let name: String

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: String(format: ForYou.metahubPoster, imdb), title: name, maxPoints: DS.Decide.listPoster)
                .frame(width: DS.Decide.listPoster)
            Text(verbatim: name).recipe(.cardTitle).lineLimit(2)
        }
    }
}
