import SwiftUI

/// La misma puerta en Inicio, bajo «Seguir viendo» (DE2): abre «Decide por mí» ahí mismo, encima de Inicio (Fernando, 13 nov
/// 2026: antes te mandaba a Explorar). Lo que se sugiere y el abanico de la puerta salen del mismo modelo de Explorar
/// (`DecideSheet`, `decideFan`); una ficha elegida en la hoja se abre en Inicio (`open`) y al cerrarla sigues en Inicio.
struct DecideHomeRow: View {
    let open: (TitleRoute) -> Void
    @State private var deciding = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        // La misma puerta que en Explorar, con el mismo abanico (`decideFan`): sale de lo mismo que alimenta la hoja. Si
        // Explorar aún no carga, se pide aquí (sin pósters todavía, el dado).
        DecideDoor(posters: env.paraTi.model.decideFan(), offline: !env.isOnline, id: "home-decide") { deciding = true }
            .task { await env.paraTi.model.loadIfStale() }
            .sheet(isPresented: $deciding) { DecideSheet(open: open) }
            #if DEBUG
            .task { if Demo.isOn, Demo.open == "home-decide" { try? await Task.sleep(for: .seconds(3)); deciding = true } }   // ds-exception: capturas (Demo)
            #endif
    }
}
