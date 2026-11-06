import SwiftUI
import OrbitalCore

/// De qué complemento viene una versión (Fernando, 6 nov: «un mini ícono para saber si es de uno u otro»): Ⓣ Torrentio,
/// Ⓒ Comet (de respaldo) y una pieza para los demás. Chico y tenue, junto a la calidad; VoiceOver dice el nombre.
struct AddonMark: View {
    let kind: Streams.AddonKind

    var body: some View {
        Image(systemName: Self.symbol(kind))
            .font(DS.TextRecipe.caption.font)
            .foregroundStyle(DS.textMuted)
            .accessibilityLabel(Self.name(kind))
    }

    static func symbol(_ kind: Streams.AddonKind) -> String {
        switch kind {
        case .torrentio: "t.circle"
        case .comet: "c.circle"
        case .other: "puzzlepiece.extension"
        }
    }

    static func name(_ kind: Streams.AddonKind) -> Text {
        switch kind {
        case .torrentio: Text(verbatim: "Torrentio")
        case .comet: Text(verbatim: "Comet")
        case .other: Text("Otro complemento")
        }
    }
}
