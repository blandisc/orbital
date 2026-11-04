import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// «Elegir versión» (como la TV): una fila por idioma de audio —el tuyo, el original y las variantes de español; los demás,
/// aparte— y en cada una solo las calidades que existen, la mejor de cada una. Tocar una calidad abre su tarjeta: qué es,
/// cómo sabemos el idioma, «Ver» y «Descargar», y las otras de esa fila y calidad con su nombre técnico. Las grabadas en el
/// cine y los tráileres no se ofrecen. «Ver» en la ficha sigue arrancando sola con la recomendada (la marcada aquí).
struct SourcesSheet: View {
    @State private var observer: ModelObserver<SourcesModel>
    /// La fuente elegida y para qué (ver o descargar).
    let choose: (Source, Purpose) -> Void
    /// Abrir una fuente con Infuse (mantener presionada), si quien abre la hoja lo permite.
    var infuse: ((Source) -> Void)?
    /// T8-A · «Pedirlo y avisarme» de una versión que Real-Debrid aún no tiene (el flujo de la ficha). nil: no se puede pedir.
    var request: ((Source) async -> Void)?
    @Environment(AppEnvironment.self) private var env

    /// Un episodio: ¿esta versión es solo para él o la serie sigue así? («Solo este episodio | Desde aquí», como la TV).
    private let episode: Bool
    private let metaID: String
    @State private var fromHere: Bool

    init(model: TitleModel, videoID: String, fromHere: Bool = false, choose: @escaping (Source, Purpose) -> Void, infuse: ((Source) -> Void)? = nil,
         request: ((Source) async -> Void)? = nil) {
        self.request = request
        _observer = State(wrappedValue: ModelObserver(SourcesModel(AppEnvironment.shared.services, kind: model.kind, metaID: model.metaID, videoID: videoID)))
        self.choose = choose
        self.infuse = infuse
        episode = model.kind == "series" && videoID.contains(":")
        metaID = model.metaID
        _fromHere = State(initialValue: fromHere)
    }

    /// «Desde aquí»: la serie recuerda el idioma (y el latino o castellano) de la versión elegida; vale también en la TV.
    private func pick(_ source: Source, _ purpose: Purpose) {
        if episode && fromHere {
            let prefs = env.services.titlePrefs.languages(for: metaID, settings: env.services.appSettings).prefs
            let code = source.audio.first(where: { $0.base == prefs.audio && $0.evidence.solid })?.code ?? source.audio.first?.code
            if let code { env.services.titlePrefs.remember(metaID: metaID, audioTrack: code) }
        }
        choose(source, purpose)
    }

    @State private var showsGlossary = false
    @State private var showsMore = false
    /// «Por idioma» (las filas de siempre) o «Todas» (la lista completa y plana).
    @State private var showsAll = SourcesSheet.demoShowsAll
    /// `-demo-open sources-all`: la hoja ya en «Todas» (solo en las compilaciones de prueba; `Demo` no existe en la de tienda).
    private static var demoShowsAll: Bool {
        #if DEBUG
        Demo.isOn && Demo.open == "sources-all"
        #else
        false
        #endif
    }
    @State private var picked: PickedVersion?
    private static var demoBottom: Bool {
        #if DEBUG
        Demo.isOn && Demo.open == "sources-request"
        #else
        false
        #endif
    }

    struct PickedVersion: Identifiable { let row: LanguageRow; let option: VersionOption; var id: String { "\(row.code)-\(option.id)" } }
    /// La primera vez que se pide algo, antes de la pregunta de iOS: para qué son los avisos (P4-A, la misma en todos lados).
    @State private var asking: AskingSource?
    struct AskingSource: Identifiable { let source: Source; var id: Int { source.index } }

    /// Pide esa versión; la primera vez, la línea de para qué son los avisos.
    private func ask(_ id: Int) {
        guard let request, let source = observer.model.source(id) else { return }
        Task {
            if await DebridRequestNotifier.permission() == .notDetermined { asking = AskingSource(source: source); return }
            await request(source)
        }
    }

    /// El pedido de esa versión en tu cuenta, si ya existe: su estado, nunca pedirla otra vez.
    private func requestStatus(_ id: Int) -> DebridRequestStatus? {
        let requests = env.services.debridRequests
        let _ = requests.track()
        guard let hash = observer.model.source(id)?.torrent?.hash, let found = requests.request(hash: hash) else { return nil }
        let tr = { (key: String) in Strings.tr(key, language: env.services.appSettings.uiLanguage) }
        return DebridRequestStatus(symbol: DebridRequestWords.symbol(found.state), title: DebridRequestWords.short(found, tr),
                                   fraction: found.state == .downloading ? Double(found.percent) / 100 : nil,
                                   warn: DebridRequestWords.isTrouble(found, now: Date()), ok: found.state == .ready)
    }

    var body: some View {
        let model = observer.model
        let ui = env.services.appSettings.uiLanguage
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSheetHeader(title: Text("Versión"), subtitle: showsAll ? Text("Todas, por calidad · toca una") : Text("Por idioma y calidad · toca una")) {
                // Qué quiere decir cada etiqueta (4K, DV, REMUX, Al instante…).
                Button { showsGlossary = true } label: { Image(systemName: "info.circle").font(DS.TextRecipe.section.font) }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget, alignment: .trailing)   // el ícono al ras del margen, el toque sigue de 44
                    .accessibilityLabel(Text("Qué significa cada etiqueta"))
                    .accessibilityIdentifier("sources-info")
            }
            .padding(.horizontal, DS.Space.s4)
            DSTextTabs(options: [.init(id: false, title: Text("Por idioma")), .init(id: true, title: Text("Todas las fuentes"))], selection: $showsAll)
            .padding(.horizontal, DS.Space.s4)
            .accessibilityIdentifier("sources-mode")
            if episode {
                DSSegmented(options: [(false, "Solo este episodio"), (true, "Desde aquí")], selection: $fromHere)
                .padding(.horizontal, DS.Space.s4)
                .accessibilityIdentifier("sources-scope")
            }
            ScrollView {
                VStack(spacing: DS.Space.s2) {   // ds-exception: renglones de la lista de versiones, no secciones de pantalla
                    if model.isLoading { DSLoadingState() }
                    if let error = model.error { DSNotice(verbatim: env.message(error), tone: .warn) }
                    if showsAll {
                        if !model.ranked.isEmpty {
                            AllSourcesList(sources: model.ranked, current: model.recommendedIndex,
                                           primary: ("Ver", { pick($0, .watch) }), secondary: ("Descargar", { pick($0, .download) }),
                                           uiLanguage: ui, prefs: env.services.titlePrefs.languages(for: metaID, settings: env.services.appSettings).prefs,
                                           offersSecondary: { s in s.playbackURL.map { !["m3u8", "mpd"].contains($0.pathExtension.lowercased()) } ?? false },
                                           request: request == nil ? nil : { ask($0.index) }, requestStatus: { requestStatus($0.index) })
                        }
                    } else {
                        byLanguage(model, ui)
                    }
                    // C8: si un complemento no contestó a tiempo, se dice quién (sus versiones no están aquí).
                    if !model.isLoading, !model.quiet.isEmpty { AddonQuietLine(names: model.quiet).padding(.top, DS.Space.s1) }
                }
            }
            .defaultScrollAnchor(Self.demoBottom ? .bottom : nil)   // `-demo-open sources-request`: abre abajo, en «Hay que pedirlas»
            .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
            .contentMargins(.vertical, DS.Space.s1, for: .scrollContent)
            if env.connectivity.isCellular {
                Text("Con datos móviles te avisamos antes de usar versiones de más de \(Int(env.services.appSettings.warnCellularOverGB)) GB.").recipe(.caption, color: DS.textFaint).padding(.horizontal, DS.Space.s4)
            }
        }
        .dsSheetContent(sides: false)   // el carrusel llega a las orillas: cada parte pone su margen
        .task { await model.load(onCellular: env.connectivity.isCellular) }
        .sheet(item: $asking) { pending in DebridNotifyAsk { _ in asking = nil; await request?(pending.source) } }
        .sheet(isPresented: $showsGlossary) { SourcesGlossary().fittedSheet().presentationDragIndicator(.visible) }
        .sheet(item: $picked) { p in
            VersionCard(row: p.row, option: p.option, others: model.others(of: p.option, in: p.row), uiLanguage: ui,
                        act: { id, purpose in
                            picked = nil
                            if let source = model.source(id) { pick(source, purpose) }
                        },
                        infuse: infuse.map { open in { id in picked = nil; if let s = model.source(id) { open(s) } } },
                        request: request == nil ? nil : { id in ask(id) }, requestStatus: requestStatus(p.option.id))
                // Mide lo que dice (sin espacio muerto); al abrir «Otras», crece y, si no cabe, se desplaza.
        }
    }

    /// «Por idioma»: una fila por idioma de audio, los demás idiomas plegados y cuántas se esconden.
    @ViewBuilder private func byLanguage(_ model: SourcesModel, _ ui: String) -> some View {
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
                Text("\(Text("Otros idiomas · "))\(Text(verbatim: model.moreLanguages.map { LanguageFlags.flagged(VersionLanguageRow.inline(Streams.versionLanguageName($0.code, in: ui), ui), $0.code) }.joined(separator: ", ")))")
            }
            .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
            .padding(DS.Space.s3)
            .dsCard(translucent: true)
            .tint(DS.textMuted)
        }
        if request != nil, !model.toRequest.isEmpty {
            VersionRequestGroup {
                ForEach(model.toRequest) { item in
                    let name = Streams.versionLanguageName(item.code, in: ui)
                    VersionRequestRow(title: Text("\(Text.flag(item.code))\(Text(verbatim: "\(name) · \(item.option.quality)"))"), option: item.option,
                                      status: requestStatus(item.id), request: { ask(item.id) },
                                      open: { picked = PickedVersion(row: LanguageRow(code: item.code, yours: false, original: false, options: [item.option]), option: item.option) })
                }
            }
        }
        if model.hiddenCount > 0 {
            (model.hiddenCount == 1 ? Text("1 oculta: grabada en el cine o tráiler") : Text("\(model.hiddenCount) ocultas: grabadas en el cine o tráileres"))
                .recipe(.caption, color: DS.textFaint)
                .frame(maxWidth: .infinity).padding(.top, DS.Space.s1)
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
    /// T8-A · la que Real-Debrid aún no tiene se pide, nunca se reproduce; ya pedida, su estado.
    var request: ((Int) -> Void)?
    var requestStatus: DebridRequestStatus?
    @State private var showsOthers = false
    /// El alto de lo que dice la tarjeta: la hoja mide eso (medida por la zona desplazable dejaba un hueco al pie).
    @State private var contentHeight: CGFloat = DS.Size.touchTarget * 8
    /// El margen de la barra de inicio: iOS lo suma por su cuenta al alto que se le pide a la hoja (pides 200, mide ~234), y
    /// la tarjeta ya llega hasta abajo (`ignoresSafeArea`): sin restarlo quedaba ese hueco al pie.
    private var windowBottomInset: CGFloat {
        AppWindows.safeArea.bottom
    }

    var body: some View { bodyContent.pointerHover(.highlight) }
    @ViewBuilder private var bodyContent: some View {
        let language = Streams.versionLanguageName(row.code, in: uiLanguage)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
                let facts = [VersionChip.size(option), option.badges.isEmpty ? nil : option.badges.joined(separator: " · ")].compactMap { $0 }.joined(separator: " · ")
                DSSheetHeader(title: Text("\(Text.flag(row.code))\(Text(verbatim: "\(language) · \(option.quality)"))"),
                              subtitle: VersionCard.withSpeed(facts, option.speed))
                if option.otherTitle {
                    DSNotice(text: "¿Otro título? El nombre dice otro año: puede ser otra película.", tone: .warn)
                }
                VersionEvidence(evidence: option.evidence, language: language, release: option.release, site: option.site)
                if !option.alsoHas.isEmpty {
                    (Text("\(Text("También trae: "))\(Text(verbatim: option.alsoHas.map { LanguageFlags.flagged(Streams.versionLanguageName($0, in: uiLanguage), $0) }.joined(separator: ", ")))"))
                        .recipe(.footnote)
                }
                if option.speed == .realDebridMustDownload, let request {
                    if let requestStatus { requestStatus } else {
                        Button { request(option.id) } label: { Label("Pedirlo y avisarme", systemImage: "arrow.down.circle").frame(maxWidth: .infinity) }
                            .dsPrimaryButton().controlSize(.large).accessibilityIdentifier("version-request")
                    }
                } else {
                HStack(spacing: DS.Space.s2) {
                    Button { act(option.id, .watch) } label: { Label("Ver", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .dsPrimaryButton().controlSize(.large).accessibilityIdentifier("version-watch")
                    if option.downloadable {
                        Button { act(option.id, .download) } label: { Label("Descargar", systemImage: "arrow.down").frame(maxWidth: .infinity) }
                            .dsGlassButton().controlSize(.large).accessibilityIdentifier("version-download")
                    }
                }
                }
                if let infuse {
                    Button("Abrir con Infuse", systemImage: "arrow.up.forward.app") { infuse(option.id) }
                        .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).buttonStyle(.plain)
                }
                if !others.isEmpty {
                    // Un botón y la lista debajo (no un `DisclosureGroup`: cerrado guardaba ~40 pt vacíos al pie de la tarjeta).
                    Button { withAnimation(DS.Motion.fade) { showsOthers.toggle() } } label: {
                        HStack {
                            Text("Otras \(others.count) en \(VersionLanguageRow.inline(language, uiLanguage)) \(option.quality)").recipe(.secondary, color: DS.text)
                            Spacer(minLength: DS.Space.s2)
                            Image(systemName: showsOthers ? "chevron.down" : "chevron.right").font(DS.TextRecipe.label.font).foregroundStyle(DS.textMuted)
                        }
                        .frame(minHeight: DS.Size.touchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsOthers ? Text("Abierto") : Text("Cerrado"))
                    if showsOthers {
                        VStack(spacing: DS.Space.s2) { ForEach(others) { other in otherRow(other) } }
                    }
                }
            }
            .padding(DS.Space.s5)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        // La hoja flota con sus esquinas redondas y la barra de inicio va encima de su borde: reservarle sus 34 pt además del
        // margen dejaba espacio muerto al pie de la tarjeta. El margen de abajo ya la separa de la barra.
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([.height(max(DS.Size.touchTarget * 4, contentHeight - windowBottomInset))])
        .fittedFormSizing(idealHeight: contentHeight)
        .presentationDragIndicator(.visible)
    }

    /// «2.9 GB · DV · Al instante»: los datos y, si se sabe, qué tan rápido arranca.
    static func withSpeed(_ facts: String, _ speed: SourceSpeed) -> Text {
        guard let words = VersionChip.speedText(speed) else { return Text(verbatim: facts) }
        return facts.isEmpty ? words : Text("\(Text(verbatim: facts + " · "))\(words)")
    }

    /// Otra del mismo idioma y calidad: su tamaño, cómo sabemos el idioma y su nombre técnico, con ▶ y ↓.
    private func otherRow(_ other: VersionOption) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                VersionCard.withSpeed(VersionChip.facts(other), other.speed).recipe(.footnote, color: DS.text)
                Text(verbatim: other.release).font(DS.TextRecipe.caption.font.monospaced()).foregroundStyle(DS.textMuted).lineLimit(2)
                if other.otherTitle { Text("¿Otro título?").recipe(.caption, color: DS.warning) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if other.speed == .realDebridMustDownload, let request {   // T8-A: se pide, nunca se reproduce
                Button { request(other.id) } label: { Image(systemName: "arrow.down.circle").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).background(DS.fillStrong, in: Circle()) }
                    .buttonStyle(.plain).foregroundStyle(DS.text).accessibilityLabel(Text("Pedirlo y avisarme"))
            } else {
            Button { act(other.id, .watch) } label: { Image(systemName: "play.fill").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).background(DS.fillStrong, in: Circle()) }
                .buttonStyle(.plain).foregroundStyle(DS.text).accessibilityLabel(Text("Ver"))
            }
            if other.downloadable {
                Button { act(other.id, .download) } label: { Image(systemName: "arrow.down").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).background(DS.fillStrong, in: Circle()) }
                    .buttonStyle(.plain).foregroundStyle(DS.text).accessibilityLabel(Text("Descargar"))
            }
            // Sin ↓ (una lista HLS) se aparta su lugar: el ▶ queda en la misma columna que el de las demás filas.
            else { Color.clear.frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).accessibilityHidden(true) }
        }
        .padding(DS.Space.s2)
        .dsCard(.row, translucent: true)
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

    /// «Al instante» (ya está en tu Real-Debrid) solo si tienes Real-Debrid: con tu lista de complementos armada y sin clave, sobra.
    private var shown: [(String, LocalizedStringKey, LocalizedStringKey)] {
        let services = AppEnvironment.shared.services
        let withoutDebrid = services.addonList.isConfigured && !services.debrid.hasToken
        return entries.filter { !(withoutDebrid && $0.0 == "bolt.fill") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Layout.titleToContent) {
            DSSheetHeader(title: Text("Qué significa cada etiqueta"))
            ForEach(shown, id: \.0) { symbol, title, detail in
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.accent).frame(width: DS.Size.touchTarget)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).recipe(.labelLarge, color: DS.text)
                        Text(detail).recipe(.footnote)
                    }
                }
            }
        }
        .padding(DS.Space.s5)
    }
}
