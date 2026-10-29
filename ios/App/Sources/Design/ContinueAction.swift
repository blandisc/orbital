import SwiftUI

/// El botón principal de la ficha y lo que lo acompaña. El botón dice una sola cosa («▶ Continuar», «▶ Ver T2 E6», «Cargando»);
/// debajo, a su tamaño, el avance con cuánto falta, la versión que va a sonar («🇲🇽 Latino · 1080p») y «Desde el principio»,
/// como Apple TV y Netflix. Antes los tres iban dentro del botón: la barrita encimada al texto de la versión y ese texto encogido
/// para caber (opción A del 29 oct).
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

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Button(action: play) { label }
                .dsSolidPrimaryButton().disabled(!enabled)
                .accessibilityIdentifier("title-play")
            if let progress {
                HStack(spacing: DS.Space.s3) {
                    DSProgress(fraction: progress)
                    if let left { left.recipe(.footnote, color: DS.textMuted).lineLimit(1).layoutPriority(1) }
                }
                .padding(.horizontal, DS.Space.s1)
            }
            if version != nil || restart != nil {
                // Con letra grande no caben en un renglón: uno debajo del otro.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s3) { versionText; if restart != nil { Spacer(minLength: 0) }; restartButton }
                    VStack(spacing: DS.Space.s2) { versionText; restartButton }
                }
                .padding(.horizontal, DS.Space.s1)
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

    @ViewBuilder private var versionText: some View {
        if let version {
            version.recipe(.footnote, color: DS.textMuted).lineLimit(1)
                .accessibilityLabel(versionLabel ?? version)
        }
    }

    @ViewBuilder private var restartButton: some View {
        if let restart {
            Button("Desde el principio", systemImage: "arrow.counterclockwise", action: restart)
                .font(DS.TextRecipe.footnote.font).buttonStyle(.borderless).tint(DS.textMuted).lineLimit(1)
                .accessibilityIdentifier("title-restart")
        }
    }
}
