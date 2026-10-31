import SwiftUI
import OrbitalCore
import OrbitalModels

extension TitleView {
    /// «Ya la vi» en la fila de una película: abre «¿Cuándo la viste?»; vista, queda encendida y ofrece verla otra vez o
    /// quitarla.
    func watchedAction(_ model: TitleModel) -> some View {
        let seen = model.isWatched(.movie)
        return Button { marking = .movie } label: {
            ActionTileLabel(title: seen ? Text("Vista") : Text("Ya la vi"), symbol: seen ? "checkmark.circle.fill" : "checkmark.circle", active: seen, tint: artAccent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("title-watched")
    }
}

/// La hoja «¿Cuándo la viste?» de la ficha: arma qué se marca (película, episodio, temporada o serie), su fecha de estreno
/// y cuántos episodios anteriores faltan, y hace lo elegido.
struct TitleWatchedWhen: ViewModifier {
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
        case .movie, .series: Text(verbatim: model.title)
        case .episode(let id): Text(verbatim: "\(model.title) · \(code(id))")
        case .season(let s): Text("\(model.title) · Temporada \(s)")
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
