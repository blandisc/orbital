import SwiftUI

/// El botón principal de la ficha y lo que lo acompaña. El botón dice una sola cosa («▶ Continuar», «▶ Ver T2 E6», «Cargando»).
/// Si hay versión que elegir, el botón va partido (`SplitPlayButton`, L3, Fernando, 11 nov 2026): a la derecha, la versión que
/// va a sonar («🇲🇽 1080p ⌄») abre «Versión». No hay un renglón de versión aparte (docs/ios-interfaz.md § «La versión vive en
/// el botón»). Debajo, si ibas a medias, UNA línea con tres piezas centradas entre sí (R1, Fernando, 12 nov 2026: «Me gusta la
/// F1. Y vamos a ir con R1»): la barra de avance (lo que sobra), «quedan 20 min» y el botón redondo «Desde el principio» (solo
/// el ícono, `DSIconButton`, 44 pt). Abajo, si hay, el aviso en gris a la izquierda y la otra salida (`aside`, Real-Debrid) en
/// color a la derecha (docs/ios-interfaz.md § «Lo que acompaña a un control va en su misma línea»).
struct ContinueAction: View {
    let title: Text
    /// nil: sin ícono («Sin conexión», «Aún sin episodios»).
    var symbol: String? = "play.fill"
    var loading = false
    var enabled = true
    /// 0…1, si ibas a medias.
    var progress: Double?
    /// «quedan 1 h 59 min».
    var left: Text?
    /// El aviso de abajo, que solo informa: «Sin versiones por ahora», «Lo tiene tu TV con otra cuenta», «T1 E2 · En cola».
    var note: Text?
    /// La versión que va a sonar: la zona derecha del botón partido. nil: el botón entero (sin versiones, sin red, Real-Debrid
    /// o una versión de la app que no deja elegir).
    var version: VersionSummary?
    let play: () -> Void
    /// «Desde el principio»: solo si ibas a medias. Un botón redondo al final de la línea del avance.
    var restart: (() -> Void)?
    /// La otra salida (Real-Debrid, R2-A y R13): «Verlo en inglés al instante» o «Cancelar pedido». A la derecha del aviso, en
    /// color: dice qué hace, así que lleva su nombre (no es un ícono solo).
    var aside: (title: Text, symbol: String, action: () -> Void)?
    /// N5-A · por qué «Ver» no es la de un idioma que va antes en tu orden («La de inglés pesa 64 GB y aquí no se ve bien»):
    /// un renglón aparte, debajo del estado.
    var why: Text?
    /// IOS-9 · el renglón de abajo dice un problema (atorado, rechazado): en ámbar, mientras el botón dice la acción.
    var warn = false
    /// El color de «Desde el principio»: el del arte, como los mosaicos de abajo.
    var tint: Color = DS.accent
    @Environment(\.colorScheme) private var scheme
    /// En claro, el color del arte se oscurece como en las acciones de abajo (`TitleActions`): el tono claro sobre papel no se leía.
    private var ink: Color { scheme == .light ? tint.mix(with: DS.backdropDeep, by: DS.TitleAction.lightDeepen) : tint }

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            if let version {
                SplitPlayButton(title: label, version: version, enabled: enabled, play: play)
            } else {
                Button(action: play) { label }
                    .dsSolidPrimaryButton().disabled(!enabled)
                    .accessibilityIdentifier("title-play")
                    .coachAnchor("title-play")   // F3: el aviso con foco de la ficha señala este botón
            }
            if progress != nil || left != nil || restart != nil { resumeLine }
            if note != nil || aside != nil {
                // Si el aviso y la otra salida no caben juntos (aviso largo, letra grande), la salida baja sola.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s3) { status(note); if aside != nil { Spacer(minLength: 0); asideButton } }
                    VStack(alignment: .leading, spacing: DS.Space.s2) { status(note); asideButton }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let why {
                why.recipe(.footnote, color: DS.textMuted).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("title-why-version")
            }
        }
    }

    /// R1: la barra (lo que sobra), «quedan 20 min» y ↺, en una sola línea y centrados entre sí. Con letra de accesibilidad,
    /// si la barra ya no tendría su ancho mínimo, «quedan…» baja solo y la barra y ↺ siguen juntos.
    private var resumeLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s3) {
                bar.frame(minWidth: DS.TitleAction.resumeBarMin)
                status(left).fixedSize()
                restartButton
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                HStack(spacing: DS.Space.s3) { bar; restartButton }
                status(left)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var bar: some View {
        if let progress { DSProgress(fraction: progress) } else { Spacer(minLength: 0) }
    }

    private var label: some View {
        Group {
            if loading {
                HStack(spacing: DS.Space.s2) { ProgressView().tint(DS.onSolidPrimary); title }   // ds-exception: la ruedita va dentro del botón principal, con su título grande (DSInlineProgress es chica y gris)
            } else if let symbol {
                Label { title } icon: { Image(systemName: symbol) }
            } else { title }
        }
        .font(DS.TextRecipe.cardTitle.font).lineLimit(2).multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: DS.TitleAction.primaryHeight - DS.Space.s3 * 2)
    }

    /// «quedan 50 min» o el aviso, en gris (ámbar si es un problema). El aviso solo, hasta dos renglones («Muchas descargas
    /// activas · Lo vuelvo a pedir cuando se libere un lugar» se cortaba a la mitad).
    @ViewBuilder private func status(_ text: Text?) -> some View {
        if let text { text.recipe(.footnote, color: warn ? DS.warning : DS.textMuted).lineLimit(2) }
    }

    /// ↺ «Desde el principio»: de la familia de botones redondos de la app, con su nombre para VoiceOver.
    @ViewBuilder private var restartButton: some View {
        if let restart {
            DSIconButton(symbol: DS.Symbol.restart, label: "Desde el principio", action: restart)
                .accessibilityIdentifier("title-restart")
        }
    }

    @ViewBuilder private var asideButton: some View {
        if let aside {
            Button(action: aside.action) { Label { aside.title } icon: { Image(systemName: aside.symbol) } }
                .font(DS.TextRecipe.label.font).buttonStyle(.borderless).tint(ink).lineLimit(1)
                .accessibilityIdentifier("title-aside")
        }
    }
}
