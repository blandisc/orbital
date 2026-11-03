import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

// Piezas de «tu lista, la misma que tu TV» (Fase 4, 3 nov 2026; S1, S3, S5, S6): dónde está en palabras y lo que es solo de
// la TV. Solo aparecen en Orbital Ultra con una TV emparejada (S4).

/// Dónde está tu lista con la de tu TV, en una línea con su ícono (nunca solo color): igual, revisando, la TV no contestó, o
/// lo que se queda en este iPhone porque lleva una clave (con calma: no es un error).
struct AddonTVStatus: View {
    let status: AddonTVSync.Status
    var waitingForKeys: [String] = []
    /// «Reintentar» (IOS-9): la TV no contestó o no tomó la lista.
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            if let line = main { row(line.symbol, line.tint, line.title, line.detail) }
            if let retry, hasProblem {
                Button(action: retry) { Text("Reintentar").font(DS.TextRecipe.label.font) }
                    .dsSecondaryButton().controlSize(.large)
                    .accessibilityIdentifier("addons-tv-retry")
            }
            if !waitingForKeys.isEmpty {   // IOS-5: solo sin conexión propia (con ella, todo viaja); sin «llaves»
                row("iphone", DS.textMuted, Text("\(waitingForKeys.joined(separator: ", ")) se queda en este iPhone"),
                    Text("Su dirección lleva tu clave: pasa a la TV cuando este iPhone tenga su propia conexión (Ajustes › Tu Orbital)."))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("addons-tv-status")
    }

    private struct Line { var symbol: String; var tint: Color; var title: Text; var detail: Text? }

    private var main: Line? {
        switch status {
        case .off: nil
        case .checking: Line(symbol: "tv", tint: DS.textMuted, title: Text("Revisando con tu TV…"), detail: nil)
        case .same(_, let by):
            Line(symbol: "checkmark.circle", tint: DS.success, title: Text("Es la misma lista que tu TV"),
                 detail: by == "tv" ? Text("El último cambio fue en tu TV") : Text("Lo que cambies aquí, tu TV lo toma"))
        case .unreachable:
            Line(symbol: "tv", tint: DS.warning, title: Text("Tu TV no contestó"), detail: Text("Lo que cambies aquí le llega cuando conteste"))
        case .outdated:
            Line(symbol: "arrow.down.circle", tint: DS.warning, title: Text("Actualiza Orbital en tu TV"), detail: Text("Así toma esta lista"))
        case .refused(let why) where AddonTVSync.waitsForKeys(why): nil   // lo dice el renglón de abajo, si toca (IOS-5)
        case .refused:   // IOS-9: en palabras y con «Reintentar» (antes «no tiene la forma acordada»)
            Line(symbol: "exclamationmark.circle", tint: DS.warning, title: Text("Tu TV no tomó la lista"),
                 detail: Text("Algo no cuadró al mandarla. Reintenta; si sigue, actualiza Orbital en tu TV."))
        }
    }

    private var hasProblem: Bool {
        switch status {
        case .unreachable: true
        case .refused(let why): !AddonTVSync.waitsForKeys(why)
        default: false
        }
    }

    private func row(_ symbol: String, _ tint: Color, _ title: Text, _ detail: Text?) -> some View {
        IconBeside(symbol: symbol, color: tint) {
            title.font(DS.TextRecipe.body.font).foregroundStyle(DS.text)
            if let detail { detail.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Uno que está en tu TV y no en este iPhone (S5): «Archivos de la TV · Solo en la TV» o su nombre con «Solo en la TV».
struct AddonTVOnlyRow: View {
    let addon: SharedAddon

    var body: some View {
        IconBeside(symbol: "tv") {
            (addon.isTVFiles ? Text("Archivos de la TV") : Text(verbatim: addon.name))
                .font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
            Text("Solo en la TV").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
        }
        .accessibilityElement(children: .combine)
    }
}
