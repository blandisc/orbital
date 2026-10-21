import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Elegir versión» (como la TV): una fila por idioma de audio —el tuyo, el original y las variantes de español; los demás,
/// aparte— y en cada una solo las calidades que existen, la mejor de cada una. Tocar una calidad abre su tarjeta: qué es,
/// cómo sabemos el idioma, «Ver» y «Descargar», y las otras de esa fila y calidad con su nombre técnico. Las grabadas en el
/// cine y los tráileres no se ofrecen. «Ver» en la ficha sigue arrancando sola con la recomendada (la marcada aquí).
struct SourcesSheet: View {
    @StateObject private var observer: ModelObserver<SourcesModel>
    /// La fuente elegida y para qué (ver o descargar).
    let choose: (Source, Purpose) -> Void
    /// Abrir una fuente con Infuse (mantener presionada), si quien abre la hoja lo permite.
    var infuse: ((Source) -> Void)?
    @EnvironmentObject private var env: AppEnvironment

    init(model: TitleModel, videoID: String, choose: @escaping (Source, Purpose) -> Void, infuse: ((Source) -> Void)? = nil) {
        _observer = StateObject(wrappedValue: ModelObserver(SourcesModel(AppEnvironment.shared.services, kind: model.kind, metaID: model.metaID, videoID: videoID)))
        self.choose = choose
        self.infuse = infuse
    }

    @State private var showsGlossary = false
    @State private var showsMore = false
    @State private var picked: PickedVersion?

    struct PickedVersion: Identifiable { let row: LanguageRow; let option: VersionOption; var id: String { "\(row.code)-\(option.id)" } }

    var body: some View {
        let model = observer.model
        let ui = env.services.appSettings.uiLanguage
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Elegir versión").recipe(.title)
                    Text("Por idioma y calidad · toca una").recipe(.footnote)
                }
                Spacer()
                // Qué quiere decir cada etiqueta (4K, DV, REMUX, Al instante…).
                Button { showsGlossary = true } label: { Image(systemName: "info.circle").font(DS.TextRecipe.section.font) }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                    .accessibilityLabel(Text("Qué significa cada etiqueta"))
                    .accessibilityIdentifier("sources-info")
            }
            .padding(.horizontal, DS.Space.s4)
            ScrollView {
                VStack(spacing: DS.Space.s2) {
                    if model.isLoading { ProgressView().frame(maxWidth: .infinity).padding(DS.Space.s6) }
                    if let error = model.error { DSNotice(verbatim: env.message(error), tone: .warn) }
                    ForEach(model.languageRows) { row in
                        VersionLanguageRow(row: row, uiLanguage: ui) { picked = PickedVersion(row: row, option: $0) }
                    }
                    if !model.moreLanguages.isEmpty {
                        DisclosureGroup(isExpanded: $showsMore) {
                            VStack(spacing: DS.Space.s2) {
                                ForEach(model.moreLanguages) { row in
                                    VersionLanguageRow(row: row, uiLanguage: ui) { picked = PickedVersion(row: row, option: $0) }
                                }
                            }
                            .padding(.top, DS.Space.s2)
                        } label: {
                            Text("Otros idiomas · ") + Text(verbatim: model.moreLanguages.map { Streams.versionLanguageName($0.code, in: ui).lowercased() }.joined(separator: ", "))
                        }
                        .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
                        .padding(DS.Space.s3)
                        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .tint(DS.textMuted)
                    }
                    if model.hiddenCount > 0 {
                        (model.hiddenCount == 1 ? Text("1 oculta: grabada en el cine o tráiler") : Text("\(model.hiddenCount) ocultas: grabadas en el cine o tráileres"))
                            .recipe(.caption, color: DS.textFaint)
                            .frame(maxWidth: .infinity).padding(.top, DS.Space.s1)
                    }
                }
            }
            .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
            .contentMargins(.vertical, DS.Space.s1, for: .scrollContent)
            if env.connectivity.isCellular {
                Text("Con datos móviles te avisamos antes de usar fuentes de más de \(Int(env.services.appSettings.warnCellularOverGB)) GB.").recipe(.caption, color: DS.textFaint).padding(.horizontal, DS.Space.s4)
            }
        }
        .padding(.vertical, DS.Space.s4)
        .task { await model.load(onCellular: env.connectivity.isCellular) }
        .sheet(isPresented: $showsGlossary) { SourcesGlossary().fittedSheet().presentationDragIndicator(.visible) }
        .sheet(item: $picked) { p in
            VersionCard(row: p.row, option: p.option, others: model.others(of: p.option, in: p.row), uiLanguage: ui,
                        act: { id, purpose in
                            picked = nil
                            if let source = model.source(id) { choose(source, purpose) }
                        },
                        infuse: infuse.map { open in { id in picked = nil; if let s = model.source(id) { open(s) } } })
                .fittedScrollSheet()   // del alto de lo que dice (sin espacio muerto); al abrir «Otras», crece
        }
    }
}

/// La tarjeta de una versión: «Latino · 1080p», su tamaño y si arranca al instante, cómo sabemos el idioma, «Ver» y
/// «Descargar», y las otras de ese idioma y calidad (con su nombre técnico, solo aquí).
struct VersionCard: View {
    let row: LanguageRow
    let option: VersionOption
    let others: [VersionOption]
    let uiLanguage: String
    let act: (Int, Purpose) -> Void
    var infuse: ((Int) -> Void)?
    @State private var showsOthers = false

    var body: some View {
        let language = Streams.versionLanguageName(row.code, in: uiLanguage)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(verbatim: "\(language) · \(option.quality)").recipe(.title)
                    (Text(verbatim: [VersionChip.size(option), option.badges.isEmpty ? nil : option.badges.joined(separator: " · ")].compactMap { $0 }.joined(separator: " · ") + " · ")
                     + (option.cached ? Text("Al instante") : Text("Tarda en empezar"))).recipe(.secondary)
                }
                if option.otherTitle {
                    DSNotice(text: "¿Otro título? El nombre dice otro año: puede ser otra película.", tone: .warn)
                }
                VersionEvidence(evidence: option.evidence, language: language, release: option.release, site: option.site)
                if !option.alsoHas.isEmpty {
                    (Text("También trae: ") + Text(verbatim: option.alsoHas.map { Streams.versionLanguageName($0, in: uiLanguage) }.joined(separator: ", ")))
                        .recipe(.footnote)
                }
                HStack(spacing: DS.Space.s2) {
                    Button { act(option.id, .watch) } label: { Label("Ver", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .dsPrimaryButton().controlSize(.large).accessibilityIdentifier("version-watch")
                    if option.downloadable {
                        Button { act(option.id, .download) } label: { Label("Descargar", systemImage: "arrow.down").frame(maxWidth: .infinity) }
                            .buttonStyle(.glass).controlSize(.large).accessibilityIdentifier("version-download")
                    }
                }
                if let infuse {
                    Button("Abrir con Infuse", systemImage: "arrow.up.forward.app") { infuse(option.id) }
                        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).buttonStyle(.plain)
                }
                if !others.isEmpty {
                    DisclosureGroup(isExpanded: $showsOthers) {
                        VStack(spacing: DS.Space.s2) { ForEach(others) { other in otherRow(other) } }.padding(.top, DS.Space.s2)
                    } label: {
                        Text("Otras \(others.count) en \(language.lowercased()) \(option.quality)").recipe(.secondary, color: DS.text)
                    }
                    .tint(DS.textMuted)
                }
            }
            .padding(DS.Space.s5)
        }
    }

    /// Otra del mismo idioma y calidad: su tamaño, cómo sabemos el idioma y su nombre técnico, con ▶ y ↓.
    private func otherRow(_ other: VersionOption) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                (Text(verbatim: VersionChip.facts(other) + " · ") + (other.cached ? Text("Al instante") : Text("Tarda en empezar"))).recipe(.footnote, color: DS.text)
                Text(verbatim: other.release).font(DS.TextRecipe.caption.font.monospaced()).foregroundStyle(DS.textMuted).lineLimit(2)
                if other.otherTitle { Text("¿Otro título?").recipe(.caption, color: DS.warning) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { act(other.id, .watch) } label: { Image(systemName: "play.fill").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).background(DS.fillStrong, in: Circle()) }
                .buttonStyle(.plain).foregroundStyle(DS.text).accessibilityLabel(Text("Ver"))
            if other.downloadable {
                Button { act(other.id, .download) } label: { Image(systemName: "arrow.down").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).background(DS.fillStrong, in: Circle()) }
                    .buttonStyle(.plain).foregroundStyle(DS.text).accessibilityLabel(Text("Descargar"))
            }
        }
        .padding(DS.Space.s2)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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
