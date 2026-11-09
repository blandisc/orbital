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

/// DP2: bajar la temporada desde su encabezado («⬇︎ Temporada · 7.6 GB»); bajando, cuántas van («2 de 5»); toda lista, ✓.
struct SeasonDownloadButton: View {
    let missing: Int
    let total: Int
    let bytes: Int64?
    let tint: Color
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        if total > 0 {
            Button(action: action) {
                Label {
                    if missing == 0 { Text("Temporada lista") }
                    else if let bytes { Text("Temporada · \(Text(verbatim: ByteSize.text(bytes, locale: locale)))") }
                    else { Text("Temporada") }
                } icon: { Image(systemName: missing == 0 ? "checkmark.circle.fill" : "arrow.down.circle") }
                .font(DS.TextRecipe.label.font)
                .foregroundStyle(tint)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(missing == 0)
            .accessibilityIdentifier("season-download")
        }
    }
}
