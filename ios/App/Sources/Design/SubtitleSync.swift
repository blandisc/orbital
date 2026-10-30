import SwiftUI
import OrbitalCore
import OrbitalModels

/// Sincronizar los subtítulos con una línea del video y la vista previa del subtítulo.

/// «Sincronizar con una línea»: tres frases que vienen; tocas la que escuchas en el momento en que la oyes y el tiempo se
/// ajusta solo (se recuerda para esa versión). Luego, «¿Ya van bien?»: Sí, u Otra vez con las siguientes.
struct SubtitleSyncView: View {
    let lines: [SubtitleLine]
    /// La frase que tocaste y el ajuste que quedó.
    var picked: Double?
    var result: Double?
    let pick: (SubtitleLine) -> Void
    let confirm: () -> Void
    let again: () -> Void
    let back: () -> Void
    var compact = false
    var language = "es"

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? DS.Space.s2 : DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                Button(action: back) {
                    Image(systemName: "chevron.left").font(DS.TextRecipe.secondary.font.weight(.bold)).foregroundStyle(DS.text)
                        .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                        .background(DS.fill, in: Circle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Volver"))
                Text("Sincronizar con una línea").recipe(.cardTitle).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            }
            if lines.isEmpty {
                Text("Esta versión no trae frases de texto para sincronizar. Usa Antes y Después.").recipe(.footnote)
            } else if let result {
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text(resultTitle(result)).recipe(.secondary, color: DS.onSolidPrimary).fontWeight(.bold)
                    Text("¿Ya van bien? Se recuerda para esta versión.").recipe(.caption, color: DS.onSolidPrimary)
                    HStack(spacing: DS.Space.s2) {
                        answer(Text("Sí"), primary: true, action: confirm).accessibilityIdentifier("subtitle-sync-yes")
                        answer(Text("Otra vez"), primary: false, action: again).accessibilityIdentifier("subtitle-sync-again")
                    }
                }
                .padding(DS.Space.s3)
                .background(DS.solidPrimary, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
            } else {
                Text("Toca la frase en el momento en que la escuches.").recipe(.footnote)
                ForEach(lines) { line in
                    Button { pick(line) } label: {
                        Text(verbatim: line.text).recipe(.secondary, color: DS.text).lineLimit(compact ? 1 : 2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
                            .padding(.horizontal, DS.Space.s3)
                            .background(picked == line.start ? DS.fillStrong : DS.fill, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subtitle-sync-line")
                }
            }
        }
        .padding(compact ? DS.Space.s3 : DS.Space.s4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
    }

    private func resultTitle(_ value: Double) -> String {
        if abs(value) < 0.05 { return Strings.tr("Listo: ya iban a tiempo", language: language) }
        let key = value > 0 ? "Listo: subtítulos %@ s después" : "Listo: subtítulos %@ s antes"
        return String(format: Strings.tr(key, language: language), String(format: "%.1f", abs(value)))
    }

    private func answer(_ title: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title.font(DS.TextRecipe.footnote.font.weight(.semibold)).lineLimit(1)
                .foregroundStyle(primary ? DS.solidPrimary : DS.onSolidPrimary)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .background(primary ? DS.onSolidPrimary : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(primary ? .clear : DS.onSolidPrimary.opacity(DesignTokens.Opacity.disabled)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Ajustes › Subtítulos: una escena de muestra con una línea dibujada con tu estilo (fondo, tamaño, posición).
struct SubtitlePreview: View {
    let look: SubtitleLook

    var body: some View {
        GeometryReader { geo in
            let size = max(DS.Subtitle.minFont, geo.size.width / DS.Poster.stillAspect * look.heightFraction)
            Text("— Así se van a ver.")
                .font(.system(size: size, weight: .semibold))   // ds-exception: la letra se mide con el video, como en el reproductor
                .foregroundStyle(look.text)
                .subtitleLook(look, size: size)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, geo.size.height * (look.raised ? DS.Subtitle.raisedMargin : DS.Subtitle.edgeMargin) * 2)
        }
        .aspectRatio(DS.Poster.stillAspect, contentMode: .fit)
        .background(LinearGradient(colors: [DS.backdropDeep, DS.warning.opacity(DesignTokens.Opacity.disabled), DS.backdropDeep],   // ds-exception: la barra de sincronía (ámbar), no un velo
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: DS.PlayerPanel.rowRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
