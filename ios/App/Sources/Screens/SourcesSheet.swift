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

    @State private var showsGlossary = false

    var body: some View {
        let model = observer.model
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Fuentes").recipe(.title)
                    Text("De Real-Debrid · la recomendada va primero").recipe(.footnote)
                }
                Spacer()
                // Qué quiere decir cada etiqueta (4K, DV, REMUX, Al instante…).
                Button { showsGlossary = true } label: { Image(systemName: "info.circle").font(DS.TextRecipe.section.font) }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                    .accessibilityLabel(Text("Qué significa cada etiqueta"))
                    .accessibilityIdentifier("sources-info")
            }
            .padding(.horizontal, DS.Space.s4)
            DSSegmented(options: [(Purpose.watch, "Ver"), (.download, "Descargar")], selection: $purpose).padding(.horizontal, DS.Space.s4)
            ScrollView {
                VStack(spacing: DS.Space.s2) {
                    if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding(DS.Space.s6) }
                    if let error = model.error { DSNotice(verbatim: env.message(error), tone: .warn) }
                    ForEach(model.rows) { row in
                        // `model.purpose`: para lo que se cargó la lista (no la pestaña recién tocada, que aún carga). Tocar el
                        // renglón elige; las etiquetas se deslizan de lado sin elegir.
                        SourceRowView(row: row, purpose: purpose) { if let source = model.source(row.id) { choose(source, model.purpose) } }
                    }
                }
            }
            // Aire a los lados y arriba: el contorno de la recomendada no se corta contra la orilla.
            .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
            .contentMargins(.vertical, DS.Space.s1, for: .scrollContent)
            if env.connectivity.isCellular {
                Text("Con datos móviles te avisamos antes de usar fuentes de más de 5 GB.").recipe(.caption, color: DS.textFaint).padding(.horizontal, DS.Space.s4)
            }
        }
        .padding(.vertical, DS.Space.s4)
        .task(id: purpose) { await model.load(purpose, onCellular: env.connectivity.isCellular) }
        .sheet(isPresented: $showsGlossary) { SourcesGlossary().fittedSheet().presentationDragIndicator(.visible) }
    }
}

/// Qué quiere decir cada etiqueta de las fuentes, en corto.
struct SourcesGlossary: View {
    private let entries: [(String, LocalizedStringKey, LocalizedStringKey)] = [
        ("sparkles", "Recomendada", "La que elegimos por calidad, idioma y tamaño. Es la que arranca sola."),
        ("bolt.fill", "Al instante", "Ya está en tu Real-Debrid: empieza sin esperar."),
        ("4k.tv", "4K · 1080p · 720p", "La resolución. 4K se luce en la TV; en el iPhone, 1080p ya se ve nítido."),
        ("sun.max", "HDR · DV", "Más contraste y color. DV es Dolby Vision: el iPhone lo reproduce."),
        ("hifispeaker.2", "Atmos · 5.1", "Sonido envolvente. Con audífonos AirPods, Atmos se oye espacial."),
        ("opticaldisc", "REMUX", "La copia íntegra del disco: la mejor imagen y la más pesada."),
        ("play.rectangle", "WEB-DL", "Del servicio de streaming: buena calidad y tamaño medio."),
        ("rectangle.compress.vertical", "x265 · AV1", "Compresión eficiente: se ve igual y ocupa menos."),
        ("internaldrive", "Tamaño", "En amarillo, las pesadas: con datos móviles te avisamos antes."),
        ("exclamationmark.triangle", "CAM", "Grabada en el cine: mala imagen. Va hasta abajo."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("Qué significa cada etiqueta").recipe(.title)
            ForEach(entries, id: \.0) { symbol, title, detail in
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.accent).frame(width: DS.Size.touchTarget)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).recipe(.secondary, color: DS.text).fontWeight(.semibold)
                        Text(detail).recipe(.footnote)
                    }
                }
            }
        }
        .padding(DS.Space.s5)
    }
}

struct SourceRowView: View {
    let row: SourceRow
    var purpose: Purpose = .watch
    let choose: () -> Void
    @State private var taps = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        HStack(alignment: .center, spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text(row.headline).recipe(.secondary, color: DS.text).fontWeight(.semibold).lineLimit(2)
                // Las que no caben se deslizan de lado (dentro del renglón, hasta su orilla).
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s1) {
                        if row.recommended { DSChip(text: "Recomendada", tone: .good) }
                        if row.cached { DSChip(text: "Al instante", tone: .good) }
                        if let gb = row.sizeGB { DSChipText(text: gb >= 1 ? String(format: "%.1f GB", gb) : String(format: "%.0f MB", gb * 1000), tone: row.heavy ? .warn : .normal) }
                        QualityBadges(items: QualityBadges.items(resolution: row.resolution, hdr: row.hdr, audio: row.audio))
                        ForEach(row.tags, id: \.self) { DSChipText(text: $0) }
                    }
                }
            }
            Image(systemName: purpose == .download ? "arrow.down.circle" : "play.circle.fill")
                .font(DS.TextRecipe.section.font).foregroundStyle(row.recommended ? DS.accent : DS.textMuted)
        }
        .padding(DS.Space.s3)
        .background(row.recommended ? DS.fillStrong : DS.fill, in: shape)
        .overlay(shape.strokeBorder(row.recommended ? DS.accent : DS.hairline, lineWidth: DS.Size.hairline))   // dentro del borde: no se corta
        .contentShape(shape)
        .onTapGesture { taps += 1; choose() }
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { choose() }
    }
}
