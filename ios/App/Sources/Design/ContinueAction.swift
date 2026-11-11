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
    /// Aún buscando versión: el renglón con su forma en gris (esqueleto), no «Buscando versión…» en letras.
    var versionPending = false
    /// Lo que lee VoiceOver en vez de `version` (sin las banderas).
    var versionLabel: Text?
    let play: () -> Void
    /// «Desde el principio»: solo si ibas a medias.
    var restart: (() -> Void)?
    /// La otra salida a la derecha cuando no hay «Desde el principio» (Real-Debrid, R2-A y R13): «Verlo en inglés al
    /// instante» o «Cancelar pedido». Mismo lugar y mismo estilo: una acción en color.
    var aside: (title: Text, symbol: String, action: () -> Void)?
    /// N5-A · por qué «Ver» no es la de un idioma que va antes en tu orden («La de inglés pesa 64 GB y aquí no se ve bien»):
    /// un renglón aparte, debajo de la versión.
    var why: Text?
    /// IOS-9 · el renglón de abajo dice un problema (atorado, rechazado): en ámbar, mientras el botón dice la acción.
    var warn = false
    /// I7 · tocar la versión («🇲🇽 · 1080p ›») abre «Versión»: antes era un cuarto botón abajo. nil: el renglón solo informa.
    var versions: (() -> Void)?
    /// El color de «Desde el principio»: el del arte, como los mosaicos de abajo.
    var tint: Color = DS.accent
    @Environment(\.colorScheme) private var scheme
    /// En claro, el color del arte se oscurece como en las acciones de abajo (`TitleActions`): el tono claro sobre papel no se leía.
    private var ink: Color { scheme == .light ? tint.mix(with: DS.backdropDeep, by: DS.TitleAction.lightDeepen) : tint }

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            Button(action: play) { label }
                .dsSolidPrimaryButton().disabled(!enabled)
                .accessibilityIdentifier("title-play")
                .coachAnchor("title-play")   // F3: el aviso con foco de la ficha señala este botón
            if let progress { DSProgress(fraction: progress).padding(.top, DS.Space.s1) }
            if versionPending {
                // «quedan…» y «Desde el principio» como siempre; solo la versión, en gris con su forma.
                HStack(spacing: DS.Space.s3) {
                    status(leftText, nil)
                    Text(verbatim: "🇲🇽 · 1080p · CC").recipe(.footnote).redacted(reason: .placeholder)
                        .accessibilityLabel(Text("Buscando versión"))
                    if restart == nil && aside == nil { Spacer(minLength: 0) }
                    restartRow
                }
            } else if left != nil || version != nil || restart != nil || aside != nil {
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

    private var leftText: Text? { left }
    private var versionText: Text? { version }

    /// «quedan 50 min · 🇺🇸 Inglés · 1080p»: cuánto falta y la versión, en un solo texto gris.
    @ViewBuilder private func status(_ left: Text?, _ version: Text?) -> some View {
        if let version, let versions {
            // La versión se toca: con su flechita, del alto de un dedo, y VoiceOver dice que abre «Versión».
            Button(action: versions) {
                HStack(spacing: DS.Space.s1) {
                    statusText(left, version)
                    Image(systemName: "chevron.forward").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).accessibilityHidden(true)
                }
                .frame(minHeight: DS.Size.touchTarget).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Toca para elegir otra versión"))
            .accessibilityIdentifier("title-sources")
        } else {
            statusText(left, version)
        }
    }

    @ViewBuilder private func statusText(_ left: Text?, _ version: Text?) -> some View {
        if let text = Self.join(left, version) {
            // Solo la versión (sin «quedan…»): hasta dos renglones («Muchas descargas activas · Lo vuelvo a pedir cuando se
            // libere un lugar» se cortaba a la mitad).
            text.recipe(.footnote, color: warn ? DS.warning : DS.textMuted).lineLimit(left == nil ? 2 : 1)
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
