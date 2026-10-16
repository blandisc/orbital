import SwiftUI
import OrbitalCore
import OrbitalModels

/// La lista de fuentes de Real-Debrid: «Ver» o «Descargar». La recomendada va arriba y es la que arranca sola.
struct SourcesSheet: View {
    @StateObject private var observer: ModelObserver<SourcesModel>
    @State private var purpose: Purpose
    /// La fuente elegida y para qué (Ver o Descargar, como quedó el selector de la hoja).
    let choose: (Source, Purpose) -> Void
    @EnvironmentObject private var env: AppEnvironment

    init(model: TitleModel, videoID: String, purpose: Purpose, choose: @escaping (Source, Purpose) -> Void) {
        _observer = StateObject(wrappedValue: ModelObserver(SourcesModel(AppEnvironment.shared.services, kind: model.kind, metaID: model.metaID, videoID: videoID)))
        _purpose = State(initialValue: purpose)
        self.choose = choose
    }

    var body: some View {
        let model = observer.model
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("Fuentes de Real-Debrid").font(DS.TextRecipe.section.font.weight(.bold)).foregroundStyle(DS.text)
            Text("La recomendada está arriba.").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            DSSegmented(options: [(Purpose.watch, "Ver"), (.download, "Descargar")], selection: $purpose)
            ScrollView {
                VStack(spacing: DS.Space.s2) {
                    if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding(DS.Space.s6) }
                    if let error = model.error { DSNotice(text: env.message(error), tone: .warn) }
                    ForEach(model.rows) { row in
                        Button { if let source = model.source(row.id) { choose(source, purpose) } } label: { SourceRowView(row: row, purpose: purpose) }.buttonStyle(.plain)
                    }
                }
            }
            if env.connectivity.isCellular { Text("Con datos móviles te avisamos antes de usar fuentes de más de 5 GB.").font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint) }
        }
        .padding(DS.Space.s4)
        .task(id: purpose) { await model.load(purpose, onCellular: env.connectivity.isCellular) }
    }
}

struct SourceRowView: View {
    let row: SourceRow
    var purpose: Purpose = .watch

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(row.headline).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s1) {
                        if row.recommended { DSChip(text: "Recomendada", tone: .good) }
                        if row.cached { DSChip(text: "Al instante", tone: .good) }
                        if let gb = row.sizeGB { DSChipText(text: gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", gb * 1000), tone: row.heavy ? .warn : .normal) }
                        ForEach(row.hdr, id: \.self) { DSChipText(text: $0) }
                        ForEach(row.tags, id: \.self) { DSChipText(text: $0) }
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: purpose == .download ? "arrow.down.circle" : "play.fill").foregroundStyle(DS.textMuted).padding(.top, DS.Space.s1)
        }
        .padding(DS.Space.s3)
        .background(row.recommended ? DS.fillStrong : DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg).stroke(row.recommended ? DS.primary : Color.clear))
        .accessibilityElement(children: .combine)
    }
}
