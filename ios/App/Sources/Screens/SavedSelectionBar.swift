import SwiftUI
import OrbitalCore
import OrbitalModels

/// La barra de abajo de Guardado mientras eliges (G3-A, Fernando, 10 nov 2026: «Vamos con tus sugerencias»). Ofrece solo lo
/// que tiene sentido donde estás (`SavedModel.batchActions`): en Mi lista y tus listas, Vistas (solo películas) · Las dejé ·
/// Mover a… · Quitar; en Viendo, Mi lista · Las dejé · Agregar a una lista; en Vistas, Mi lista · Agregar a una lista (sin
/// «Quitar»: borraría cuándo la viste); en Las dejé, Viendo · Mi lista. Un solo aviso con «Deshacer» para todo el grupo.
/// En la TV: sigue con el «−» por póster (pendiente en el registro de paridad); lo que cambies aquí le llega por Trakt.
struct SavedSelectionBar: View {
    @Environment(AppEnvironment.self) private var env
    let model: SavedModel
    let selection: ListSelection
    /// La lista que ves (`watchlist` o `list:<id>`), o nil en un montón del tablero.
    let listID: String?
    let pile: TitleStatus?
    /// Lo que se ve ahora, en orden (para tomar los elegidos).
    let items: [Suggestion]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var naming = false
    @State private var newName = ""

    private var chosen: [Suggestion] { items.filter { selection.chosen.contains($0.imdb) } }

    var body: some View {
        let actions = SavedModel.batchActions(listID: listID, pile: pile)
        let none = chosen.isEmpty
        DSSelectionBar {
            ForEach(actions, id: \.self) { action in
                switch action {
                case .watched:
                    Button { run { await watched() } } label: { DSSelectionBarLabel(title: "Vistas", symbol: "checkmark.circle") }
                        .disabled(!chosen.contains { $0.kind == "movie" })
                        .accessibilityHint(Text("Solo las películas; las series se marcan por capítulo en su ficha"))
                case .drop:
                    Button { run { await drop() } } label: { DSSelectionBarLabel(title: "Las dejé", symbol: "eye.slash") }.disabled(none)
                case .moveToList:
                    Menu { listMenu } label: { DSSelectionBarLabel(title: listID == nil ? "A una lista" : "Mover a…", symbol: "rectangle.portrait.on.rectangle.portrait") }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .disabled(none)
                case .toWatchlist:
                    Button { run { await toWatchlist() } } label: { DSSelectionBarLabel(title: "Mi lista", symbol: "bookmark") }.disabled(none)
                case .resume:
                    Button { run { await resume() } } label: { DSSelectionBarLabel(title: "Viendo", symbol: "play.circle") }.disabled(none)
                case .remove:
                    Button(role: .destructive) { run { await remove() } } label: { DSSelectionBarLabel(title: "Quitar", symbol: "trash", destructive: true) }
                        .keyboardShortcut(.delete, modifiers: [])
                        .disabled(none)
                }
            }
            .buttonStyle(.plain).menuStyle(.button)
        }
        .alert("Lista nueva", isPresented: $naming) {   // ds-exception: pide un nombre: el campo de texto del sistema
            TextField("Nombre", text: $newName)
            Button("Cancelar", role: .cancel) { newName = "" }
            Button("Crear") { let name = newName; newName = ""; run { await createAndMove(name) } }
        } message: { Text("Nace «Solo tú» y lo que elegiste entra ahí.") }
    }

    /// Tus otras listas (y Mi lista, si estás en una tuya) y «Lista nueva…».
    @ViewBuilder private var listMenu: some View {
        Section {
            if let listID, listID != SavedModel.watchlist {
                Button { run { await moveTo(SavedModel.watchlist) } } label: { Label("Mi lista", systemImage: "bookmark") }
            }
            ForEach(model.lists.filter { $0.id != SavedModel.watchlist && $0.id != listID }) { list in
                Button { run { await moveTo(list.id) } } label: { Label(list.name, systemImage: "list.bullet") }
            }
            Button { naming = true } label: { Label("Lista nueva…", systemImage: "plus") }
        } header: { Text(listID == nil ? "Agregar a…" : "Mover a…") }
    }

    /// Hace la acción con lo elegido y sale de elegir.
    private func run(_ work: @escaping () async -> Void) {
        let motion = DS.Motion.base(reduceMotion)
        Task { await work(); withAnimation(motion) { selection.editing = false } }
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String {
        String(format: Strings.tr(n == 1 ? one : many, language: env.services.appSettings.uiLanguage), n)
    }

    private func notify(_ text: String, detail: String? = nil, undo: @escaping () async -> Void) {
        env.notify(text, detail: detail, tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") { Task { await undo() } }
    }

    // MARK: acciones
    private func watched() async {
        let picked = chosen, model = model
        let listed = picked.filter { s in model.watchlist.contains { $0.imdb == s.imdb } }
        let movies = await model.markMoviesWatched(picked)
        let series = picked.count - movies.count
        notify(count(movies.count, "%d marcada como vista", "%d marcadas como vistas"),
               detail: series > 0 ? Strings.tr("Las series se marcan por capítulo en su ficha", language: env.services.appSettings.uiLanguage) : nil) {
            await model.unmarkMoviesWatched(movies)
            await model.setMany(listed.filter { s in movies.contains { $0.imdb == s.imdb } }, in: SavedModel.watchlist, add: true)
        }
    }

    private func drop() async {
        let picked = chosen, model = model, follow = env.follow
        let series = picked.filter { $0.kind == "series" }.map(\.imdb)
        if let problem = await follow.hide(series) { env.notify(problem, tone: .error); return }
        for id in series { await ReleaseNotifier.forget(id) }
        let fromList = listID ?? SavedModel.watchlist
        let listed = picked.filter { s in fromList != SavedModel.watchlist || model.watchlist.contains { $0.imdb == s.imdb } }
        if listID != nil || pile == .watching { await model.setMany(listed, in: fromList, add: false) }
        for s in picked where s.kind == "movie" { await env.services.watch.dismissContinue(metaID: s.imdb) }
        notify(count(picked.count, "%d en Las dejé", "%d en Las dejé")) {
            _ = await follow.unhide(series)
            await model.setMany(listed, in: fromList, add: true)
        }
    }

    private func moveTo(_ target: String) async {
        let picked = chosen, model = model, from = listID
        await model.setMany(picked, in: target, add: true)
        if let from { await model.setMany(picked, in: from, add: false) }
        let name = env.listName(target, name: model.lists.first { $0.id == target }?.name ?? "")
        notify(String(format: Strings.tr(from == nil ? "Agregadas a «%@»" : "Movidas a «%@»", language: env.services.appSettings.uiLanguage), name),
               detail: count(picked.count, "%d título", "%d títulos")) {
            await model.setMany(picked, in: target, add: false)
            if let from { await model.setMany(picked, in: from, add: true) }
        }
    }

    private func createAndMove(_ name: String) async {
        switch await model.createList(named: name) {
        case .success(let id): await moveTo(id)
        case .failure(let error): env.notify("No pude crear la lista", failure: error, tone: .warn)
        }
    }

    private func toWatchlist() async {
        let picked = chosen, model = model, follow = env.follow
        let dropped = picked.map(\.imdb).filter { follow.hidden.contains($0) }
        if !dropped.isEmpty { _ = await follow.unhide(dropped) }
        await model.setMany(picked, in: SavedModel.watchlist, add: true)
        notify(count(picked.count, "%d guardada en Mi lista", "%d guardadas en Mi lista")) {
            await model.setMany(picked, in: SavedModel.watchlist, add: false)
            if !dropped.isEmpty { _ = await follow.hide(dropped) }
        }
    }

    private func resume() async {
        let ids = chosen.map(\.imdb), follow = env.follow
        if let problem = await follow.unhide(ids) { env.notify(problem, tone: .error); return }
        notify(count(ids.count, "%d otra vez en Viendo", "%d otra vez en Viendo")) { _ = await follow.hide(ids) }
    }

    private func remove() async {
        guard let listID else { return }
        let picked = chosen, model = model
        await model.setMany(picked, in: listID, add: false)
        let name = env.listName(listID, name: model.lists.first { $0.id == listID }?.name ?? "")
        notify(String(format: Strings.tr("Quitadas de «%@»", language: env.services.appSettings.uiLanguage), name),
               detail: count(picked.count, "%d título", "%d títulos")) {
            await model.setMany(picked, in: listID, add: true)
        }
    }
}
