import SwiftUI

/// Prueba del 11 nov 2026. Fernando: el renglón de la versión («🇲🇽 Español · 1080p ›») «está ahí crudo, solo y rompe
/// simetría». Tres maneras de ponerlo en la ficha, construidas en real para verlas y elegir una:
/// - L1 (`VersionRowCentered`): centrado con los datos del título, justo arriba de «Ver».
/// - L2 (`VersionRowTile`): una tarjeta a todo lo ancho, de la familia de Guardar · Descargar · Tráiler.
/// - L3 (`SplitPlayButton`): dentro de «Ver», como la parte derecha de un botón partido.
/// En las tres, tocar abre la misma hoja «Versión». Se elige con `-demo-version-row L1|L2|L3` (solo Debug); sin la bandera,
/// como hoy. Este es el único punto que elige: al decidir, se borran este archivo, las dos piezas que no ganaron y cada
/// `VersionRowStyle.current` (la ficha y `ContinueAction`).
enum VersionRowStyle {
    /// Hoy: el renglón suelto, a la izquierda, bajo «Ver».
    case today
    /// L1.
    case centered
    /// L2.
    case tile
    /// L3.
    case split

    static let current: VersionRowStyle = {
        #if DEBUG
        switch Demo.value(after: "-demo-version-row") {
        case "L1": .centered
        case "L2": .tile
        case "L3": .split
        default: .today
        }
        #else
        .today
        #endif
    }()
}

/// Lo que dicen las tres piezas de la versión, ya armado por la ficha (`TitleView.versionSummary`).
struct VersionSummary {
    /// «🇲🇽 Latino · 1080p»: la bandera con su idioma escrito y la calidad (la mitad España, mitad México, dibujada).
    let full: Text
    /// «🇲🇽 1080p»: para la parte derecha del botón partido.
    let compact: Text
    /// Lo mínimo que la identifica (la bandera; sin bandera conocida, el idioma): el botón partido cuando no cabe más.
    let mark: Text
    /// «Español, 1080p», sin banderas: VoiceOver dice «Versión: Español, 1080p. Cambiar».
    let spoken: String
    /// Aún buscando la versión: la pieza con su forma, en gris, sin tocarse (nada brinca cuando llega).
    var pending = false
    let open: () -> Void

    var accessibilityLabel: Text { pending ? Text("Buscando versión") : Text("Versión: \(spoken). Cambiar") }

    /// Mientras se busca: el mismo largo que tendrá, en gris.
    static var placeholder: VersionSummary { VersionSummary(full: Text(verbatim: "Español · 1080p"), compact: Text(verbatim: "Es 1080p"),
                                            mark: Text(verbatim: "Es"), spoken: "", pending: true, open: {}) }
}

extension View {
    /// Lo común de las tres piezas: el esqueleto mientras busca y lo que lee VoiceOver.
    func versionRowBehavior(_ summary: VersionSummary) -> some View {
        redacted(reason: summary.pending ? .placeholder : [])
            .disabled(summary.pending)
            .accessibilityLabel(summary.accessibilityLabel)
            .accessibilityIdentifier("title-sources")
    }
}
