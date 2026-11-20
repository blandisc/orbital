import SwiftUI

/// Piezas de la guía de la primera vez (`Screens/Onboarding/`) y de Ajustes › Cuentas. No leen el estado de la app:
/// reciben sus datos y avisan lo que se toca.

/// La barra de avance de la guía: un arco fino con una marca por paso; la luna turquesa avanza a la tuya con un resorte
/// (la misma luna que atrapó los pósters en la bienvenida). Sin texto.
struct GuideSteps: View {
    let current: Int
    let total: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let count = max(total, 2)
            ZStack {
                OrbitArcShape().stroke(DS.fill, lineWidth: DS.Stroke.regular)
                ForEach(0..<count, id: \.self) { i in
                    Circle().fill(i < current ? DS.textMuted : DS.fill)
                        .frame(width: DS.OrbitArc.mark, height: DS.OrbitArc.mark)
                        .position(OrbitArcShape.point(Double(i) / Double(count - 1), in: geo.size))
                }
                Circle().fill(DS.brandMoon)
                    .frame(width: DS.OrbitArc.moon, height: DS.OrbitArc.moon)
                    .position(OrbitArcShape.point(Double(min(current, count - 1)) / Double(count - 1), in: geo.size))
                    .animation(DS.Motion.smooth(reduceMotion), value: current)
            }
        }
        .frame(height: DS.OrbitArc.height)
        .accessibilityElement()
        .accessibilityLabel(Text("Paso \(String(current + 1)) de \(String(total))"))
    }
}

/// El arco de la barra de avance: una curva suave, más alta al centro.
struct OrbitArcShape: Shape {
    static func point(_ f: Double, in size: CGSize) -> CGPoint {
        let inset = DS.OrbitArc.moon / 2
        let x = inset + (size.width - 2 * inset) * f
        let lift = size.height * DS.OrbitArc.bend * (1 - pow(2 * f - 1, 2))
        return CGPoint(x: x, y: size.height - inset - lift)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 40
        for i in 0...steps {
            let p = Self.point(Double(i) / Double(steps), in: rect.size)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

/// Una página de la guía: título, una frase, lo propio de la página y, abajo y siempre a la mano, el botón para seguir (con
/// «Ahora no» si el paso se puede saltar).
struct GuidePage<Content: View>: View {
    /// Sin título, la página lo pone en su contenido (Trakt conectado: la foto va arriba del «Listo»).
    let title: Text?
    var message: Text?
    var step: (current: Int, total: Int)?
    var primary: Text = Text("Continuar")
    var primaryEnabled = true
    var secondary: Text?
    /// Un segundo camino entre el principal y «Ahora no» (tu nube: «Aún no tengo»); «Ahora no» pasa a ser un enlace.
    var alternate: Text?
    var alternateAction: (() -> Void)?
    let next: () -> Void
    var skip: (() -> Void)?
    /// «Saltar» arriba a la derecha: termina la guía desde cualquier paso (nada es obligatorio).
    var skipGuide: (() -> Void)?
    /// La flecha de regresar, arriba a la izquierda (la guía no va en una pila de navegación).
    var back: (() -> Void)?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                if step != nil || skipGuide != nil {
                    HStack(spacing: DS.Space.s4) {
                        if let back {
                            DSIconButton(symbol: "chevron.backward", label: "Atrás", size: .regular, action: back)
                                .accessibilityIdentifier("guide-back")
                        }
                        if let step { GuideSteps(current: step.current, total: step.total) } else { Spacer() }
                        if let skipGuide { GuideSkip(action: skipGuide) }
                    }
                }
                if let title {
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        title.font(DS.TextRecipe.display.font).foregroundStyle(DS.text)
                        if let message { message.font(DS.Welcome.lead).foregroundStyle(DS.textMuted) }
                    }
                }
                content
            }
            .padding(DS.Space.s6)
            .frame(maxWidth: DS.Guide.readable, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaBar(edge: .bottom) {
            // Al centro de la ventana y no más anchos que `buttonWidth` (en la Mac quedaban pegados a la izquierda; Fernando,
            // 17 nov 2026: «los botones estén centrados»).
            VStack(spacing: DS.Space.s2) {
                Button(action: next) { primary.frame(maxWidth: .infinity) }
                    .dsPrimaryButton().dsControlSize(.large).disabled(!primaryEnabled)
                    .accessibilityIdentifier("guide-next")
                if let alternate, let alternateAction {
                    Button(action: alternateAction) { alternate.frame(maxWidth: .infinity) }.dsGlassButton().dsControlSize(.large)
                        .accessibilityIdentifier("guide-alt")
                }
                if let skip, let secondary {
                    if alternate != nil {
                        Button(action: skip) { secondary.recipe(.label, color: DS.textMuted).frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("guide-skip")
                    } else {
                        Button(action: skip) { secondary.frame(maxWidth: .infinity) }.dsGlassButton().dsControlSize(.large)
                            .accessibilityIdentifier("guide-skip")
                    }
                }
            }
            .frame(maxWidth: DS.Welcome.buttonWidth)
            .padding(.horizontal, DS.Space.s6).padding(.bottom, DS.Space.s2)
            .frame(maxWidth: .infinity)
        }
        .background(Backdrop())
        .navigationBarBackButtonHidden(step == nil)
    }
}

/// «Saltar» de la guía: siempre a la vista, con su ícono.
struct GuideSkip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label("Saltar", systemImage: "forward.end").labelStyle(.titleAndIcon) }
            .buttonStyle(.borderless).foregroundStyle(DS.textMuted)
            .accessibilityIdentifier("guide-skip-all")
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
        HStack(alignment: .top, spacing: DS.Space.s2) {
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
        .dsCard()
        .accessibilityElement(children: .combine)
    }
}

/// Un paso numerado («1 · Abre la página»), con algo a la derecha si hace falta (un botón «Abrir»).
struct GuideNumberedStep<Accessory: View>: View {
    let number: Int
    let text: Text
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: DS.Space.s2) {
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
            .frame(maxWidth: .infinity).padding(DS.Space.s6)
            .dsCard()
            .accessibilityLabel(Text(verbatim: code.map(String.init).joined(separator: " ")))
    }
}

/// Conectar una cuenta con un código (Trakt, Real-Debrid, OneDrive): la misma pantalla en Ajustes y en la guía (17 nov 2026,
/// Fernando: «dale una pulida a la pantalla donde se mete el código»; antes cada cuenta lo decía y lo acomodaba distinto). Dónde
/// escribirlo, el código grande, un botón que lo copia y abre la página, y que estamos esperando.
struct DeviceCodeCard: View {
    /// El nombre de la cuenta para el botón («Copiar y abrir Trakt»).
    let service: String
    let code: String
    let url: URL?
    /// Con su botón «Copiar y abrir». En la guía de Trakt no: ahí es el botón principal de la página (G5-B, 18 nov 2026).
    var showsOpen = true
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("Escribe este código en \(Text(verbatim: Self.site(url)).bold())").recipe(.secondary, color: DS.textMuted)
            GuideCode(code: code)
            if showsOpen, let url {
                Button("Copiar y abrir \(service)", systemImage: "arrow.up.forward.app") { Self.copyAndOpen(code, url, openURL) }
                .dsGlassButton()
            }
            DSInlineProgress(text: Text("Esperando a que lo apruebes…"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Copia el código y abre su página (en el mismo aparato: allá solo se pega).
    static func copyAndOpen(_ code: String, _ url: URL, _ openURL: OpenURLAction) {
        UIPasteboard.general.string = code
        openURL(url)
    }

    /// «auth.trakt.tv/activate»: la dirección sin «https://» ni la diagonal del final, como se escribe.
    static func site(_ url: URL?) -> String {
        guard let url else { return "" }
        let text = url.absoluteString.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        return text.hasSuffix("/") ? String(text.dropLast()) : text
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
        .dsCard()
        .accessibilityHidden(true)   // es adorno: el título y la frase de la página ya lo dicen
    }
}
