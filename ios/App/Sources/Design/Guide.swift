import SwiftUI

/// Piezas de la guía de la primera vez (`Screens/Onboarding/`) y de Ajustes › Cuentas. No leen el estado de la app:
/// reciben sus datos y avisan lo que se toca.

/// Las rayitas de arriba: en qué paso vas.
struct GuideSteps: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: DS.Space.s1) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule().fill(i <= current ? DS.accent : DS.fill).frame(height: DS.Guide.stepBar)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Paso \(String(current + 1)) de \(String(total))"))
    }
}

/// Una página de la guía: título, una frase, lo propio de la página y, abajo y siempre a la mano, el botón para seguir (con
/// «Ahora no» si el paso se puede saltar).
struct GuidePage<Content: View>: View {
    let title: Text
    var message: Text?
    var step: (current: Int, total: Int)?
    var primary: Text = Text("Continuar")
    var primaryEnabled = true
    var secondary: Text?
    let next: () -> Void
    var skip: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                if let step { GuideSteps(current: step.current, total: step.total) }
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    title.font(DS.TextRecipe.display.font).foregroundStyle(DS.text)
                    if let message { message.font(DS.TextRecipe.body.font).foregroundStyle(DS.textMuted) }
                }
                content
            }
            .padding(DS.Space.s6)
            .frame(maxWidth: DS.Guide.readable, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DS.Space.s2) {
                Button(action: next) { primary.frame(maxWidth: .infinity) }
                    .dsPrimaryButton().controlSize(.large).disabled(!primaryEnabled)
                    .accessibilityIdentifier("guide-next")
                if let skip, let secondary {
                    Button(action: skip) { secondary.frame(maxWidth: .infinity) }.buttonStyle(.glass).controlSize(.large)
                        .accessibilityIdentifier("guide-skip")
                }
            }
            .padding(.horizontal, DS.Space.s6).padding(.bottom, DS.Space.s3)
            .frame(maxWidth: DS.Guide.readable)
        }
        .background(Backdrop())
        .navigationBarBackButtonHidden(step == nil)
    }
}

/// Una pieza de Orbital (o una cuenta): su ícono en su color, qué es, una línea de cómo está y, a la derecha, una etiqueta
/// («Obligatorio», «143 días», «No conectada»).
struct GuidePiece: View {
    let symbol: String
    let tint: Color
    let title: Text
    var detail: Text?
    var tag: Text?

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: symbol).font(DS.TextRecipe.section.font).foregroundStyle(tint)
                .frame(width: DS.Guide.pieceIcon, height: DS.Guide.pieceIcon)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                title.font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
                if let detail { detail.font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: DS.Space.s2)
            if let tag { tag.font(DS.TextRecipe.eyebrow.font).foregroundStyle(DS.textMuted) }
        }
        .padding(DS.Space.s4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .combine)
    }
}

/// Un paso numerado («1 · Abre la página»), con algo a la derecha si hace falta (un botón «Abrir»).
struct GuideNumberedStep<Accessory: View>: View {
    let number: Int
    let text: Text
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            Text(verbatim: "\(number)").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.onPrimary)
                .frame(width: DS.Guide.stepNumber, height: DS.Guide.stepNumber)
                .background(DS.accent, in: Circle())
            text.font(DS.TextRecipe.body.font).foregroundStyle(DS.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.Space.s2)
            accessory
        }
        .accessibilityElement(children: .combine)
    }
}

/// El código para escribir en trakt.tv/activate: grande y espaciado, para leerlo desde otro aparato.
struct GuideCode: View {
    let code: String

    var body: some View {
        Text(verbatim: code).font(DS.TextRecipe.display.font.monospaced()).tracking(DS.Guide.codeTracking)
            .foregroundStyle(DS.text).textSelection(.enabled)
            .frame(maxWidth: .infinity).padding(DS.Space.s5)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
            .accessibilityLabel(Text(verbatim: code.map(String.init).joined(separator: " ")))
    }
}

/// Un complemento: su nombre y, debajo, qué aporta («Usa tu Real-Debrid», «Subtítulos») y si se importó.
struct AddonLabel: View {
    let name: String
    let usesDebrid: Bool
    let subtitles: Bool
    let imported: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: name).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
            detail.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
        }
    }

    private var detail: Text {
        let what = usesDebrid ? Text("Usa tu Real-Debrid") : subtitles ? Text("Subtítulos") : Text("Fuentes y listas")
        return imported ? Text("\(what) · \(Text("Importado"))") : what
    }
}

/// La ilustración de una página del tutorial de Orbital: un recuadro con un ícono grande en su color y, si hace falta, lo
/// que se toca de verdad debajo (los botones «Ver» y «Ver en la TV»).
struct GuideArt<Detail: View>: View {
    let symbol: String
    let tint: Color
    @ViewBuilder var detail: Detail

    var body: some View {
        VStack(spacing: DS.Space.s4) {
            Image(systemName: symbol).font(.system(size: DS.Guide.artSymbol)).foregroundStyle(tint)   // ds-exception: un dibujo, no texto: no crece con Dynamic Type
            detail
        }
        .frame(maxWidth: .infinity, minHeight: DS.Guide.artHeight)
        .padding(DS.Space.s4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityHidden(true)   // es adorno: el título y la frase de la página ya lo dicen
    }
}
