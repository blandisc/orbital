import SwiftUI
import OrbitalCore

/// DS1 (Fernando, 8 nov): «¿Qué descargo?» al tocar «Descargar» en una serie. El de un toque de siempre arriba y resaltado; los
/// siguientes, la temporada y toda la serie con su tamaño y si caben (lo que no cabe, en ámbar). https://claude.ai/artifact/TVB3waLrnVJyfQ9vE8U7d8
struct DownloadChoiceSheet: View {
    struct Option: Identifiable {
        let id: String
        let symbol: String
        let title: Text
        let detail: Text
        let bytes: Int64?
        var main = false
        let pick: () -> Void
    }
    let subtitle: Text
    let options: [Option]
    let chooseVersion: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// Lo libre en el iPhone (lo que iOS deja usar para algo importante).
    private var free: Int64? {
        (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            DSSheetHeader(title: Text("¿Qué descargo?"), subtitle: subtitle).padding(.bottom, DS.Space.s2)
            ForEach(options) { option in row(option) }
            row(Option(id: "version", symbol: "list.bullet.rectangle", title: Text("Elegir versión…"), detail: Text("Otra calidad o idioma"), bytes: nil, pick: chooseVersion))
        }
        .dsSheetContent()
        .fittedSheet()
    }

    private func row(_ o: Option) -> some View {
        let tooBig = o.bytes.map { b in free.map { b > $0 } ?? false } ?? false
        return Button { dismiss(); o.pick() } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: o.symbol).font(DS.TextRecipe.label.font)
                    .foregroundStyle(o.main ? DS.onPrimary : DS.text)
                    .frame(width: DS.Size.touchTarget * DownloadChoiceSheet.iconShare, height: DS.Size.touchTarget * DownloadChoiceSheet.iconShare)
                    .dsCard(fill: o.main ? DS.primary : DS.fillStrong)
                VStack(alignment: .leading, spacing: 0) {
                    o.title.recipe(.label, color: DS.text)
                    (tooBig ? Text("\(o.detail) · no cabe en tu iPhone") : o.detail).recipe(.caption, color: tooBig ? DS.warning : DS.textMuted)
                }
                Spacer(minLength: DS.Space.s2)
                if let b = o.bytes { Text(verbatim: ByteSize.text(b, locale: locale)).recipe(.caption, color: tooBig ? DS.warning : DS.textMuted).monospacedDigit() }
            }
            .padding(.vertical, DS.Space.s2).padding(.horizontal, DS.Space.s2)
            .dsCard(translucent: !o.main, fill: o.main ? DS.fill : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("download-choice-\(o.id)")
    }

    static let iconShare: CGFloat = 0.7
}

/// ET1 (Fernando, 9 nov): un botón de ícono del encabezado de temporada con su texto chico debajo (el peso, «Vista»).
/// `progress` (0…1) lo vuelve un anillo con su %; `done` lo pinta lleno en verde. https://claude.ai/artifact/ARhv4cB7YRH8PFFsbNiF6w
struct SeasonActionButton: View {
    let symbol: String
    let caption: Text
    var progress: Double? = nil
    var done = false
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: DS.Space.s1) {
            ZStack {
                Circle().stroke(DS.hairline, lineWidth: DS.Stroke.selected)
                if let progress {
                    Circle().trim(from: 0, to: max(0.02, progress))
                        .stroke(tint, style: StrokeStyle(lineWidth: DS.Stroke.selected, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(DS.Motion.base(reduceMotion), value: progress)
                    Text(verbatim: "\(Int((progress * 100).rounded(.down)))").font(DS.TextRecipe.badge.font).monospacedDigit().foregroundStyle(DS.text)
                } else {
                    Image(systemName: done ? "\(symbol).fill" : symbol).font(DS.TextRecipe.label.font)
                        .foregroundStyle(done ? DS.success : tint)
                }
            }
            .frame(width: DS.Size.seasonAction, height: DS.Size.seasonAction)
            caption.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).lineLimit(1)
        }
        .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
        .contentShape(Rectangle())
    }
}
