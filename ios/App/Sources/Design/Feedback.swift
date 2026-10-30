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
