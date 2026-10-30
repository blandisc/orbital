import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Lo que le dice la app a quien la usa: el aviso en línea, el selector segmentado y el estado vacío.
/// Un aviso corto con su color (sin conexión, error).
struct DSNotice: View {
    /// El tono es el de los avisos del paquete (`NoticeTone`): la cola de avisos no conoce SwiftUI.
    typealias Tone = NoticeTone
    let text: Text
    var tone: Tone = .info

    init(text: LocalizedStringKey, tone: Tone = .info) { self.text = Text(text); self.tone = tone }
    /// Un texto ya en el idioma de la app (un error o aviso traducido con `Strings.message`): tal cual, sin buscarlo otra vez.
    init(verbatim: String, tone: Tone = .info) { self.text = Text(verbatim: verbatim); self.tone = tone }

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: symbol)
            text.font(DS.TextRecipe.footnote.font).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var symbol: String {
        switch tone { case .info: "info.circle"; case .success: "checkmark.circle.fill"; case .warn: "exclamationmark.triangle"; case .error: "exclamationmark.triangle.fill" }
    }

    private var color: Color {
        switch tone { case .info: DS.textMuted; case .success: DS.good; case .warn: DS.warning; case .error: DS.danger }
    }
}

/// Cuando algo no llegó: la causa de verdad (sin internet, un servicio que no contesta, algo sin conectar), qué sigue
/// funcionando y la salida («Tus descargas», «Intentar de nuevo», «Abrir Ajustes»). Es el aviso del modo degradado
/// (`docs/producto/modo-degradado.md`); `DSNotice` queda para avisos de una línea sin salida.
struct DSDegradedNotice: View {
    let state: Degraded
    /// El texto en el idioma de la app (`env.message`): la pieza no lee el estado de la app.
    let text: (String) -> String
    /// La salida principal («Tus descargas», «Intentar de nuevo», «Abrir Ajustes»).
    let act: () -> Void
    /// «Intentar de nuevo» al lado, cuando la salida principal es otra; nil: no se ofrece.
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Label { Text(verbatim: text(state.title)).font(DS.TextRecipe.footnote.font.weight(.semibold)) } icon: { Image(systemName: state.symbol) }
                .foregroundStyle(color)
            Text(verbatim: text(state.detail)).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.s2) {
                Button(text(state.actionTitle), systemImage: actionSymbol, action: act).accessibilityIdentifier("degraded-action")
                // Sin internet la salida es Descargas; reintentar va al lado (la red pudo volver).
                if state.action != .retry, let retry {
                    Button(text("Intentar de nuevo"), systemImage: "arrow.clockwise", action: retry).accessibilityIdentifier("degraded-retry")
                }
            }
            .buttonStyle(.glass).controlSize(.small).padding(.top, DS.Space.s1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("degraded-notice")
    }

    private var actionSymbol: String {
        switch state.action { case .retry: "arrow.clockwise"; case .settings: "gearshape"; case .downloads: "arrow.down.circle" }
    }

    private var color: Color {
        switch state { case .notConnected: DS.accent; case .offline, .down: DS.warning }
    }
}

/// Selector segmentado: el control nativo de iOS (`Picker` con `.segmented`), que en iOS 26 ya es de vidrio.
struct DSSegmented<Value: Hashable>: View {
    let options: [(Value, LocalizedStringKey)]
    @Binding var selection: Value
    /// El valor actual como dato de la vista: con un `Binding(get:set:)` SwiftUI no ve el cambio y no la vuelve a pintar.
    private let current: Value

    init(options: [(Value, LocalizedStringKey)], selection: Binding<Value>) {
        self.options = options; _selection = selection; current = selection.wrappedValue
    }

    var body: some View {
        Picker(selection: $selection) {
            ForEach(options.indices, id: \.self) { Text(options[$0].1).tag(options[$0].0) }
        } label: { EmptyView() }
        .pickerStyle(.segmented)
        .frame(maxWidth: DS.Size.segmentedMax)   // en ventana ancha no se estira de orilla a orilla
        .sensoryFeedback(.selection, trigger: current)
    }
}

/// Cuando un área entera no tiene nada (Descargas vacía, sin resultados, nada con estos filtros): siempre esto, el vacío nativo
/// de iOS con un ícono, qué pasa y, si lo hay, qué hacer. Regla de la app: un área vacía → `DSEmptyState`; un renglón vacío
/// dentro de una sección → texto chico; un error o sin conexión → `DSNotice`.
struct DSEmptyState<Actions: View>: View {
    let symbol: String
    let title: Text
    var message: Text?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ContentUnavailableView {
            Label { title } icon: { Image(systemName: symbol) }
        } description: {
            if let message { message }
        } actions: {
            actions().buttonStyle(.glass).controlSize(.large)
        }
    }
}

extension DSEmptyState where Actions == EmptyView {
    init(symbol: String, title: Text, message: Text? = nil) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
