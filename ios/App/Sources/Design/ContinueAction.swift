import SwiftUI

/// El botón principal de la ficha y lo que lo acompaña. El botón dice una sola cosa («▶ Continuar», «▶ Ver T2 E6», «Cargando»).
/// Si hay versión que elegir, el botón va partido (`SplitPlayButton`, L3, Fernando, 11 nov 2026): a la derecha, la versión que
/// va a sonar («🇲🇽 1080p ⌄») abre «Versión». No hay un renglón de versión aparte (docs/ios-interfaz.md § «La versión vive en
/// el botón»). Debajo, si ibas a medias, la barrita de avance a todo lo ancho del botón; y un solo renglón: a la izquierda el
/// estado en gris («quedan 50 min», o un aviso: «Sin versiones por ahora»), a la derecha la acción «Desde el principio» en
/// color, para que se vea que se toca (pulida del 29 oct).
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
    /// «Desde el principio»: solo si ibas a medias.
    var restart: (() -> Void)?
    /// La otra salida a la derecha cuando no hay «Desde el principio» (Real-Debrid, R2-A y R13): «Verlo en inglés al
    /// instante» o «Cancelar pedido». Mismo lugar y mismo estilo: una acción en color.
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
            if let progress { DSProgress(fraction: progress).padding(.top, DS.Space.s1) }
            if left != nil || note != nil || restart != nil || aside != nil {
                // Si no cabe todo en un renglón (aviso largo, letra grande), «quedan…» y «Desde el principio» se quedan juntos
                // (son el mismo asunto: el avance) y el aviso baja solo.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s3) { status(left, note); restartRow }
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        HStack(spacing: DS.Space.s3) { status(left, nil); restartRow }
                        status(nil, note)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Letra de accesibilidad: ni «quedan…» y «Desde el principio» caben juntos (revisión 2: «quedan 20…»,
                    // «Desde el…»); cada uno en su renglón, completo.
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        status(left, nil)
                        restartButton
                        status(nil, note)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let why {
                why.recipe(.footnote, color: DS.textMuted).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("title-why-version")
            }
        }
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

    /// «quedan 50 min · Sin conexión»: cuánto falta y el aviso, en un solo texto gris (ámbar si es un problema).
    @ViewBuilder private func status(_ left: Text?, _ note: Text?) -> some View {
        if let text = Self.join(left, note) {
            // Solo el aviso (sin «quedan…»): hasta dos renglones («Muchas descargas activas · Lo vuelvo a pedir cuando se
            // libere un lugar» se cortaba a la mitad).
            text.recipe(.footnote, color: warn ? DS.warning : DS.textMuted).lineLimit(left == nil ? 2 : 1)
        }
    }

    private static func join(_ a: Text?, _ b: Text?) -> Text? {
        switch (a, b) {
        case (let a?, let b?): Text("\(a) · \(b)")
        case (let a?, nil): a
        case (nil, let b?): b
        case (nil, nil): nil
        }
    }

    @ViewBuilder private var restartRow: some View {
        if restart != nil || aside != nil { Spacer(minLength: 0); restartButton }
    }

    @ViewBuilder private var restartButton: some View {
        if let restart {
            Button("Desde el principio", systemImage: "arrow.counterclockwise", action: restart)
                .font(DS.TextRecipe.label.font).buttonStyle(.borderless).tint(ink).lineLimit(1)
                .accessibilityIdentifier("title-restart")
        } else if let aside {
            Button(action: aside.action) { Label { aside.title } icon: { Image(systemName: aside.symbol) } }
                .font(DS.TextRecipe.label.font).buttonStyle(.borderless).tint(ink).lineLimit(1)
                .accessibilityIdentifier("title-aside")
        }
    }
}
