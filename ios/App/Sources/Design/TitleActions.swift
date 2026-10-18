import SwiftUI
import OrbitalCore

/// El anillo de avance de una descarga (como la App Store): se llena con el color que le den. Es el mismo en el círculo de
/// Descargar de la ficha y en la fila de cada episodio.
struct DownloadRing: View {
    let fraction: Double
    var tint: Color = DS.accent
    var lineWidth: CGFloat = DS.TitleAction.ring

    var body: some View {
        ZStack {
            Circle().stroke(DS.hairline, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: fraction)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Descargando"))
        .accessibilityValue(Text(verbatim: "\(Int(fraction * 100)) %"))
    }
}

/// Una acción de la ficha: un círculo con su ícono y el nombre debajo (Guardar, Descargar, Tráiler, Fuente). Activa (Guardada,
/// Descargada) se pinta con el color del arte; con `progress`, el círculo lleva el anillo de la descarga. Es solo la etiqueta:
/// quien la usa la pone en un `Button` o en un `Menu` (tocar hace lo principal; mantener presionado, el resto).
struct CircleActionLabel: View {
    let title: Text
    let symbol: String
    var active = false
    var progress: Double?
    var tint: Color = DS.accent

    var body: some View {
        VStack(spacing: DS.Space.s2) {
            ZStack {
                Circle().fill(active ? tint.opacity(DesignTokens.Opacity.track) : DS.fill)
                Circle().strokeBorder(active ? tint.opacity(DesignTokens.Opacity.faint) : DS.hairline, lineWidth: DS.Size.hairline)
                if let progress { DownloadRing(fraction: progress, tint: tint).padding(DS.TitleAction.ring / 2) }
                Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(active ? tint : DS.text)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: DS.TitleAction.circle, height: DS.TitleAction.circle)
            title.font(DS.TextRecipe.caption.font).foregroundStyle(active ? DS.text : DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
