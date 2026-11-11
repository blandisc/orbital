import SwiftUI
import OrbitalCore

/// El anillo de avance de una descarga (como la App Store): se llena con el color que le den. Es el mismo en el círculo de
/// Descargar de la ficha y en la fila de cada episodio.
struct DownloadRing: View {
    let fraction: Double
    var tint: Color = DS.accent
    var lineWidth: CGFloat = DS.TitleAction.ring
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(DS.hairline, lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : DS.Motion.steady, value: fraction)
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Descargando"))
        .accessibilityValue(Text(verbatim: "\(Int(fraction * 100)) %"))
    }
}

/// La tarjeta de acción, una sola pieza para toda la app: ícono arriba, el nombre abajo y, si hace falta, un renglón chico de
/// estado («En Mi lista», «Viendo»). En la ficha (Guardar, Descargar, Tráiler), en «Mi media» (Ver, Descargar) y en las
/// teclas del control (`style: .key`). Llena su parte del renglón; activa (Guardada, Descargada) se tiñe del color del arte;
/// con `progress`, el ícono lleva el anillo de la descarga. Es solo la etiqueta: quien la usa la pone en un `Button`, un
/// `Link` o un `Menu`.
///
/// Aire parejo (Fernando, 11 nov 2026: «"Guardar / Viendo" como que tiene muy poco espacio abajo»): el contenido lleva el
/// mismo relleno arriba y abajo (`DS.ActionTile`, un solo `padding(.vertical, …)`) y queda al centro del alto mínimo; si la
/// fila puede llevar un renglón de estado (`actionTileRow(reservesDetail:)`), todas las tarjetas lo reservan: miden lo mismo,
/// los íconos quedan a la misma altura y los nombres en la misma línea. Regla en docs/ios-interfaz.md § «Aire parejo».
struct ActionTileLabel: View {
    enum Style { case title, key }
    var style: Style = .title
    let title: Text
    let symbol: String
    var active = false
    var progress: Double?
    var tint: Color = DS.accent
    /// DB1: cuántos tienes (los episodios de una serie en el iPhone), en la esquina.
    var badge: Int? = nil
    /// El estado en letra chica bajo el nombre («En Mi lista», «Viendo»): el botón no cambia de nombre (revisión del 11 nov:
    /// «Viendo» en el botón parecía un estado, no una puerta).
    var detail: Text? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    /// La fila reserva el renglón del estado (alguna de sus tarjetas lo lleva): las demás dejan su lugar vacío.
    @Environment(\.actionTileReservesDetail) private var reservesDetail
    /// Cuánto crece la letra del ícono (Dynamic Type).
    @ScaledMetric(relativeTo: .headline) private var iconScale: CGFloat = 1

    private var metrics: DS.ActionTile.Metrics { style == .key ? DS.ActionTile.key : DS.ActionTile.title }
    /// El color del arte suele ser claro: en el modo claro se oscurece para que «Guardada» se lea sobre el papel.
    private var ink: Color { scheme == .light ? tint.mix(with: DS.backdropDeep, by: DS.TitleAction.lightDeepen) : tint }

    var body: some View {
        let tint = ink
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        VStack(spacing: DS.ActionTile.gap) {
            ZStack {
                if let progress { DownloadRing(fraction: progress, tint: tint, lineWidth: DS.TitleAction.ringSmallLine) }
                Image(systemName: symbol).font(iconFont)
                    .foregroundStyle(active ? tint : DS.text)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: active)   // «Vista», «Guardada»: se encienden con un salto, no solo cambian
            }
            // Su caja, la misma en toda la fila (los íconos quedan a la misma altura): crece con la letra (con letra grande el
            // ícono se salía y tocaba la orilla de arriba); su orilla (`iconRim`) no, para que no sobre aire arriba del ícono.
            .frame(width: style == .title ? iconBox : nil, height: iconBox)
            names
        }
        .padding(.horizontal, style == .key ? DS.Space.s1 : 0)   // el nombre de una tecla no toca la orilla: parte en dos antes
        .padding(.vertical, metrics.pad)
        // Una tecla llena el alto de su fila (la fila lleva `fixedSize`): todas miden lo mismo aunque una parta su nombre en dos.
        .frame(maxWidth: .infinity, minHeight: metrics.minHeight, maxHeight: style == .key ? .infinity : nil)
        .dsCard(translucent: true, fill: active ? tint.opacity(DesignTokens.Opacity.track) : nil)
        .overlay(shape.strokeBorder(style == .key ? .clear : active ? tint.opacity(DesignTokens.Opacity.faint) : DS.hairline, lineWidth: DS.Size.hairline))
        .overlay(alignment: .topTrailing) {
            if let badge, badge > 0 {
                Text(verbatim: "\(badge)").recipe(.badge, color: DS.onPrimary).monospacedDigit()
                    .padding(.horizontal, DS.Space.s1).background(tint, in: Capsule()).padding(DS.Space.s1)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(shape)
    }

    private var iconBox: CGFloat { (metrics.icon - DS.ActionTile.iconRim) * iconScale + DS.ActionTile.iconRim }

    private var iconFont: Font {
        if style == .key { return DS.TextRecipe.cardTitle.font }   // como las teclas de siempre
        return (progress == nil ? DS.TextRecipe.cardTitle : DS.TextRecipe.caption).font.weight(.semibold)
    }

    @ViewBuilder private var names: some View {
        switch style {
        case .key:
            // Completo o solo el ícono (I3, 10 nov): con letra grande en un renglón de cinco, «5 atr…» no decía nada. Con letra
            // normal el nombre parte en dos renglones si no cabe (revisión 2 del 11 nov: «−5 en la fila» se salía de la tecla).
            if !typeSize.isAccessibilitySize {
                title.recipe(.caption, color: DS.textMuted).lineLimit(2).multilineTextAlignment(.center)
                    .minimumScaleFactor(DS.Size.statScale).fixedSize(horizontal: false, vertical: true)
            }
        case .title:
            VStack(spacing: 0) {
                title.font(DS.TextRecipe.badge.font).foregroundStyle(active ? DS.text : DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                    .contentTransition(.numericText())
                if let detail {
                    detail.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                } else if reservesDetail {
                    // El lugar del estado, vacío: con la letra del estado, para que mida lo mismo con cualquier tamaño.
                    Text(verbatim: " ").font(DS.TextRecipe.caption.font).accessibilityHidden(true)
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// Ver `actionTileRow(reservesDetail:)`.
    @Entry var actionTileReservesDetail = false
}

extension View {
    /// Una fila de tarjetas de acción donde alguna lleva (o puede llevar) el renglón del estado: todas lo reservan, así miden
    /// lo mismo y el ícono y el nombre quedan a la misma altura en las tres.
    func actionTileRow(reservesDetail: Bool) -> some View {
        environment(\.actionTileReservesDetail, reservesDetail)
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
                DSSheetHeader(title: Text("Ya la tienes"), subtitle: Text("Puedes guardar varias versiones del mismo título."))
            }
            HStack(spacing: DS.Space.s2) {
                version(Text("La que tienes"), current)
                Image(systemName: "arrow.right").font(DS.TextRecipe.label.font).foregroundStyle(DS.textFaint)
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
            .font(DS.TextRecipe.labelLarge.font)
        }
        .dsSheetContent()
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
        .dsCard(translucent: true)
    }
}
