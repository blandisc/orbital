import SwiftUI
import OrbitalCore

/// La regla de años de Época (el diseño que Fernando eligió el 29 oct 2026 y regresó el 31): una rayita por año, más larga
/// cada cinco y cada diez, y una ventana blanca con lo elegido. Se arrastra la ventana entera o sus orillas; tocar fuera de
/// ella acerca la orilla más cercana; tocar una década abajo la elige entera (otra vez, la quita). Con VoiceOver se mueve
/// la ventana de año en año.
struct YearRuler: View {
    @Binding var years: ClosedRange<Int>?
    let first: Int
    let last: Int
    @State private var drag: Mode?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode: Equatable { case lower, upper, move(offset: Int, length: Int) }

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
                let r = years ?? (last - 9)...last
                let step = direction == .increment ? 1 : -1
                guard r.lowerBound + step >= first, r.upperBound + step <= last else { return }
                years = (r.lowerBound + step)...(r.upperBound + step)
            }
            .accessibilityIdentifier("filter-year-ruler")
            decades
        }
    }

    /// La ventana con sus dos orillas.
    private func window(_ r: ClosedRange<Int>, _ width: CGFloat) -> some View {
        let left = x(max(r.lowerBound, first), width), right = x(min(r.upperBound, last), width)   // «Clásicos» empieza antes de la regla
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return shape.fill(DS.Filter.windowFill)
            .overlay(shape.strokeBorder(DS.text, lineWidth: DS.Size.hairline * 4))
            .overlay(alignment: .leading) { handle.offset(x: -DS.Filter.handleWidth / 2) }
            .overlay(alignment: .trailing) { handle.offset(x: DS.Filter.handleWidth / 2) }
            .frame(width: max(right - left, DS.Filter.handleWidth), height: DS.Filter.rulerWindow)
            .offset(x: left, y: -DS.Space.s1)
            .shadow(DS.Elevation.low.drop(0))
            .animation(drag == nil ? DS.Motion.base(reduceMotion) : nil, value: r)
    }

    private var handle: some View {
        Capsule().fill(DS.text).frame(width: DS.Filter.handleWidth, height: DS.Filter.handleHeight).shadow(DS.Elevation.medium.drop(0))
    }

    /// Las décadas debajo, cada una centrada en su tramo: tocar una la elige entera.
    private var decades: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ForEach(Array(stride(from: first, through: last, by: 10)), id: \.self) { d in
                let range = d...min(d + 9, last)
                let on = years == range
                Button { years = on ? nil : range } label: {
                    Text(verbatim: "’\(String(format: "%02d", d % 100))")
                        .recipe(.footnote, color: on ? DS.bg : DS.textMuted).fontWeight(.bold).monospacedDigit()
                        .frame(width: DS.Filter.decadeButton, height: DS.Size.touchTarget)
                        .background(on ? DS.text : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
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

    private func x(_ year: Int, _ width: CGFloat) -> CGFloat { CGFloat(year - first) / CGFloat(max(last - first, 1)) * width }
    private func year(_ x: CGFloat, _ width: CGFloat) -> Int { min(last, max(first, first + Int((x / max(width, 1) * CGFloat(last - first)).rounded()))) }

    private func change(_ value: DragGesture.Value, _ width: CGFloat) {
        let y = year(value.location.x, width)
        if drag == nil {
            guard let r = years else {
                // Sin nada elegido, el primer toque pone una década alrededor del dedo.
                let lower = max(first, min(y - 4, last - 9))
                years = lower...min(lower + 9, last)
                drag = .move(offset: y - lower, length: min(9, last - lower))
                return
            }
            let grab = DS.Filter.handleWidth * 1.5
            let start = value.startLocation.x
            if abs(start - x(r.lowerBound, width)) <= grab { drag = .lower }
            else if abs(start - x(r.upperBound, width)) <= grab { drag = .upper }
            else if r.contains(y) { drag = .move(offset: y - r.lowerBound, length: r.upperBound - r.lowerBound) }
            else { drag = abs(y - r.lowerBound) <= abs(y - r.upperBound) ? .lower : .upper }
        }
        guard let r = years, let drag else { return }
        switch drag {
        case .lower: years = min(y, r.upperBound)...r.upperBound
        case .upper: years = r.lowerBound...max(y, r.lowerBound)
        case .move(let offset, let length):
            let lower = max(first, min(last - length, y - offset))
            years = lower...(lower + length)
        }
    }
}
