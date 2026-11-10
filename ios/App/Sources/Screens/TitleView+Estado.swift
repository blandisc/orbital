import SwiftUI
import OrbitalCore
import OrbitalModels

/// G1-A (Fernando, 9 nov 2026: «me gusta tu sugerencia»): un solo botón dice cómo vas con el título y reemplaza a «Ya la vi»,
/// «Guardar» y «Seguir». Sin estado, un toque la guarda en Mi lista (como «Guardar»); con estado, un toque abre «¿Cómo vas
/// con…?». Mantener el dedo siempre lo abre. docs/producto/live-activity-2026-11-08/gestor-maquetas.html
/// En la TV: la ficha sigue con sus botones; lo que se marca aquí le llega por Trakt (pendiente en el registro de paridad).
extension TitleView {
    func statusAction(_ model: TitleModel) -> some View {
        let follow = env.follow
        let _ = follow.track()
        let status = model.status(dropped: follow.hidden.contains(model.metaID))
        let label = ActionTileLabel(title: Self.statusTitle(status), symbol: Self.statusSymbol(status), active: status != .none, tint: artAccent)
        return Group {
            if status == .none {
                Menu { statusMenu(model, status, follow) } label: { label } primaryAction: { Task { await quickSave(model) } }
                    .accessibilityHint(Text("Mantén presionado para ver las opciones"))
            } else {
                Menu { statusMenu(model, status, follow) } label: { label }
            }
        }
        .menuStyle(.button).buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: status) { _, now in now != .none }
        .animation(DS.Motion.base(reduceMotion), value: status)
        .accessibilityIdentifier("title-status")
    }

    static func statusTitle(_ status: TitleStatus) -> Text {
        switch status {
        case .none: Text("Mi lista")
        case .inList: Text("En Mi lista")
        case .watching: Text("Viendo")
        case .watched: Text("Vista")
        case .dropped: Text("La dejé")
        }
    }

    static func statusSymbol(_ status: TitleStatus) -> String {
        switch status {
        case .none: "bookmark"
        case .inList: "bookmark.fill"
        case .watching: "play.circle.fill"
        case .watched: "checkmark.circle.fill"
        case .dropped: "eye.slash"
        }
    }

    /// «¿Cómo vas con…?»: las respuestas (la elegida con la palomita), la campana de una serie y tus listas.
    @ViewBuilder private func statusMenu(_ model: TitleModel, _ status: TitleStatus, _ follow: FollowModel) -> some View {
        let series = model.kind == "series"
        let canDrop = series ? follow.available : (model.inLibrary || model.resumeFraction != nil)
        Section {
            Button { Task { await toggleList(model, status, follow) } } label: {
                Label { Text("En Mi lista") } icon: { Image(systemName: status == .inList ? "checkmark" : "bookmark") }
            }
            if series, status == .watching || status == .dropped && model.seasonProgress.watched > 0 {
                Button { Task { await showAgain(model, follow) } } label: {
                    Label { Text("Viendo") } icon: { Image(systemName: status == .watching ? "checkmark" : "play.circle") }
                }
            }
            Button { marking = series ? .series : .movie } label: {
                Label { Text("Vista") } icon: { Image(systemName: status == .watched ? "checkmark" : "checkmark.circle") }
            }
            if canDrop {
                Button { Task { status == .dropped ? await showAgain(model, follow) : await drop(model, follow) } } label: {
                    Label { Text("La dejé") } icon: { Image(systemName: status == .dropped ? "checkmark" : "eye.slash") }
                }
            }
        } header: { Text("¿Cómo vas con \(model.title)?") }
        if series, follow.available {
            Section {
                Toggle(isOn: Binding(get: { follow.isFollowing(model.metaID) }, set: { on in Task { await setBell(model, follow, on) } })) {
                    Label("Avisarme de episodios nuevos", systemImage: "bell")
                }
                .disabled(status == .dropped)
            }
        }
        if model.traktAvailable {
            Section { Button("Agregar a una lista…", systemImage: "list.bullet") { saving = true } }
        }
    }

    private func toggleList(_ model: TitleModel, _ status: TitleStatus, _ follow: FollowModel) async {
        if status == .dropped { _ = await follow.unhide(model.metaID) }
        let adding = !model.inLibrary
        await model.toggleLibrary()
        if adding { env.notify(saved: model.saveDestination, undo: true) { Task { await model.toggleLibrary() } } }
        else { env.notify(removed: model.saveDestination) { Task { await model.toggleLibrary() } } }
    }

    /// «Viendo» desde «La dejé»: la serie regresa a Seguir viendo (sin la campana, como estaba al dejarla).
    private func showAgain(_ model: TitleModel, _ follow: FollowModel) async {
        guard follow.hidden.contains(model.metaID) else { return }
        if let problem = await follow.unhide(model.metaID, following: false) { env.notify(problem, tone: .error); return }
        env.notify("Otra vez en Seguir viendo", detail: model.title, tone: .info)
    }

    /// «La dejé»: una serie se esconde (sale de Seguir viendo, de tus estrenos y de los avisos) y sale de Mi lista; una película
    /// sale de Mi lista y de Seguir viendo. Lo visto se queda. Con «Deshacer».
    private func drop(_ model: TitleModel, _ follow: FollowModel) async {
        let wasInList = model.inLibrary
        if model.kind == "series" {
            if let problem = await follow.hide(model.metaID) { env.notify(problem, tone: .error); return }
            await ReleaseNotifier.forget(model.metaID)
            if wasInList { await model.toggleLibrary() }
            env.notify("La dejaste", detail: model.title, tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
                Task {
                    if let problem = await follow.undoHide() { env.notify(problem, tone: .error) }
                    if wasInList, !model.inLibrary { await model.toggleLibrary() }
                }
            }
        } else {
            await model.dropMovie()
            env.notify("La dejaste", detail: "Ya no sale en Mi lista ni en Seguir viendo", tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") {
                Task { if wasInList, !model.inLibrary { await model.toggleLibrary() } }
            }
        }
    }

    private func setBell(_ model: TitleModel, _ follow: FollowModel, _ on: Bool) async {
        if let problem = await follow.setFollowing(model.metaID, on) { env.notify(problem, tone: .error); return }
        env.notify(on ? "Te aviso de episodios nuevos" : "Sin avisos de episodios nuevos", detail: model.title, tone: .info,
                   actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward") { Task { _ = await follow.setFollowing(model.metaID, !on) } }
    }
}
