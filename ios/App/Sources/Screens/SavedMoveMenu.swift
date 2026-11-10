import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Mover a…» (G2-A, Fernando, 9 nov 2026: «Completa todos los pendientes»): mantener el dedo sobre un póster del tablero de
/// Guardado lo pasa a otro estado sin abrir su ficha, con «Deshacer». Las mismas palabras del botón de estado de la ficha.
/// Con teclado y puntero: clic secundario. En la TV: pendiente en el registro de paridad.
struct SavedMoveMenu: View {
    /// Opcional: el menú contextual puede pintarse fuera del árbol que trae el entorno (`ToolbarEnvironmentTests`).
    @Environment(AppEnvironment.self) private var maybeEnv: AppEnvironment?
    private var env: AppEnvironment { maybeEnv ?? AppEnvironment.shared }
    let suggestion: Suggestion
    let from: TitleStatus
    let model: SavedModel

    var body: some View {
        let moves = SavedModel.moves(kind: suggestion.kind, from: from)
        Section {
            ForEach(moves, id: \.self) { to in
                Button { Task { await move(to) } } label: {
                    Label { Self.title(to) } icon: { Image(systemName: TitleView.statusSymbol(to == .inList ? .inList : to)) }
                }
            }
            if from == .inList {
                Button(role: .destructive) { Task { await removeFromList() } } label: { Label("Quitar de Mi lista", systemImage: "minus.circle") }
            }
        } header: { Text("Mover a…") }
    }

    static func title(_ to: TitleStatus) -> Text {
        switch to {
        case .inList: Text("Mi lista")
        case .watching: Text("Viendo")
        case .watched: Text("Vistas")
        case .dropped: Text("Las dejé")
        case .none: Text(verbatim: "")
        }
    }

    private func move(_ to: TitleStatus) async {
        let s = suggestion, follow = env.follow, model = model, env = env
        let wasListed = model.watchlist.contains { $0.imdb == s.imdb }
        switch to {
        case .inList:
            if from == .dropped { _ = await follow.unhide(s.imdb, following: false) }
            await model.setInWatchlist(s, true)
            done(to) { Task { await model.setInWatchlist(s, false) } }
        case .watching:
            if let problem = await follow.unhide(s.imdb, following: false) { env.notify(problem, tone: .error); return }
            done(to) { Task { _ = await follow.hide(s.imdb) } }
        case .watched:
            await model.markMovieWatched(s)
            done(to) { Task { await model.unmarkMovieWatched(s); if wasListed { await model.setInWatchlist(s, true) } } }
        case .dropped:
            if s.kind == "series" {
                if let problem = await follow.hide(s.imdb) { env.notify(problem, tone: .error); return }
                await ReleaseNotifier.forget(s.imdb)
                if wasListed { await model.setInWatchlist(s, false) }
                done(to) { Task { _ = await follow.undoHide(); if wasListed { await model.setInWatchlist(s, true) } } }
            } else {
                await model.dropMovie(s)
                done(to) { Task { if wasListed { await model.setInWatchlist(s, true) } } }
            }
        case .none: break
        }
    }

    private func removeFromList() async {
        let s = suggestion, model = model
        await model.setInWatchlist(s, false)
        env.notify(removed: .myList) { Task { await model.setInWatchlist(s, true) } }
    }

    /// «Marcada como vista · Dune», con «Deshacer».
    private func done(_ to: TitleStatus, undo: @escaping () -> Void) {
        let text = switch to {
        case .inList: "Guardada en Mi lista"
        case .watching: "Otra vez en Seguir viendo"
        case .watched: "Marcada como vista"
        case .dropped, .none: "La dejaste"
        }
        env.notify(text, detail: suggestion.title, tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward", perform: undo)
    }
}
