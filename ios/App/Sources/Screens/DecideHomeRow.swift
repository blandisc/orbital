import SwiftUI

/// La misma puerta en Inicio, bajo «Seguir viendo» (DE2): abre «Decide por mí» en Explorar.
struct DecideHomeRow: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        DecideDoor(id: "home-decide") {
            env.ui.openDecide = true
            env.openTab = AppEnvironment.exploreTab
        }
    }
}
