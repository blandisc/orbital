import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// «Elegir versión» (V1 + V3, Fernando, 9 nov): una lista con íconos. Tu idioma primero, con su bandera de encabezado; los
/// demás bajo «Otros idiomas», con la bandera en cada renglón. Tocar un renglón reproduce (o la pide a la nube, si hay que
/// pedirla); mantenerlo presionado da sus detalles (cómo sabemos el idioma, qué más trae, de qué complemento viene) y lo
/// demás: Descargar, Infuse, las otras del mismo idioma y calidad. Arriba no hay pestañas: «Todas» es un enlace al pie y, en
/// un episodio, la pregunta de la serie llega después de elegir y solo si cambias de idioma. Las grabadas en el cine y los
/// tráileres no se ofrecen. «Ver» en la ficha sigue arrancando sola con la recomendada (la ✦ de aquí).
struct SourcesSheet: View {
    @State private var observer: ModelObserver<SourcesModel>
    /// La fuente elegida y para qué (ver o descargar).
    let choose: (Source, Purpose) -> Void
    /// Abrir una fuente con Infuse (mantener presionada), si quien abre la hoja lo permite.
    var infuse: ((Source) -> Void)?
    /// T8-A · «Pedirlo y avisarme» de una versión que Real-Debrid aún no tiene (el flujo de la ficha). nil: no se puede pedir.
    var request: ((Source) async -> Void)?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    /// Un episodio: si eliges otro idioma, se pregunta si la serie sigue así (V3). `fromHere`: ya se abrió «desde aquí».
    private let episode: Bool
    private let metaID: String
    private let fromHere: Bool

    init(model: TitleModel, videoID: String, fromHere: Bool = false, choose: @escaping (Source, Purpose) -> Void, infuse: ((Source) -> Void)? = nil,
         request: ((Source) async -> Void)? = nil) {
        self.request = request
        _observer = State(wrappedValue: ModelObserver(SourcesModel(AppEnvironment.shared.services, kind: model.kind, metaID: model.metaID, videoID: videoID)))
        self.choose = choose
        self.infuse = infuse
        episode = model.kind == "series" && videoID.contains(":")
        metaID = model.metaID
        self.fromHere = fromHere
    }

    private var prefs: Preferences { env.services.titlePrefs.languages(for: metaID, settings: env.services.appSettings).prefs }

    /// ¿Es el idioma con el que va la serie? (la misma regla que «Tu idioma» de las filas).
    private func speaksSeries(_ code: String) -> Bool {
        let want = prefs.wanted
        return code == want || (want.count == 2 && code.hasPrefix(want))
    }

    /// V3 · elegir: en un episodio y con otro idioma que el de la serie, primero «¿Para el resto de la serie también?».
    /// `code`: el idioma del renglón elegido; sin él (la lista «Todas»), el que dice la versión.
    private func pick(_ source: Source, _ purpose: Purpose, code: String? = nil) {
        let chosen = code ?? source.audio.first(where: { $0.evidence.solid })?.code ?? source.audio.first?.code
        let same = code.map(speaksSeries) ?? source.audio.contains { $0.evidence.solid && speaksSeries($0.code) }
        if episode, !fromHere, !same, let chosen {
            seriesAsk = SeriesAsk(source: source, purpose: purpose, code: chosen)
            return
        }
        finish(source, purpose, forSeries: episode && fromHere ? (same ? nil : chosen) : nil, keep: episode && fromHere && same)
    }

    /// «Desde aquí»: la serie recuerda el idioma (y el latino o castellano) de la versión elegida; vale también en la TV.
    /// `forSeries`: el idioma nuevo; `keep`: el mismo de la serie (se vuelve a guardar con la pista de esta versión).
    private func finish(_ source: Source, _ purpose: Purpose, forSeries code: String?, keep: Bool = false) {
        if let code {
            let track = source.audio.first(where: { $0.code == code })?.code ?? code
            env.services.titlePrefs.remember(metaID: metaID, audioTrack: track)
        } else if keep {
            let track = source.audio.first(where: { $0.base == prefs.audio && $0.evidence.solid })?.code ?? source.audio.first?.code
            if let track { env.services.titlePrefs.remember(metaID: metaID, audioTrack: track) }
        }
        choose(source, purpose)
    }

    /// Tocar un renglón: la que hay que pedir se pide (ya pedida, cómo va); las demás se ven (o se bajan).
    private func open(_ option: VersionOption, code: String, _ purpose: Purpose = .watch) {
        if option.speed == .realDebridMustDownload, request != nil {
            if requestStatus(option.id) != nil { waiting = Waiting(id: option.id) } else { ask(option.id) }
            return
        }
        guard let source = observer.model.source(option.id) else { return }
        pick(source, purpose, code: code)
    }

    @State private var showsGlossary = false
    /// Lo que la lista no deja ver (cuánto le sobra o le falta a su marco) y el alto de la hoja: en ventana ancha (iPad,
    /// Mac) la tarjeta mide lo que trae, con tope en el de la ventana, en vez de un hueco abajo con pocas versiones.
    @State private var listSlack: CGFloat = 0
    @State private var sheetHeight: CGFloat = 0
    @State private var showsMore = false
    /// «Todas» (la lista completa y plana), desde el enlace del pie.
    @State private var showsAll = SourcesSheet.demoShowsAll
    /// `-demo-open sources-all`: la hoja ya en «Todas» (solo en las compilaciones de prueba; `Demo` no existe en la de tienda).
    private static var demoShowsAll: Bool {
        #if DEBUG
        Demo.isOn && Demo.open == "sources-all"
        #else
        false
        #endif
    }
    private static var demoBottom: Bool {
        #if DEBUG
        Demo.isOn && Demo.open == "sources-request"
        #else
        false
        #endif
    }

    /// V3 · la versión elegida en otro idioma, esperando «¿Para el resto de la serie también?».
    @State private var seriesAsk: SeriesAsk?
    struct SeriesAsk: Identifiable { let source: Source; let purpose: Purpose; let code: String; var id: Int { source.index } }
    /// RX2-A · una ya pedida que baja en la nube: cuánto falta y, si hay, la que ya arranca.
    @State private var waiting: Waiting?
    struct Waiting: Identifiable { let id: Int }
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

    /// El pedido de esa versión en tu cuenta, si ya existe: su estado, nunca pedirla otra vez. `full` (RX2-A): abajo cuánto
    /// falta, con «Te aviso» solo si este aparato va a avisar.
    private func requestStatus(_ id: Int, full: Bool = false) -> DebridRequestStatus? {
        let requests = env.services.debridRequests
        let _ = requests.track()
        guard let hash = observer.model.source(id)?.torrent?.hash, let found = requests.request(hash: hash) else { return nil }
        let tr = { (key: String) in Strings.tr(key, language: env.services.appSettings.uiLanguage) }
        let notifies = DebridRequestNotifier.canNotify && requests.isFromHere(found)
        return DebridRequestStatus(symbol: DebridRequestWords.symbol(found.state), title: DebridRequestWords.title(found, tr),
                                   detail: full ? DebridRequestWords.paceLine(found, now: Date(), notifies: notifies, tr) : nil,
                                   fraction: found.state == .downloading ? Double(found.percent) / 100 : nil,
                                   warn: DebridRequestWords.isTrouble(found, now: Date()), ok: found.state == .ready)
    }

    /// RX2-A · mientras la tuya baja en la nube: la mejor que ya arranca en tus idiomas (la primera de la misma lista que
    /// usa «Ver»), «Ver Inglés · 1080p, ya arranca». nil si no hay ninguna.
    private func instantInstead(_ model: SourcesModel, _ ui: String) -> (title: Text, action: () -> Void)? {
        let instant = model.languageRows.flatMap { row in row.options.filter { $0.cached && !$0.otherTitle }.map { (row.code, $0) } }
        guard let source = model.ranked.first(where: { s in instant.contains { $0.1.id == s.index } }),
              let match = instant.first(where: { $0.1.id == source.index }) else { return nil }
        let name = "\(Streams.versionLanguageName(match.0, in: ui)) · \(match.1.quality)"
        return (Text("Ver \(Text.withFlagImages(LanguageFlags.flagged(name, match.0))), ya arranca"), { waiting = nil; pick(source, .watch, code: match.0) })
    }

    /// Ventana ancha (iPad, Mac): la tarjeta mide lo que trae, con tope en el alto de la ventana. Sin `fixedSize` (cortaba la
    /// lista): el alto de ahora más lo que a la lista le sobra o le falta. nil mientras no se ha medido.
    private var fittedHeight: CGFloat? {
        guard sheetHeight > 0 else { return nil }
        return min(max(DS.Size.touchTarget * 6, sheetHeight + listSlack), WindowMetrics.size.height * DS.Sheet.maxShare)
    }

    var body: some View {
        let model = observer.model
        let ui = env.services.appSettings.uiLanguage
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSheetHeader(title: Text("Versión"), subtitle: showsAll ? Text("Todas, por calidad · toca una") : Text("Toca para ver · mantén presionado para más")) {
                // Qué quiere decir cada ícono y etiqueta (⚡, ☁︎, 4K, DV, REMUX…).
                Button { showsGlossary = true } label: { Image(systemName: "info.circle").font(DS.TextRecipe.section.font) }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget, alignment: .trailing)   // el ícono al ras del margen, el toque sigue de 44
                    .accessibilityLabel(Text("Qué significa cada etiqueta"))
                    .accessibilityIdentifier("sources-info")
            }
            .padding(.horizontal, DS.Space.s4)
            ScrollView {
                VStack(spacing: DS.Space.s2) {   // ds-exception: renglones de la lista de versiones, no secciones de pantalla
                    if model.isLoading { VersionsSkeleton() }   // la forma de lo que viene, no una ruedita sola
                    // V4: sin ninguna versión, la causa de la tabla de «Ver» con su salida, no un aviso suelto.
                    if !model.isLoading, let cause = model.emptyCause {
                        VersionsEmptyCause(cause: cause, uiLanguage: ui, perform: { emptyExit($0, model) })
                    } else if let error = model.error { DSNotice(verbatim: env.message(error), tone: .warn) }
                    if showsAll {
                        if !model.ranked.isEmpty {
                            AllSourcesList(sources: model.ranked, current: model.recommendedIndex,
                                           primary: ("Ver", { pick($0, .watch) }), secondary: ("Descargar", { pick($0, .download) }),
                                           uiLanguage: ui, prefs: prefs,
                                           offersSecondary: { s in s.playbackURL.map { !["m3u8", "mpd"].contains($0.pathExtension.lowercased()) } ?? false },
                                           request: request == nil ? nil : { ask($0.index) }, requestStatus: { requestStatus($0.index) })
                        }
                    } else {
                        byLanguage(model, ui)
                    }
                    // C8: si un complemento no contestó a tiempo, se dice quién (sus versiones no están aquí).
                    if !model.isLoading, !model.quiet.isEmpty {
                        AddonQuietLine(names: model.quiet) { Task { await model.retryQuiet(onCellular: env.connectivity.isCellular) } }
                            .padding(.top, DS.Space.s1)
                    }
                    // V3 · «Todas» ya no es una pestaña: un enlace al pie (y de vuelta).
                    if !model.isLoading, !model.ranked.isEmpty { allLink(model) }
                }
            }
            .defaultScrollAnchor(Self.demoBottom ? .bottom : nil)   // `-demo-open sources-request`: abre abajo, en «Hay que pedirlas»
            .contentMargins(.horizontal, DS.Space.s4, for: .scrollContent)
            .contentMargins(.vertical, DS.Space.s1, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height + $0.contentInsets.top + $0.contentInsets.bottom - $0.containerSize.height } action: { _, slack in listSlack = slack }
            if env.connectivity.isCellular {
                Text("Con datos móviles te avisamos antes de usar versiones de más de \(Int(env.services.appSettings.warnCellularOverGB)) GB.").recipe(.caption, color: DS.textFaint).padding(.horizontal, DS.Space.s4)
            }
        }
        .dsSheetContent(sides: false)   // el carrusel llega a las orillas: cada parte pone su margen
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sheetHeight = $0 }
        .modifier(VersionSheetSizing(fitted: fittedHeight))
        .task {
            model.playerOpen = { HardwareVolumeButtons.yieldsToPlayer }   // con el reproductor abierto no se revisa el audio de nada
            await model.load(onCellular: env.connectivity.isCellular)
            #if DEBUG
            demoSeriesAsk(model)
            #endif
        }
        .sheet(item: $asking) { pending in DebridNotifyAsk { _ in asking = nil; await request?(pending.source) } }
        .debridFlowIntro(when: request != nil && !model.toRequest.isEmpty && !showsAll)   // RX3-A: «↓ Por pedir» a la vista
        .sheet(isPresented: $showsGlossary) { SourcesGlossary().fittedSheet().presentationDragIndicator(.visible) }
        // Las dos preguntas son tarjetas de la app (Fernando, 13 nov 2026: «también conviértelos en la tarjeta»). Lo que
        // eliges corre cuando la tarjeta ya se cerró: «Ver Inglés…» puede traer después la de la serie sin chocar con ella.
        .choiceSheet(item: $seriesAsk) { ask in seriesCard(ask, ui) }
        .choiceSheet(item: $waiting) { item in waitingCard(item, model, ui) }
    }

    /// V3 · «¿Para el resto de la serie también?»: «Sí, desde aquí» (la serie sigue en ese idioma) o «Solo este episodio».
    /// Cerrarla sin elegir no abre nada, como antes.
    private func seriesCard(_ ask: SeriesAsk, _ ui: String) -> ChoiceCard {
        ChoiceCard(title: Text("¿Para el resto de la serie también?"),
                   detail: Text("Los siguientes episodios, en \(VersionText.inline(VersionText.name(ask.code, ui), ui))."),
                   primary: ChoiceAction(id: "series-from-here", title: Text("Sí, desde aquí"), symbol: DS.Symbol.fromHereOn) {
                       finish(ask.source, ask.purpose, forSeries: ask.code)
                   },
                   options: [ChoiceAction(id: "series-only-this", title: Text("Solo este episodio"), symbol: DS.Symbol.onlyThisOne) {
                       finish(ask.source, ask.purpose, forSeries: nil)
                   }],
                   id: "series-ask-card")
    }

    /// RX2-A · una ya pedida que baja en la nube: arriba cómo va («Bajando en la nube · 34 %» y cuánto falta) y, si hay, la
    /// que ya arranca en tus idiomas. Esperar es cerrarla (deslizar, tocar fuera o Esc): el pedido sigue igual.
    private func waitingCard(_ item: Waiting, _ model: SourcesModel, _ ui: String) -> ChoiceCard {
        let status = requestStatus(item.id, full: true)
        return ChoiceCard(title: Text(verbatim: status?.title ?? ""), detail: status?.detail.map { Text(verbatim: $0) },   // no-es-título: el estado del pedido
                          primary: instantInstead(model, ui).map { instead in
                              ChoiceAction(id: "request-instead", title: instead.title, symbol: "play.fill", run: instead.action)   // no-es-título: «Ver Inglés · 1080p, ya arranca»
                          },
                          id: "request-waiting-card")
    }

    #if DEBUG
    /// `-demo-open sources-series`: en un episodio, como tocar una versión en otro idioma que el de la serie (trae la tarjeta
    /// «¿Para el resto de la serie también?» sin tocar la pantalla).
    private func demoSeriesAsk(_ model: SourcesModel) {
        guard Demo.isOn, Demo.open == "sources-series", episode,
              let row = model.languageRows.first(where: { !speaksSeries($0.code) && $0.options.contains { $0.cached } }),
              let option = row.options.first(where: \.cached), let source = model.source(option.id) else { return }
        pick(source, .watch, code: row.code)
    }
    #endif

    /// V3 · el enlace del pie: «Ver todas las versiones · 34» o, ya en «Todas», volver a la lista por idioma.
    private func allLink(_ model: SourcesModel) -> some View {
        Button { withAnimation(DS.Motion.fade) { showsAll.toggle() } } label: {
            Label { showsAll ? Text("Ver por idioma") : Text("Ver todas las versiones · \(model.ranked.count)") }
                icon: { Image(systemName: showsAll ? "flag" : "list.bullet") }
                .recipe(.secondary, color: DS.textMuted)
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sources-all")
    }

    /// V4 · la salida de la causa de una hoja vacía. «Pedir a la nube» y «Elegir otra versión» no llevan botón: lo que se
    /// puede pedir ya está abajo y no hay otra versión que elegir.
    private func emptyExit(_ action: UnavailableCause.Action, _ model: SourcesModel) -> (() -> Void)? {
        switch action {
        case .retry: { Task { await model.load(onCellular: env.connectivity.isCellular) } }
        case .renew: { UIApplication.shared.open(env.services.debrid.provider.renewURL) }   // en el navegador
        case .settings: { dismiss(); env.ui.openSettings = true }
        case .request, .otherVersion: nil
        }
    }

    /// Un renglón de la lista con su menú de mantener presionado.
    private func versionRow(_ row: LanguageRow, _ option: VersionOption, showsLanguage: Bool, _ model: SourcesModel, _ ui: String) -> some View {
        VersionListRow(option: option, code: row.code, uiLanguage: ui, showsLanguage: showsLanguage,
                       cloud: option.speed == .realDebridMustDownload ? requestStatus(option.id) : nil,
                       action: { open(option, code: row.code) }) {
            actions(option, row, model, ui)
        }
    }

    /// Lo que antes tenía la tarjeta, al mantener presionado: Ver o Pedir, Descargar, Infuse y las otras de ese idioma y calidad.
    @ViewBuilder private func actions(_ option: VersionOption, _ row: LanguageRow, _ model: SourcesModel, _ ui: String) -> some View {
        let mustAsk = option.speed == .realDebridMustDownload && request != nil
        if mustAsk {
            if requestStatus(option.id) == nil { Button("Pedir a la nube", systemImage: DS.Symbol.cloud) { ask(option.id) } }
            else { Button("Ver cómo va", systemImage: DS.Symbol.cloud) { waiting = Waiting(id: option.id) } }
        } else {
            Button("Ver", systemImage: "play.fill") { open(option, code: row.code) }
            if option.downloadable { Button("Descargar", systemImage: "arrow.down") { open(option, code: row.code, .download) } }
            if let infuse, let source = model.source(option.id) { Button("Abrir con Infuse", systemImage: "arrow.up.forward.app") { infuse(source) } }
        }
        let others = model.others(of: option, in: row)
        if !others.isEmpty {
            Menu {
                ForEach(others) { other in
                    Button { open(other, code: row.code) } label: {
                        VersionText.withSpeed(VersionText.facts(other, locale: Locale(identifier: ui)), other.speed)
                        Text(verbatim: other.release)
                    }
                }
            } label: {
                Label { Text("Otras \(others.count) en \(VersionText.inline(VersionText.name(row.code, ui), ui)) \(option.quality)") } icon: { Image(systemName: "rectangle.stack") }
            }
        }
    }

    /// «Por idioma»: tu idioma con su encabezado, los demás bajo «Otros idiomas», los de más allá plegados, las que hay que
    /// pedir y cuántas se esconden.
    @ViewBuilder private func byLanguage(_ model: SourcesModel, _ ui: String) -> some View {
        // Tu idioma existe pero no arranca al instante: se dice arriba, con la acción de pedirlo (12 nov).
        if request != nil, let yours = model.yoursToRequest {
            let name = VersionText.inline(VersionText.name(yours.code, ui), ui)
            VersionYoursAside(language: Text.withFlagImages(LanguageFlags.flagged(name, yours.code)), option: yours.option,
                              status: requestStatus(yours.id), request: { ask(yours.id) })
        }
        VersionLegend()
        VersionLanguageList(rows: model.languageRows, uiLanguage: ui) { row, option, showsLanguage in
            versionRow(row, option, showsLanguage: showsLanguage, model, ui)
        }
        if !model.moreLanguages.isEmpty {
            DisclosureGroup(isExpanded: $showsMore) {
                VersionGroup {
                    ForEach(model.moreLanguages) { row in
                        ForEach(row.options) { option in versionRow(row, option, showsLanguage: true, model, ui) }
                    }
                }
                .padding(.top, DS.Space.s2)
            } label: {
                Text("\(Text("Más idiomas · "))\(Text.withFlagImages(model.moreLanguages.map { LanguageFlags.flagged(VersionText.inline(Streams.versionLanguageName($0.code, in: ui), ui), $0.code) }.joined(separator: ", ")))")
            }
            .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
            .padding(DS.Space.s3)
            .dsCard(translucent: true)
            .tint(DS.textMuted)
        }
        // La de tu idioma ya va arriba («Hay latino, pero hay que pedirlo a la nube»): aquí no se repite.
        let toRequest = model.toRequest.filter { $0.id != model.yoursToRequest?.id }
        if request != nil, !toRequest.isEmpty {
            VersionRequestGroup {
                ForEach(toRequest) { item in
                    let name = Streams.versionLanguageName(item.code, in: ui)
                    VersionRequestRow(title: Text("\(Text.flag(item.code))\(Text(verbatim: "\(name) · \(item.option.quality)"))"), option: item.option,
                                      status: requestStatus(item.id), request: { ask(item.id) },
                                      open: { open(item.option, code: item.code) })
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

/// Qué quiere decir cada etiqueta de las fuentes, en corto.
struct SourcesGlossary: View {
    /// La marca de Torrentio y Comet solo donde hay complementos (D1-B).
    private var entries: [(String, LocalizedStringKey, LocalizedStringKey)] {
        AppEnvironment.shared.services.capabilities.instantStreams ? Self.all : Self.all.filter { $0.0 != "t.circle" }
    }
    private static let all: [(String, LocalizedStringKey, LocalizedStringKey)] = [
        ("sparkles", "Recomendada", "La que elegimos por calidad, idioma y tamaño. Es la que arranca sola."),
        ("bolt.fill", "Al instante", "Ya está en la nube: empieza sin esperar."),
        (DS.Symbol.cloud, "Hay que pedirla", "Aún no está en la nube: tocarla la pide y te avisamos cuando llegue."),
        ("info.circle", "Tal vez", "Hay pistas del idioma, pero no seguras. Mantén presionado para ver por qué."),
        ("t.circle", "Torrentio · Comet", "De qué complemento viene: Ⓣ Torrentio y Ⓒ Comet. Las de otros complementos no llevan marca."),   // edición: se quita sin instantStreams (`entries`)
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

/// El alto de «Versión»: a la medida de su lista con tope (`DS.Sheet.maxShare` de la ventana), en el iPhone igual que en
/// ventana ancha (iPad, Mac). Antes medía siempre lo mismo y con pocas versiones quedaba un hueco abajo (iPad 10 nov, iPhone
/// 11 nov 2026). La altura va en `presentationDetents`: así iOS vuelve a medir la hoja cuando la lista termina de llegar;
/// mientras no se mide, la hoja grande de siempre.
private struct VersionSheetSizing: ViewModifier {
    let fitted: CGFloat?

    func body(content: Content) -> some View {
        // Sin `if`: cambiar de rama volvería a crear la hoja (y a cargar las versiones) al terminar de medir.
        let wide = WindowMetrics.size.width > DS.TitleAction.readableWidth ? fitted : nil   // ds-exception: una hoja flota sobre la ventana, no va en la columna
        content.presentationDetents(fitted.map { [.height($0)] } ?? [.large]).fittedFormSizing(idealHeight: wide)
    }
}
