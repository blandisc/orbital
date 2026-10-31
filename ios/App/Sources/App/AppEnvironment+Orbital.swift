import SwiftUI
import UIKit
import OrbitalCore
import OrbitalModels

/// Tu Orbital (la consola): emparejar, «Ver en la TV», pasarle el video desde el reproductor y deshacerlo.
extension AppEnvironment {
    func pairWithOrbital(address: String, token: String) async {
        do {
            let got = try await services.connectOrbital(address: address, token: token)
            let brought = got.joined(separator: services.appSettings.uiLanguage == "en" ? " and " : " y ")
            if got.isEmpty { notify("Conectado con tu Orbital", tone: .success) } else { notify(format: "Conectado con tu Orbital: %@ ya están aquí.", brought, tone: .success) }
        } catch { notifyOrbital(error) }
    }

    /// Tu Orbital no hizo lo que se le pidió: lo que dijo (no contesta, el token, actualizar), nunca el texto técnico.
    func notifyOrbital(_ error: Error) {
        notify((error as? OrbitalRemote.Failure)?.description ?? "Tu Orbital no contestó.", tone: .warn)
    }


    /// «Ver en la TV»: el aviso sale al tocar («Mandando a tu Orbital…», con su toque suave), y cuando la consola lo
    /// acepta se vuelve la confirmación, con el control a un toque. Un segundo toque mientras va en camino no manda otra.
    func playOnTV(kind: String, metaID: String, videoID: String?, title: String) async {
        guard ui.sendingToTV != metaID else { return }
        ui.sendingToTV = metaID
        defer { if ui.sendingToTV == metaID { ui.sendingToTV = nil } }
        let language = services.appSettings.uiLanguage
        notices.show(Notice(text: Strings.message("Mandando a tu Orbital…", language: language), tone: .info, detail: title, symbol: "tv"))
        do {
            try await services.orbital.play(kind: kind, metaID: metaID, videoID: videoID, title: title)
            notify("Ya está en tu Orbital", detail: title, tone: .success, actionTitle: "Control", actionSymbol: "appletvremote.gen4.fill") { [weak self] in
                self?.ui.openRemote = true
            }
        } catch { notifyOrbital(error) }
    }

    /// Lo de `metaID` va en camino a tu Orbital (el botón de la tele enseña la ruedita).
    func isSendingToTV(_ metaID: String) -> Bool { ui.sendingToTV == metaID }

    /// Del reproductor del iPhone a tu Orbital, en el mismo punto: la TV sigue donde ibas y la app enseña el aviso.
    func handOffToTV(_ request: PlayRequest, position: Double, choice: ResumeChoice? = nil) async {
        do {
            // Con el segundo exacto y lo que tenías puesto: la TV no adivina con su recomendada ni con el avance de Stremio.
            try await services.orbital.play(kind: request.kind, metaID: request.metaID, videoID: request.videoID, title: request.displayTitle,
                                            position: position, choice: choice)
            handoff = TVHandoff(request: request, position: position)
        } catch { notifyOrbital(error) }
    }

    /// «Deshacer»: la TV se detiene y sigues en el iPhone donde ibas (el avance ya se guardó al cerrar).
    func undoHandoff() async {
        guard let h = handoff else { return }
        handoff = nil
        _ = try? await services.orbital.control(action: "stop")
        var request = h.request
        request.fromStart = false
        play(request)
    }

}
