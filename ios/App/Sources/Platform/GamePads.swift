import GameController
import SwiftUI

/// ¿Hay un mando conectado (tu GameSir por Bluetooth)? Con mando no hay botones en la pantalla; si se desconecta, aparecen
/// solos (E2-A). En Debug, `-demo-game-pad` finge uno para las capturas.
@MainActor @Observable
final class GamePads {
    private(set) var connected = false
    /// El nombre del mando («GameSir-T4»), para la ficha y Ajustes › Juegos.
    private(set) var name: String?
    private var watchers: [NSObjectProtocol] = []

    init() {
        refresh()
        let center = NotificationCenter.default
        for note in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            watchers.append(center.addObserver(forName: note, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    private func refresh() {
        #if DEBUG
        // En el modo demo manda la bandera: el simulador ve el mando conectado a la Mac.
        if Demo.isOn { connected = Demo.has("-demo-game-pad"); name = connected ? "GameSir" : nil; return }
        #endif
        let pad = GCController.controllers().first { $0.extendedGamepad != nil }
        connected = pad != nil
        name = pad?.vendorName
    }
}
