import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los dos deslizadores de Calificación (Fernando, 2 nov 2026; propuesta en
/// docs/producto/propuestas-2026-11-01/calificacion-deslizador-2.html): la misma función, cada uno en su idioma. El público
/// es una regla del 5 al 9 con el número en la perilla; los cinéfilos, cinco estrellas que se llenan. Del todo a la
/// izquierda es «Sin mínimo». Un puntito marca dónde empieza cada nivel y se enciende al alcanzarlo (con un toquecito en la
/// mano). Qué valor sale del dedo lo decide `RatingSlider` (OrbitalModels, con pruebas); aquí solo se dibuja y se mide.

/// La regla del público: la línea, las rayitas de medio en medio con su número en los enteros, los puntitos de los niveles y
/// la perilla con el número.
struct RatingRulerSlider: View {
    @Binding var value: Double?
    let scale: RatingSlider
    let hue: Color
    let label: Text

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                Capsule().fill(DS.fillStrong).frame(width: w, height: DS.Filter.track)
                    .position(x: w / 2, y: DS.Filter.trackY)
                Capsule().fill(hue).frame(width: x(value, w), height: DS.Filter.track).glow(hue)
                    .position(x: x(value, w) / 2, y: DS.Filter.trackY)
                ForEach(ticks, id: \.self) { v in
                    let whole = v.truncatingRemainder(dividingBy: 1) == 0
                    Rectangle().fill(whole ? DS.Filter.tickStrong : DS.Filter.tickFaint)
                        .frame(width: DS.Stroke.regular, height: whole ? DS.Filter.tickYear : DS.Filter.tickYear / 2)
                        .position(x: x(v, w), y: DS.Filter.tickY + (whole ? DS.Filter.tickYear : DS.Filter.tickYear / 2) / 2)
                    if whole {
                        Text(verbatim: RatingLevels.short(v)).recipe(.caption, color: DS.textMuted).monospacedDigit()
                            .position(x: x(v, w), y: DS.Filter.rulerNumberY)
                    }
                }
                ForEach(scale.stops.indices, id: \.self) { i in
                    // En la línea: blancos sobre lo lleno (como las paradas de iOS), huecos en lo que falta.
                    RatingStopMark(on: (scale.level(value) ?? -1) >= i, hue: DS.text)
                        .position(x: x(scale.stops[i], w), y: DS.Filter.trackY)
                }
                thumb.position(x: min(max(x(value, w), DS.Filter.thumbWidth / 2), w - DS.Filter.thumbWidth / 2), y: DS.Filter.trackY)
            }
            .frame(width: w, height: DS.Filter.ratingRuler)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let next = scale.value(atFraction: Double(g.location.x / max(w, 1)))
                if next != value { value = next }
            })
        }
        .frame(height: DS.Filter.ratingRuler)
        .padding(.horizontal, DS.Filter.thumbWidth / 2)
        .ratingSliderAccessibility(value: $value, scale: scale, label: label, prefix: "")
    }

    private var ticks: [Double] { Array(stride(from: scale.floor, through: scale.ceiling, by: 0.5)) }
    private func x(_ v: Double?, _ w: CGFloat) -> CGFloat { CGFloat(scale.fraction(of: v)) * w }

    /// La perilla blanca con el número («7.5») o «—» sin mínimo.
    private var thumb: some View {
        Text(verbatim: value.map(RatingLevels.short) ?? "—")
            .recipe(.label, color: value == nil ? DS.textMuted : DS.bg).monospacedDigit()
            .padding(.horizontal, DS.Space.s2)
            .frame(minWidth: DS.Filter.thumbWidth, minHeight: DS.Filter.thumbHeight)
            .background(DS.text, in: Capsule())
            .shadow(DS.Elevation.medium.drop(0))
            .contentTransition(.numericText())
    }
}

/// Las estrellas de los cinéfilos: cinco que se llenan (de décima en décima) y, debajo, los puntitos de los niveles.
struct RatingStarSlider: View {
    @Binding var value: Double?
    let scale: RatingSlider
    let hue: Color
    let label: Text
    private let count = 5

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Filter.starGap) {
                ForEach(0..<count, id: \.self) { k in star(filled: min(max((value ?? 0) - Double(k), 0), 1)) }
            }
            ZStack(alignment: .topLeading) {
                ForEach(scale.stops.indices, id: \.self) { i in
                    RatingStopMark(on: (scale.level(value) ?? -1) >= i, hue: hue).offset(x: x(scale.stops[i]) - DS.Filter.dot / 2)
                }
            }
            .frame(width: width, height: DS.Filter.dot, alignment: .topLeading)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            let next = scale.value(atFraction: stars(at: g.location.x) / Double(count))
            if next != value { value = next }
        })
        .ratingSliderAccessibility(value: $value, scale: scale, label: label, prefix: "★")
    }

    private var unit: CGFloat { DS.Filter.star + DS.Filter.starGap }
    private var width: CGFloat { CGFloat(count) * DS.Filter.star + CGFloat(count - 1) * DS.Filter.starGap }

    /// Dónde va un valor (en puntos): la estrella que le toca y cuánto de ella; los huecos entre estrellas no cuentan.
    private func x(_ v: Double) -> CGFloat {
        let k = min(Int(v), count - 1)
        return CGFloat(k) * unit + CGFloat(min(v - Double(k), 1)) * DS.Filter.star
    }

    /// Cuántas estrellas hay bajo el dedo.
    private func stars(at x: CGFloat) -> Double {
        let k = min(max(Int(x / unit), 0), count - 1)
        return Double(k) + Double(min(max((x - CGFloat(k) * unit) / DS.Filter.star, 0), 1))
    }

    private func star(filled: Double) -> some View {
        let shape = Image(systemName: "star.fill").resizable().scaledToFit().frame(width: DS.Filter.star, height: DS.Filter.star)
        return shape.foregroundStyle(DS.fillStrong)
            .overlay(alignment: .leading) {
                shape.foregroundStyle(hue)
                    .mask(alignment: .leading) { Rectangle().frame(width: DS.Filter.star * CGFloat(filled)) }
            }
            .accessibilityHidden(true)
    }
}

/// El puntito donde empieza un nivel: hueco y tenue, o lleno en el color de la opinión si ya lo alcanzas.
struct RatingStopMark: View {
    let on: Bool
    let hue: Color

    var body: some View {
        Circle().fill(on ? hue : DS.surface)
            .overlay(Circle().strokeBorder(on ? hue : DS.textMuted, lineWidth: DS.Stroke.selected))
            .frame(width: DS.Filter.dot, height: DS.Filter.dot)
            .accessibilityHidden(true)
    }
}

private extension View {
    /// VoiceOver lo lee como un ajustable («Muy buena, 7.5 o más»): de nivel en nivel y, pasando Excelente, de medio en medio.
    /// Cada nivel que se alcanza o se deja da un toquecito.
    func ratingSliderAccessibility(value: Binding<Double?>, scale: RatingSlider, label: Text, prefix: String) -> some View {
        sensoryFeedback(.selection, trigger: scale.level(value.wrappedValue))
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(value.wrappedValue.map { v in
                let number = Text(verbatim: prefix + RatingLevels.short(v))
                return scale.level(v).map { Text("\(RatingLevels.name($0)), \(number) o más") } ?? Text("\(number) o más")
            } ?? Text("Sin mínimo"))
            .accessibilityAdjustableAction { direction in value.wrappedValue = scale.step(value.wrappedValue, up: direction == .increment) }
    }
}
