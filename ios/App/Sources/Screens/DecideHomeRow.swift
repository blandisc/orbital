import SwiftUI

/// La misma puerta en Inicio, bajo «Seguir viendo» (DE2): abre «Decide por mí» ahí mismo, encima de Inicio (Fernando, 13 nov
/// 2026: antes te mandaba a Explorar). Lo que se sugiere y el abanico de la puerta salen del mismo modelo de Explorar
/// (`DecideSheet`, `decideFan`); una ficha elegida en la hoja se abre en Inicio (`open`) y al cerrarla sigues en Inicio.
struct DecideHomeRow: View {
    /// C6 (Fernando, 18 nov 2026): con espacio, una tarjeta (sin la tira ni el margen): al final de «Seguir viendo» o en el
    /// panel del tablero, en vez de la franja de orilla a orilla con pósters sueltos.
    var compact = false
    let open: (TitleRoute) -> Void
    @State private var deciding = false
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        // La misma puerta que en Explorar, con el mismo abanico (`decideFan`): sale de lo mismo que alimenta la hoja. Si
        // Explorar aún no carga, se pide aquí (sin pósters todavía, el dado).
        let fan = env.paraTi.model.decideFan(count: DS.ParaTiB.doorFan)
        DecideDoor(posters: Array(fan.prefix(DS.ParaTiB.matchFan)), offline: !env.isOnline, id: "home-decide",
                   more: compact ? [] : Array(fan.dropFirst(DS.ParaTiB.matchFan)), inset: compact ? 0 : nil) { deciding = true }
            .task { await env.paraTi.model.loadIfStale() }
            .appSheet(isPresented: $deciding) { DecideSheet(open: open) }
            #if DEBUG
            .task { if Demo.isOn, Demo.open == "home-decide" { try? await Task.sleep(for: .seconds(3)); deciding = true } }   // ds-exception: capturas (Demo)
            #endif
    }
}
