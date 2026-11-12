import SwiftUI
import OrbitalCore
import OrbitalModels

/// F1 (Fernando, 12 nov 2026: «Me gusta la F1»): el mosaico «Vista» de la fila de acciones. En una película marca la película;
/// en una serie pregunta qué (este episodio, la temporada o toda la serie) y desde ahí se califica la temporada. Antes eran dos
/// círculos junto al selector de temporada y la opción «Vista» del menú de «Guardar». docs/ios-interfaz.md § «Las acciones de
/// un título».
extension TitleView {
    /// Se puede marcar algo: una película siempre; una serie, cuando la temporada elegida tiene episodios.
    func canMarkWatched(_ model: TitleModel) -> Bool { model.kind != "series" || model.seasonProgress.total > 0 }

    func watchedAction(_ model: TitleModel) -> some View {
        let series = model.kind == "series"
        let done = model.isWatched(series ? .series : .movie)
        // Toda vista: el ícono lleno y en verde, como el ✓ de antes junto a la temporada.
        let label = ActionTileLabel(title: Text("Vista"), symbol: done ? DS.Symbol.watchedFill : DS.Symbol.watched, active: done, tint: done ? DS.success : artAccent)
        return Group {
            if series {
                Menu { watchedMenu(model) } label: { label }
            } else {
                Button { marking = .movie } label: { label }
            }
        }
        .menuStyle(.button).buttonStyle(.plain)
        .accessibilityLabel(Text("Marcar como vista"))
        .accessibilityValue(done ? Text("Vista") : Text(verbatim: ""))
        .accessibilityIdentifier("title-watched")
    }

    /// Qué marcar en una serie: el episodio que toca, la temporada elegida o toda la serie; y calificar la temporada.
    @ViewBuilder private func watchedMenu(_ model: TitleModel) -> some View {
        let season = model.selectedSeason
        let progress = model.seasonProgress
        let specials = model.seasons.first { $0.season == season }?.isSpecials == true
        Section {
            if let episode = model.continueVideoID, let code = model.episodeLabel(episode) {
                Button { marking = .episode(episode) } label: {
                    Text("Este episodio"); Text(verbatim: code)
                    Image(systemName: model.isWatched(.episode(episode)) ? DS.Symbol.done : DS.Symbol.watched)
                }
                .accessibilityIdentifier("title-watched-episode")
            }
            Button { marking = .season(season) } label: {
                specials ? Text("Especiales") : Text("Temporada \(season)")
                Text("\(progress.watched) de \(progress.total) vistos")
                Image(systemName: progress.total > 0 && progress.watched == progress.total ? DS.Symbol.done : "rectangle.stack")
            }
            .accessibilityIdentifier("title-watched-season")
            Button { marking = .series } label: {
                Label("Toda la serie", systemImage: model.isWatched(.series) ? DS.Symbol.done : "checkmark.rectangle.stack")
            }
            .accessibilityIdentifier("title-watched-series")
        }
        // G7-A: tus estrellas de la temporada (con Trakt y algo visto de ella). Antes iban bajo «3 de 22 vistos»; F1: una sola
        // fila de estrellas a la vista (la de la serie), y la de la temporada desde aquí.
        if canRateSeason(model) {
            Section {
                Button { ratingSeason = season } label: {
                    Text("Calificar la temporada")
                    Image(systemName: DS.Symbol.rate)
                }
                .accessibilityIdentifier("title-watched-rate-season")
            }
        }
    }

    func canRateSeason(_ model: TitleModel) -> Bool {
        model.canFavorite && model.seasonProgress.watched > 0 && model.seasons.first(where: { $0.season == model.selectedSeason })?.isSpecials != true
    }
}

/// La hoja «¿Cuándo la viste?» de la ficha: arma qué se marca (película, episodio, temporada o serie), su fecha de estreno
/// y cuántos episodios anteriores faltan, y hace lo elegido.
struct TitleWatchedWhen: ViewModifier {
    @Environment(\.titleName) var titleName
    let model: TitleModel
    @Binding var scope: WatchedScope?
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.sheet(item: $scope) { scope in
            let language = env.services.appSettings.uiLanguage
            let span = model.releaseSpan(scope)
            let day = { (d: Date) in Strings.longDay(d, language: language) }
            let releaseDetail: Text? = span.map { $0.first == $0.last || scope == .movie ? Text(verbatim: day($0.first)) : Text(verbatim: "\(day($0.first)) – \(day($0.last))") }
            let earlier: Int = { if case .episode(let id) = scope, !model.isWatched(scope) { return model.earlierUnwatched(than: id).count }; return 0 }()
            WatchedWhenSheet(title: title(scope), detail: detail(scope), poster: model.poster, releaseTitle: releaseTitle(scope), releaseDetail: releaseDetail,
                             alreadyWatched: model.isWatched(scope), earlier: earlier, language: language,
                             pick: { when, alsoEarlier in Task { await model.markWatched(scope, when: when, alsoEarlier: alsoEarlier); env.collections.forgetWatched() } },
                             again: { Task { await model.markWatchedAgain(scope) } },
                             remove: {
                                 Task {
                                     await model.unmarkWatched(scope)
                                     for id in model.videos(in: scope) { env.watching.forget(metaID: model.metaID, videoID: id) }
                                     env.collections.forgetWatched()
                                 }
                             })
        }
    }

    private func title(_ scope: WatchedScope) -> Text {
        switch scope {
        case .movie, .series: Text(verbatim: titleName(model.title, id: model.metaID, kind: model.kind))
        case .episode(let id): Text(verbatim: "\(titleName(model.title, id: model.metaID, kind: model.kind)) · \(code(id))")
        case .season(let s): Text("\(titleName(model.title, id: model.metaID, kind: model.kind)) · Temporada \(s)")
        }
    }

    private func detail(_ scope: WatchedScope) -> Text {
        switch scope {
        case .movie: Text(verbatim: model.info.year)
        case .episode(let id): Text(verbatim: model.seasons.lazy.flatMap(\.episodes).first { $0.id == id }?.title ?? "")
        case .season, .series: model.videos(in: scope).count == 1 ? Text("1 episodio") : Text("\(model.videos(in: scope).count) episodios")
        }
    }

    private func releaseTitle(_ scope: WatchedScope) -> Text {
        switch scope {
        case .movie: Text("El día que se estrenó")
        case .episode: Text("El día que salió")
        case .season, .series: Text("Cuando salió cada episodio")
        }
    }

    /// «T2 E5» de un video «tt…:2:5».
    private func code(_ id: String) -> String {
        let p = id.split(separator: ":").compactMap { Int($0) }
        return p.count >= 2 ? "T\(p[p.count - 2]) E\(p[p.count - 1])" : ""
    }
}
