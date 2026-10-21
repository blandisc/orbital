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

/// «Ya la tienes»: al descargar una fuente de algo que ya tienes (o que se está bajando). Una hoja con estilo de la app, no un
/// diálogo del sistema: las dos versiones lado a lado y tres salidas — bajar también esta (quedan las dos), cambiarla, o dejarla.
struct DownloadVersionSheet: View {
    /// La que tienes: calidad y peso (o «Bajando 40 %»).
    let current: (label: String, detail: Text)
    /// La que elegiste.
    let new: (label: String, detail: Text)
    let keepBoth: () -> Void
    let replace: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "checkmark.circle.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.good)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ya la tienes").recipe(.section)
                    Text("Puedes guardar varias versiones del mismo título.").recipe(.footnote)
                }
            }
            HStack(spacing: DS.Space.s2) {
                version(Text("La que tienes"), current)
                Image(systemName: "arrow.right").font(DS.TextRecipe.footnote.font.weight(.bold)).foregroundStyle(DS.textFaint)
                version(Text("La que elegiste"), new)
            }
            .fixedSize(horizontal: false, vertical: true)   // las dos tarjetas del mismo alto, aunque una diga más
            VStack(spacing: DS.Space.s2) {
                // Las dos opciones del mismo tamaño (alto fijo, no el que cada estilo le da).
                Button(action: keepBoth) { option(Label("Bajar también esta", systemImage: "plus.square.on.square"), fill: DS.primary, ink: DS.onPrimary) }
                    .buttonStyle(.plain)
                Button(action: replace) { option(Label("Cambiarla por esta", systemImage: "arrow.triangle.2.circlepath"), fill: DS.fillStrong, ink: DS.text) }
                    .buttonStyle(.plain)
                Button(action: cancel) { Text("Dejar la que tengo").frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted)
            }
            .font(DS.TextRecipe.secondary.font.weight(.semibold))
        }
        .padding(DS.Space.gutter)
    }

    /// Una opción: la misma cápsula para las dos (solo cambia el color).
    private func option(_ label: Label<Text, Image>, fill: Color, ink: Color) -> some View {
        label.foregroundStyle(ink)
            .frame(maxWidth: .infinity, minHeight: DS.Remote.keyHeight)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
    }

    private func version(_ title: Text, _ v: (label: String, detail: Text)) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            title.recipe(.caption)
            Text(verbatim: v.label).recipe(.cardTitle).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            v.detail.recipe(.footnote).lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Space.s3)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}
