import SwiftUI
import OrbitalCore
import OrbitalModels

/// La regla de años de Época (el diseño que Fernando eligió el 29 oct 2026 y regresó el 31): una rayita por año, más larga
/// cada cinco y cada diez, y una ventana blanca con lo elegido. Se arrastra la ventana entera o sus orillas; tocar fuera de
/// ella acerca la orilla más cercana; tocar una década abajo la elige entera (otra vez, la quita). Con VoiceOver se mueve
/// la ventana de año en año. La ventana es dorada, el color de Época (31 oct 2026). Qué años quedan elegidos lo decide
/// `YearRulerLogic` (OrbitalModels, con pruebas); aquí solo se dibuja y se mide.
struct YearRuler: View {
    @Binding var years: ClosedRange<Int>?
    let first: Int
    let last: Int
    @State private var drag: YearRulerLogic.Drag?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var logic: YearRulerLogic { YearRulerLogic(first: first, last: last) }

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .bottomLeading) {
                    Rectangle().fill(DS.Filter.tickFaint).frame(height: DS.Size.hairline * 2).padding(.bottom, DS.Filter.rulerBase)
                    ForEach(first...last, id: \.self) { y in
                        Rectangle()
                            .fill(y % 10 == 0 ? DS.Filter.tickStrong : y % 5 == 0 ? DS.Filter.tickMid : DS.Filter.tickFaint)
                            .frame(width: DS.Size.hairline * 2, height: y % 10 == 0 ? DS.Filter.tickDecade : y % 5 == 0 ? DS.Filter.tickFive : DS.Filter.tickYear)
                            .offset(x: x(y, width), y: -DS.Filter.rulerBase)
                    }
                    if let years { window(years, width) }
                }
                .frame(width: width, height: geo.size.height, alignment: .bottomLeading)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { change($0, width) }.onEnded { _ in drag = nil })
            }
            .frame(height: DS.Filter.rulerHeight)
            .padding(.horizontal, DS.Filter.handleWidth / 2)
            .accessibilityElement()
            .accessibilityLabel(Text("Años"))
            .accessibilityValue(years.map { Text(verbatim: "\($0.lowerBound)–\($0.upperBound)") } ?? Text("Cualquier año"))
            .accessibilityAdjustableAction { direction in
                let moved = logic.step(years, by: direction == .increment ? 1 : -1)
                if moved != years { years = moved }
            }
            .accessibilityIdentifier("filter-year-ruler")
            decades
        }
    }

    /// La ventana con sus dos orillas.
    private func window(_ r: ClosedRange<Int>, _ width: CGFloat) -> some View {
        let left = x(max(r.lowerBound, first), width), right = x(min(r.upperBound, last), width)   // «Clásicos» empieza antes de la regla
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return shape.fill(DS.Filter.goldFill)
            .overlay(shape.strokeBorder(DS.Filter.gold, lineWidth: DS.Size.hairline * 4))
            .overlay(alignment: .leading) { handle.offset(x: -DS.Filter.handleWidth / 2) }
            .overlay(alignment: .trailing) { handle.offset(x: DS.Filter.handleWidth / 2) }
            // Con uno o dos años la ventana tiene un ancho mínimo (las orillas no se enciman) y no se sale de la regla.
            .frame(width: max(right - left, DS.Filter.windowMin), height: DS.Filter.rulerWindow)
            .offset(x: min(left, width - max(right - left, DS.Filter.windowMin)), y: -DS.Space.s1)
            .shadow(color: DS.Filter.goldGlow, radius: DS.Filter.glowRadius)
            .animation(drag == nil ? DS.Motion.base(reduceMotion) : nil, value: r)
    }

    private var handle: some View {
        Capsule().fill(DS.Filter.gold).frame(width: DS.Filter.handleWidth, height: DS.Filter.handleHeight).shadow(DS.Elevation.medium.drop(0))
    }

    /// Las décadas debajo, cada una centrada en su tramo: tocar una la elige entera.
    private var decades: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ForEach(logic.decades, id: \.lowerBound) { range in
                let d = range.lowerBound
                let on = years == range
                Button { years = logic.toggle(range, in: years) } label: {
                    Text(verbatim: "’\(String(format: "%02d", d % 100))")
                        .recipe(.footnote, color: on ? DS.bg : DS.textMuted).fontWeight(.bold).monospacedDigit()
                        .frame(width: DS.Filter.decadeButton, height: DS.Size.touchTarget)
                        .background(on ? DS.Filter.gold : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .position(x: (x(range.lowerBound, width) + x(range.upperBound, width)) / 2, y: DS.Size.touchTarget / 2)
                .accessibilityLabel(Text(verbatim: Canon.decadeName(d)))
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("filter-decade-\(d)")
            }
        }
        .frame(height: DS.Size.touchTarget)
        .padding(.horizontal, DS.Filter.handleWidth / 2)
        .sensoryFeedback(.selection, trigger: years)
    }

    private func x(_ year: Int, _ width: CGFloat) -> CGFloat { CGFloat(logic.fraction(of: year)) * width }

    /// Mide el dedo (en puntos) y deja que `YearRulerLogic` decida los años.
    private func change(_ value: DragGesture.Value, _ width: CGFloat) {
        let y = logic.year(atFraction: Double(value.location.x / max(width, 1)))
        let grab = DS.Filter.handleWidth * 1.5, start = value.startLocation.x
        let near = { (edge: Int?) in edge.map { abs(start - x($0, width)) <= grab } ?? false }
        let next = logic.change(years, drag: drag, at: y, nearLower: near(years?.lowerBound), nearUpper: near(years?.upperBound))
        if next.years != years { years = next.years }
        drag = next.drag
    }
}
