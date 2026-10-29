import SwiftUI
import OrbitalCore

/// Un día del calendario de estrenos: pintado con el color del arte de lo que sale. Con dos series el mismo día, la casilla
/// se parte en dos (una por serie); con más, las dos primeras y «+N». El número del día, en una pastilla arriba a la
/// derecha (hoy, en el acento); el elegido, con su anillo.
struct CalendarDayCell: View {
    let number: Int
    /// El arte (póster) de cada serie que sale ese día, en orden de hora.
    let art: [String]
    var isToday = false
    var isSelected = false
    var isPast = false

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
        let shape = RoundedRectangle(cornerRadius: DS.ReleaseDays.radius, style: .continuous)
        ZStack(alignment: .topTrailing) {
            HStack(spacing: DS.ReleaseDays.split) {
                if art.isEmpty { DS.fill }
                ForEach(Array(art.prefix(DS.ReleaseDays.maxColors).enumerated()), id: \.offset) { _, url in
                    WithArtColors(url: url) { colors in (colors?.accent ?? DS.fillStrong) }
                }
            }
            .clipShape(shape)
            Text(verbatim: "\(number)")
                .font(DS.TextRecipe.caption.font.weight(.heavy)).monospacedDigit()
                .foregroundStyle(isToday ? DS.onPrimary : DS.text)
                .padding(.horizontal, DS.Space.s1)
                .background(isToday ? DS.accent : (art.isEmpty ? .clear : DS.scrim), in: Capsule())
                .padding(DS.ReleaseDays.inset)
            if art.count > DS.ReleaseDays.maxColors {
                Text(verbatim: "+\(art.count - DS.ReleaseDays.maxColors)")
                    .font(DS.TextRecipe.caption.font.weight(.bold)).foregroundStyle(DS.text)
                    .padding(.horizontal, DS.Space.s1)
                    .background(DS.scrim, in: Capsule())
                    .padding(DS.ReleaseDays.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(height: DS.ReleaseDays.cell)
        .opacity(art.isEmpty && !isSelected ? DesignTokens.Opacity.faint : (isPast ? DS.ReleaseDays.pastOpacity : 1))
        .overlay(shape.strokeBorder(isSelected ? DS.accent : .clear, lineWidth: DS.SettingsLook.optionRing))
        .contentShape(shape)
    }
}
