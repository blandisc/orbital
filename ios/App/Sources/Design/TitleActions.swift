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

/// Una acción de la ficha: un rectángulo que llena su parte del renglón (sin espacio muerto entre ellas) con el ícono arriba
/// y el nombre abajo: Guardar, Descargar, Tráiler, Fuente. Activa (Guardada, Descargada) se tiñe del color del arte; con
/// `progress`, el ícono lleva el anillo de la descarga. Es solo la etiqueta: quien la usa la pone en un `Button` o en un `Menu`
/// (tocar hace lo principal; mantener presionado, el resto).
struct ActionTileLabel: View {
    let title: Text
    let symbol: String
    var active = false
    var progress: Double?
    var tint: Color = DS.accent
    @Environment(\.colorScheme) private var scheme

    /// El color del arte suele ser claro: en el modo claro se oscurece para que «Guardada» se lea sobre el papel.
    private var ink: Color { scheme == .light ? tint.mix(with: DS.backdropDeep, by: DS.TitleAction.lightDeepen) : tint }

    var body: some View {
        let tint = ink
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        VStack(spacing: DS.Space.s1) {
            ZStack {
                if let progress { DownloadRing(fraction: progress, tint: tint, lineWidth: DS.TitleAction.ringSmallLine) }
                Image(systemName: symbol).font((progress == nil ? DS.TextRecipe.cardTitle : DS.TextRecipe.caption).font.weight(.semibold))
                    .foregroundStyle(active ? tint : DS.text)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall)
            title.font(DS.TextRecipe.caption.font.weight(.medium)).foregroundStyle(active ? DS.text : DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, minHeight: DS.TitleAction.tile)
        .background(active ? tint.opacity(DesignTokens.Opacity.track) : DS.fill, in: shape)
        .overlay(shape.strokeBorder(active ? tint.opacity(DesignTokens.Opacity.faint) : DS.hairline, lineWidth: DS.Size.hairline))
        .contentShape(shape)
    }
}
