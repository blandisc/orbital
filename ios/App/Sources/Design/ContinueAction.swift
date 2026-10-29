import SwiftUI

/// El botón principal de la ficha y lo que lo acompaña. El botón dice una sola cosa («▶ Continuar», «▶ Ver T2 E6», «Cargando»).
/// Debajo, si ibas a medias, la barrita de avance a todo lo ancho del botón; y un solo renglón: a la izquierda el estado en gris
/// («quedan 50 min · 🇲🇽 Latino · 1080p»), a la derecha la acción «Desde el principio» en color, para que se vea que se toca.
/// Antes eran dos renglones que mezclaban estado y acción con la misma letra gris, y la barrita iba apretada junto a «quedan…»
/// (pulida del 29 oct).
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
    /// «🇲🇽 Latino · 1080p», «Buscando versión…»; nil: ese renglón no va.
    var version: Text?
    /// Lo que lee VoiceOver en vez de `version` (sin las banderas).
    var versionLabel: Text?
    let play: () -> Void
    /// «Desde el principio»: solo si ibas a medias.
    var restart: (() -> Void)?
    /// El color de «Desde el principio»: el del arte, como los mosaicos de abajo.
    var tint: Color = DS.accent

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Button(action: play) { label }
                .dsSolidPrimaryButton().disabled(!enabled)
                .accessibilityIdentifier("title-play")
            if let progress { DSProgress(fraction: progress).padding(.top, DS.Space.s1) }
            if left != nil || version != nil || restart != nil {
                // Si no cabe todo en un renglón (versión larga, letra grande), «quedan…» y «Desde el principio» se quedan juntos
                // (son el mismo asunto: el avance) y la versión baja sola.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s3) { status(leftText, versionText); restartRow }
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        HStack(spacing: DS.Space.s3) { status(leftText, nil); restartRow }
                        status(nil, versionText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var label: some View {
        Group {
            if loading {
                HStack(spacing: DS.Space.s2) { ProgressView().tint(DS.onSolidPrimary); title }
            } else if let symbol {
                Label { title } icon: { Image(systemName: symbol) }
            } else { title }
        }
        .font(DS.TextRecipe.body.font.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: DS.TitleAction.primaryHeight - DS.Space.s3 * 2)
    }

    private var leftText: Text? { left }
    private var versionText: Text? { version }

    /// «quedan 50 min · 🇺🇸 Inglés · 1080p»: cuánto falta y la versión, en un solo texto gris.
    @ViewBuilder private func status(_ left: Text?, _ version: Text?) -> some View {
        if let text = Self.join(left, version) {
            text.recipe(.footnote, color: DS.textMuted).lineLimit(1)
                .accessibilityLabel(version == nil ? text : Self.join(left, versionLabel ?? version) ?? text)
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
        if restart != nil { Spacer(minLength: 0); restartButton }
    }

    @ViewBuilder private var restartButton: some View {
        if let restart {
            Button("Desde el principio", systemImage: "arrow.counterclockwise", action: restart)
                .font(DS.TextRecipe.footnote.font.weight(.medium)).buttonStyle(.borderless).tint(tint).lineLimit(1)
                .accessibilityIdentifier("title-restart")
        }
    }
}
