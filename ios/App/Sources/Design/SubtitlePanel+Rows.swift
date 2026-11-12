import SwiftUI
import OrbitalCore

// «Audio y subtítulos» en renglones con palomita (S1, Fernando, 11 nov 2026: «Me gusta tu propuesta S1»). Antes eran cápsulas
// y acordeones que se partían en dos filas desalineadas y medían distinto; ahora todo es un renglón de la misma pieza, como la
// TV (renglones con ✓) y como la página «Versión» del mismo panel. La regla vive en `docs/ios-interfaz.md` § «Opciones que se
// eligen» y la cuida `DesignRulesTests+Subtitles`.

/// Lo que va a la izquierda de un renglón: un símbolo o la bandera del idioma, siempre en la misma columna fija.
enum SubtitleLead: Equatable {
    case symbol(String)
    case flag(String)
}

/// Lo que va a la derecha, en la columna fija de la palomita: nada, la palomita (lo elegido), la ruedita (cargando o buscando)
/// o la flechita (abre otra lista).
enum SubtitleMark: Equatable { case none, check, loading, opens }

/// Un renglón de «Audio y subtítulos»: ícono o bandera, el nombre y su segunda línea gris, y a la derecha la palomita o los
/// pasos («−» «+»). Alto mínimo de un objetivo táctil; con o sin bandera, elegido o no, mide y se alinea igual (las dos columnas
/// son fijas). `below` es una segunda fila del mismo renglón, alineada con el nombre (‹ 1 de 2 › de las versiones).
struct SubtitleRow: View {
    let lead: SubtitleLead
    let title: Text
    var detail: Text?
    var mark: SubtitleMark = .none
    /// Apagado (sin conexión): se ve tenue y no se toca.
    var dimmed = false
    /// El nombre lleva una flechita: tocarlo abre una lista (las versiones del idioma puesto).
    var opensList = false
    var identifier: String?
    var action: (() -> Void)?
    var trailing: AnyView?
    var below: AnyView?
    /// VoiceOver: lo elegido, lo que dice además del nombre, la pista, «−»/«+» como control ajustable y las versiones
    /// anterior y siguiente como acciones (el renglón es un solo elemento: «Español, seleccionado, versión 1 de 2»).
    var selected = false
    var spoken: String?
    var hint: LocalizedStringKey?
    var adjust: ((Int) -> Void)?
    var versionStep: ((Int) -> Void)?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Dónde empieza el texto (la raya entre renglones y la segunda fila arrancan ahí).
    static let textInset = DS.Space.s3 + DS.PlayerPanel.rowLead + DS.Space.s3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.s2) {
                main
                if let trailing { trailing }
            }
            if let below {
                below.padding(.leading, Self.textInset - DS.Space.s3).padding(.bottom, DS.Space.s2)   // arriba ya lleva el aire del renglón; abajo, el mismo s2
            }
        }
        .padding(.horizontal, DS.Space.s3)
        .accessibilityElement(children: .contain)
    }

    /// El ícono, el nombre y su segunda línea (y la palomita): un botón si hace algo; si no, solo dice.
    @ViewBuilder private var main: some View {
        if let action, !dimmed {
            Button(action: action) { label }.buttonStyle(.plain).modifier(SpokenRow(row: self))
        } else {
            label.modifier(SpokenRow(row: self))
        }
    }

    private var label: some View {
        HStack(spacing: DS.Space.s3) {
            leadView
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                titleText.recipe(.labelLarge, color: dimmed ? DS.textFaint : DS.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    detail.recipe(.footnote, color: dimmed ? DS.textFaint : DS.textMuted)
                        .lineLimit(typeSize.isAccessibilitySize ? 4 : 2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if trailing == nil { markView }
        }
        .padding(.vertical, DS.Space.s2)
        .frame(minHeight: DS.Size.touchTarget)
        .contentShape(Rectangle())
    }

    private var titleText: Text {
        guard opensList else { return title }
        let chevron = Text(Image(systemName: "chevron.right")).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted)
        return Text("\(title) \(chevron)")
    }

    @ViewBuilder private var leadView: some View {
        Group {
            switch lead {
            case .symbol(let symbol):
                Image(systemName: symbol).font(DS.TextRecipe.label.font).foregroundStyle(dimmed ? DS.textFaint : DS.textMuted)
            case .flag(let code):
                if let flag = Text.flagMark(code) { flag.font(DS.TextRecipe.labelLarge.font).opacity(dimmed ? DS.Opacity.dimmed : 1) }
                else { Image(systemName: "globe").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted) }
            }
        }
        .frame(width: DS.PlayerPanel.rowLead)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var markView: some View {
        Group {
            switch mark {
            case .none: Color.clear
            case .check: Image(systemName: DS.Symbol.done).font(DS.TextRecipe.label.font).foregroundStyle(DS.brandMoon)
            case .loading: ProgressView().controlSize(.small).tint(DS.textMuted)
            case .opens: Image(systemName: "chevron.right").font(DS.TextRecipe.badge.font).foregroundStyle(DS.textMuted)
            }
        }
        .frame(width: DS.PlayerPanel.rowMark)
        .accessibilityHidden(true)
    }
}

/// Lo que VoiceOver dice y hace con el renglón (ver `SubtitleRow.spoken`).
private struct SpokenRow: ViewModifier {
    let row: SubtitleRow
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(row.selected ? .isSelected : [])
            .accessibilityValue(Text(verbatim: row.spoken ?? ""))
            .accessibilityHint(row.hint.map { Text($0) } ?? Text(verbatim: ""))
            .accessibilityIdentifier(row.identifier ?? "")
            .modifier(Adjustable(adjust: row.adjust, versionStep: row.versionStep))
    }
}

/// «−»/«+» como control ajustable (deslizar arriba o abajo con VoiceOver) y ‹ › como acciones, solo donde los hay.
private struct Adjustable: ViewModifier {
    let adjust: ((Int) -> Void)?
    let versionStep: ((Int) -> Void)?
    func body(content: Content) -> some View {
        if let adjust {
            content.accessibilityAdjustableAction { adjust($0 == .increment ? 1 : -1) }
        } else if let versionStep {
            content
                .accessibilityAction(named: Text("Versión anterior")) { versionStep(-1) }
                .accessibilityAction(named: Text("Versión siguiente")) { versionStep(1) }
        } else { content }
    }
}

/// «−» y «+» (o ‹ ›): dos botones redondos de marco fijo, del mismo tamaño. Mantener presionado repite (sincronía, tamaño).
/// Sin vibrar: el reproductor no vibra mientras ves (Fernando, 29 oct 2026).
struct SubtitleSteps: View {
    let back: String
    let forward: String
    let backLabel: LocalizedStringKey
    let forwardLabel: LocalizedStringKey
    var canBack = true
    var canForward = true
    var repeats = false
    /// Lo que va entre los dos («1 de 2»); nil: van juntos.
    var value: Text?
    var backID: String?
    var forwardID: String?
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            DSIconButton(symbol: back, label: backLabel, steady: true, repeats: repeats) { step(-1) }
                .disabled(!canBack).accessibilityIdentifier(backID ?? "")
            if let value {
                value.recipe(.footnote, color: DS.text).monospacedDigit().lineLimit(1).fixedSize()
                    .frame(minWidth: DS.Size.touchTarget)
            }
            DSIconButton(symbol: forward, label: forwardLabel, steady: true, repeats: repeats) { step(1) }
                .disabled(!canForward).accessibilityIdentifier(forwardID ?? "")
        }
    }
}
