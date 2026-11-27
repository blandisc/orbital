import SwiftUI
import OrbitalCore

/// Los controles conectados a la TV (IN2-A, Fernando, 26 nov 2026), al pie del control del iPhone: uno por jugador, con su
/// número y su batería, como los focos junto a la hora de la TV: junto a «En la TV». Solo íconos (sin cápsulas de texto).
struct RemoteControllers: View {
    let players: [OrbitalRemote.ConnectedPlayer]

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(players, id: \.player) { player in
                HStack(spacing: DS.Space.s1) {
                    Image(systemName: "gamecontroller.fill")
                    Text(verbatim: "\(player.player)").monospacedDigit()
                    if let symbol = Self.batterySymbol(player.battery) {
                        Image(systemName: symbol).foregroundStyle(player.battery == "low" || player.battery == "empty" ? DS.warning : DS.textMuted)
                    }
                }
                .font(DS.TextRecipe.footnote.font)
                .foregroundStyle(DS.textMuted)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spoken(player))
            }
        }
        .fixedSize()   // nunca se corta: el número del control se perdía junto a «En la TV»
        .layoutPriority(1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("remote-controllers")
    }

    /// La pila según lo que dice la TV; con cable, el enchufe; sin dato, nada.
    static func batterySymbol(_ battery: String?) -> String? {
        switch battery {
        case "wired": "powerplug.fill"
        case "full": "battery.100"
        case "medium": "battery.50"
        case "low": "battery.25"
        case "empty": "battery.0"
        default: nil
        }
    }

    static func spoken(_ player: OrbitalRemote.ConnectedPlayer) -> Text {
        let battery: Text? = switch player.battery {
        case "wired": Text("con cable")
        case "full": Text("batería llena")
        case "medium": Text("batería a la mitad")
        case "low": Text("batería baja")
        case "empty": Text("sin batería")
        default: nil
        }
        return battery.map { Text("Control \(player.player), \($0)") } ?? Text("Control \(player.player)")
    }
}
