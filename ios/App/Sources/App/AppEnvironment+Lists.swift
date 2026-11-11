import SwiftUI
import OrbitalCore
import OrbitalModels

/// Editar tus listas desde un póster o una lista abierta (Fernando, 6 nov 2026): quitar y agregar con un aviso que se deshace,
/// sin preguntar. La pantalla cambia al instante (`shown`); si Trakt no acepta, regresa y lo dice.
extension AppEnvironment {
    /// El nombre de una de tus listas en el idioma de la app: «Mi lista» o el que le pusiste en Trakt.
    func listName(_ listID: String, name: String) -> String {
        listID == "watchlist" || name.isEmpty ? Strings.tr("Mi lista", language: services.appSettings.uiLanguage) : name
    }

    /// Quita (o agrega) un título de una de tus listas. `shown` mueve el póster en la pantalla: sale ya, regresa si falla o si
    /// tocas «Deshacer».
    func edit(_ s: Suggestion, list listID: String, name: String, add: Bool, shown: @escaping (Bool) -> Void) async {
        shown(add)
        do {
            try await titles.setInList(s, listID: listID, add: add)
            notifyListEdit(s, list: listID, name: name, added: add) { [weak self] in
                shown(!add)
                Task { try? await self?.titles.setInList(s, listID: listID, add: !add) }
            }
        } catch {
            shown(!add)
            notify(format: "No pude cambiar «%@»", listName(listID, name: name), failure: error, tone: .warn)
        }
    }

    /// «Quitada de Mi lista» / «Agregada a Terror de octubre», con «Deshacer».
    func notifyListEdit(_ s: Suggestion, list listID: String, name: String, added: Bool, undo: @escaping () -> Void) {
        let language = services.appSettings.uiLanguage
        let text = String(format: Strings.tr(added ? "Agregada a «%@»" : "Quitada de «%@»", language: language), listName(listID, name: name))
        notify(text, tone: .info, actionTitle: "Deshacer", actionSymbol: "arrow.uturn.backward", perform: undo)
    }
}
