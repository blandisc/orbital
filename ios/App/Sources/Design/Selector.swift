import SwiftUI

/// El selector de Orbital, la misma pieza en toda la app (SL1, Fernando, 13 nov 2026: «vamos con el selector unificado»).
/// Elige **qué ves aquí**: un riel de vidrio con las opciones a lo ancho y la elegida rellena (el blanco de la marca, que viaja
/// de una a otra). Las pestañas subrayadas (`DSTextTabs`) quedan solo para **moverte entre partes** (Biblioteca, la ficha, el
/// reproductor); el tipo (Todo · Películas · Series) es su tamaño compacto, la pastilla `DSKindFilter`, que dice el nombre de
/// lo elegido (KT1).
///
/// - `full`: ícono, cifra y nombre (Guardado: «Mi lista · 11»). Si no caben, se van los nombres; el ícono y la cifra nunca.
/// - `regular`: nombre, con su ícono si lo trae (Decide por mí, Lo que ves, Ajustes, Versión). Si no cabe a lo ancho, se
///   desliza entero en vez de cortarse.
///
/// Antes eran cinco caras: pestañas con cifra (`DSCountTabs`), el segmentado de iOS (`DSSegmented`), pestañas subrayadas para
/// elegir y otra para el tipo en Mi media. `testOneSelectorEverywhere` cuida que no vuelvan.
struct DSSelector<ID: Hashable>: View {
    struct Option {
        let id: ID
        let title: Text
        var symbol: String?
        /// La cifra junto al ícono (`full`). `.some(nil)`: todavía llega (sale «–», del mismo ancho: el riel no brinca).
        var count: Int??
        var identifier: String?

        init(id: ID, title: Text, symbol: String? = nil, count: Int?? = nil, identifier: String? = nil) {
            self.id = id; self.title = title; self.symbol = symbol; self.count = count; self.identifier = identifier
        }
    }
    enum Size { case full, regular }

    /// Solo nombres, en el orden dado (Ajustes, el filtro avanzado, Tu Orbital): lo que antes era el segmentado de iOS.
    init(choices: [(ID, LocalizedStringKey)], selection: Binding<ID>) {
        self.init(options: choices.map { Option(id: $0.0, title: Text($0.1)) }, selection: selection)
    }

    init(options: [Option], selection: Binding<ID>, size: Size = .regular, adapts: Bool = true) {
        self.options = options; _selection = selection; self.size = size; self.adapts = adapts
    }

    let options: [Option]
    @Binding var selection: ID
    var size: Size = .regular
    /// En falso, sin `ViewThatFits`: una sola forma (con letra de accesibilidad, solo íconos si los hay). Para encabezados que se
    /// miden muy seguido, como el de una hoja que cambia de alto (Decide por mí): ahí medir varias formas en cada pasada colgaba
    /// la app (como `DSTextTabs.adapts`).
    var adapts = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var mark

    var body: some View {
        Group {
            if adapts { fitted } else { track(names: !(typeSize.isAccessibilitySize && options.allSatisfy { $0.symbol != nil }), equal: true) }
        }
        .dsFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
    }

    private var fitted: some View {
        ViewThatFits(in: .horizontal) {
            track(names: true, equal: true)
            if options.allSatisfy({ $0.symbol != nil }) { track(names: false, equal: true) }
            ScrollView(.horizontal, showsIndicators: false) { track(names: true, equal: false) }
                .scrollClipDisabled()   // lo que crece al picarlo (o al dejarlo apretado) no se corta en la orilla del listón
        }
    }

    private var cellRadius: CGFloat { size == .full ? DS.Radius.lg : DS.Radius.pill }

    private func track(names: Bool, equal: Bool) -> some View {
        HStack(spacing: DS.Space.s1 / 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in cell(option, names: names, equal: equal) }
        }
        .padding(DS.Space.s1 / 2)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cellRadius + DS.Space.s1 / 2, style: .continuous))
        .frame(maxWidth: equal ? DS.Size.segmentedMax : nil, alignment: .leading)
        .fixedSize(horizontal: !equal, vertical: false)
    }

    private func cell(_ option: Option, names: Bool, equal: Bool) -> some View {
        let on = option.id == selection
        let shape = RoundedRectangle(cornerRadius: cellRadius, style: .continuous)
        return Button { withAnimation(DS.Motion.fold(reduceMotion)) { selection = option.id } } label: {
            label(option, names: names, on: on)
                .foregroundStyle(on ? DS.bg : DS.textMuted)
                .padding(.vertical, size == .full ? DS.Space.s1 : DS.Space.s2)
                .padding(.horizontal, DS.Space.s3)
                .frame(maxWidth: equal ? .infinity : nil, minHeight: DS.Size.touchTarget)
                .background {
                    if on { shape.fill(DS.text).matchedGeometryEffect(id: "mark", in: mark) }
                }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityName(option))
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier(option.identifier ?? "")
    }

    @ViewBuilder private func label(_ option: Option, names: Bool, on: Bool) -> some View {
        switch size {
        case .full:
            VStack(spacing: 0) {
                HStack(spacing: DS.Space.s1) {
                    if let symbol = option.symbol { Image(systemName: symbol).imageScale(.small).accessibilityHidden(true) }
                    if let count = option.count {
                        Group { if let count { Text(count, format: .number) } else { Text(verbatim: "–") } }
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .font(DS.TextRecipe.cardTitle.font)
                if names { weighted(option.title, on: on).font(DS.TextRecipe.footnote.font) }
            }
        case .regular:
            HStack(spacing: DS.Space.s1) {
                if let symbol = option.symbol { Image(systemName: symbol).accessibilityHidden(true) }
                if names { weighted(option.title, on: on) }
            }
            .font(DS.TextRecipe.label.font)
        }
    }

    /// La elegida en negrita; la gruesa escondida guarda el lugar para que nada brinque al cambiar.
    private func weighted(_ title: Text, on: Bool) -> some View {
        ZStack {
            title.fontWeight(.bold).hidden()   // ds-exception: la elegida se distingue por el peso
            title.fontWeight(on ? .bold : .medium)   // ds-exception: la elegida se distingue por el peso
        }
        .lineLimit(1)
    }

    private func accessibilityName(_ option: Option) -> Text {
        guard let count = option.count, let count else { return option.title }
        return Text("\(option.title), \(count)")
    }
}
