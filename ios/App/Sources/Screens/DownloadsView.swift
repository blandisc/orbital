import SwiftUI
import UniformTypeIdentifiers
import OrbitalCore
import OrbitalModels

/// La pestaña Biblioteca (Fernando, 3 nov 2026: BI2-A), con tres pestañas de texto arriba: «Descargas» · «Mi media» ·
/// «Guardado». Abre donde la dejaste (en este aparato); la primera vez, en Guardado. Un aviso de descargas abre «Descargas».
///
/// «Descargas», en dos partes (RX1-A, 3 nov): «Para ver sin internet» arriba (lo que se está bajando a este aparato,
/// con su avance, lo listo para ver sin conexión agrupado por título y la descarga inteligente) y, abajo, «Lo que
/// pediste» (lo que pediste a la nube, `DownloadsCloudPart`; Fernando, 4 nov: primero el aparato). Sin Real-Debrid (Plus, App Store) solo hay la segunda
/// y no lleva rótulo. El fondo toma el color de lo que se está bajando. «Mi media» es tu OneDrive (luego Plex y Jellyfin) y
/// «Guardado», lo tuyo en pestañas: Mi lista · Viendo · Vistas · Listas (`LibrarySavedView`, GD2).
struct DownloadsView: View {
    @Environment(\.titleName) var titleName
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var observer: ModelObserver<DownloadsModel>
    @State private var tint = ArtTint()
    /// La descarga a la que se le buscan subtítulos.
    @State private var subtitlesFor: DownloadItem?
    /// Mi media (tu OneDrive como biblioteca) junto a lo que ya está en el iPhone.
    @State private var media = ModelObserver(MiMediaModel(AppEnvironment.shared.services))
    /// Las tres partes de Biblioteca, en su orden.
    enum Part: String, Hashable { case phone = "downloads", media, saved }
    @State private var part: Part = DownloadsView.lastPart
    /// Mi lista y tus listas de Trakt (Guardado).
    @State private var saved = ModelObserver(SavedModel(AppEnvironment.shared.services))
    @State private var cloud = CloudSheets()
    /// Lo que baja en la nube (Real-Debrid): «Descargas · 2» en la pestaña de texto.
    @State private var cloudActive = 0
    @State private var cloudWatch: ObservableModel.Subscription?
    static let partKey = "library.part"

    /// Donde la dejaste en este aparato; la primera vez, Guardado (BI2-A). En la demostración, siempre igual: Guardado, o lo
    /// que pida `-demo-library` (`-demo-media` y `-demo-downloads` abren su parte).
    private static var lastPart: Part {
        #if DEBUG
        if Demo.isOn { return Demo.libraryPart.flatMap(Part.init(rawValue:)) ?? (Demo.media ? .media : Demo.has("-demo-downloads") ? .phone : .saved) }
        #endif
        return UserDefaults.standard.string(forKey: partKey).flatMap(Part.init(rawValue:)) ?? .saved
    }

    init() {
        _observer = State(wrappedValue: ModelObserver(DownloadsModel(AppEnvironment.shared.services, freeSpace: { DiskSpace.freeBytes() })))
    }

    /// Las tres partes con su fondo, su selector fijo arriba y su título.
    private var parts: some View {
        let model = observer.model
        return Group {
            switch part {
            // iPad y Mac: la lista al centro, no estirada a todo lo ancho. Guardado no: sus pósters y sus listas aprovechan el
            // ancho con más columnas (GD2), como toda cuadrícula de la app.
            case .media: MiMediaView(observer: media) { EmptyView() }.readableListWidth()
            case .phone: phoneList(model).readableListWidth()
            case .saved: LibrarySavedView(observer: saved)
            }
        }
        // Un solo fondo para las tres partes, también mientras cargan y vacías: antes solo Descargas lo traía y Mi media y
        // Guardado se quedaban en negro; al cambiar de parte cambiaba el fondo (Fernando, 4 nov 2026, la 1774). Toma el color
        // de lo que se está bajando, sea cual sea la parte.
        .scrollContentBackground(.hidden)
        .background(Backdrop(tint: tint.colors))
        // El selector, fijo arriba en una barra del sistema (con el desvanecido del contenido debajo): igual en las tres vistas,
        // así al cambiar no brinca ni se mueve nada.
        .safeAreaBar(edge: .top) {
            switcher.padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s2)
        }
        .navigationTitle("Biblioteca").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .learnCoach(.downloads, title: "Biblioteca", detail: "Lo que guardes para ver sin internet vive aquí, en tu iPhone.")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
    }

    /// A dónde lleva cada cosa que se toca en la Biblioteca.
    private func withDestinations(_ content: some View) -> some View {
        content
            .titleDestinations()
            .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
            .navigationDestination(for: DownloadSeriesRoute.self) { DownloadSeriesView(observer: observer, metaID: $0.metaID) }
            .navigationDestination(for: DownloadSeasonRoute.self) { DownloadSeasonView(observer: observer, metaID: $0.metaID, season: $0.season) }
            .navigationDestination(for: MiMediaTitleRoute.self) { MiMediaTitleView(observer: media, id: $0.id) }
            .navigationDestination(for: MiMediaFolderRoute.self) { MiMediaFolderView(observer: media, path: $0.path) }
            .navigationDestination(for: SavedListRoute.self) { SavedListScreen(observer: saved, listID: $0.id) }
    }

    var body: some View {
        let model = observer.model
        // En partes: el compilador de la CI (Xcode 26.3) no alcanzaba a revisar toda la Biblioteca de una vez.
        withDestinations(parts)
        .task { await model.run() }
        .onChange(of: part) { _, new in
            #if DEBUG
            if Demo.isOn { return }
            #endif
            UserDefaults.standard.set(new.rawValue, forKey: Self.partKey)
        }
        // Un aviso de descargas, «Ver en Descargas» o «Tus pedidos»: a «Descargas», aunque la dejaras en otra parte.
        .onChange(of: env.ui.showDownloads, initial: true) { _, wants in if wants { part = .phone; env.ui.showDownloads = false } }
        // El aviso «Ya está…» de un pedido: aquí, con su hoja abierta.
        .onChange(of: env.ui.openCloudRequest, initial: true) { _, hash in
            guard let hash else { return }
            part = .phone
            cloud.opened = .init(id: hash)
            env.ui.openCloudRequest = nil
        }
        // Viendo Descargas, lo que avisaba ya está a la vista: se quitan sus avisos y la marca de la pestaña (Fernando, 4 nov
        // 2026, la 1774: «si ya estás en Descargas, el aviso y la marca deben morir»).
        .onAppear { seeing(part == .phone) }
        .onDisappear { seeing(false) }
        .onChange(of: part) { _, new in seeing(new == .phone) }
        .task {
            let requests = env.services.debridRequests
            cloudActive = requests.active.count
            cloudWatch = requests.onChange { let count = requests.active.count; if count != cloudActive { cloudActive = count } }
        }
        .task(id: model.items.map { "\($0.id)\($0.state)" }) { await media.model.refreshPhone() }   // lo que bajas de Mi media se marca allá
        .sheet(item: $subtitlesFor) { item in DownloadSubtitlesSheet(item: item, model: model).fittedSheet().presentationDragIndicator(.visible) }
        .task(id: model.active.first?.metaID) {
            // El arte de metahub solo existe para ids de IMDb; con otro id, fondo liso.
            await tint.load(model.active.first.flatMap { $0.metaID.hasPrefix("tt") ? String(format: ForYou.metahubBackground, $0.metaID) : nil })
        }
    }

    /// Descargas está (o deja de estar) a la vista.
    private func seeing(_ on: Bool) {
        if env.ui.seeingDownloads != on { env.ui.seeingDownloads = on }
        if on { Task { await DebridRequestNotifier.clearDelivered() } }
    }

    /// «Descargas · Mi media · Guardado».
    private var switcher: some View {
        // «Descargas» (Real-Debrid y este aparato, RX1-A; dice cuántas bajan), Mi media (tu OneDrive; luego Plex y Jellyfin), con
        // carpeta: la nube es solo Real-Debrid (Fernando, 3 nov), y Guardado (Mi lista y tus listas de Trakt, BI1-A).
        let bajando = cloudActive + observer.model.active.count
        return DSTextTabs(options: [.init(id: Part.phone, title: Text("Descargas"), symbol: "arrow.down.circle", badge: bajando), .init(id: .media, title: Text("Mi media"), symbol: "folder"),
                                    .init(id: .saved, title: Text("Guardado"), symbol: "bookmark")], selection: $part)
            .accessibilityIdentifier("library-parts")
    }

    private func phoneList(_ model: DownloadsModel) -> some View {
        let showsCloud = DownloadsCloudPart.shows(env.services)
        // Con la nube arriba, «Descargando», «Series»… son subsecciones de «En este iPhone» (dos niveles, nada más).
        let level: DSSectionHead.Level = showsCloud ? .subsection : .section
        let symbol = { (name: String) in showsCloud ? nil : name }
        return List {
            // Primero «Para ver sin internet» y abajo «Lo que pediste» (Fernando, 4 nov 2026, la 1774).
            if showsCloud {
                Section {
                    DSSectionHead(title: Text("Para ver sin internet"), level: .section, symbol: ThisDevice.symbol)   // antes «En este iPhone · sin internet», que se leía como aviso de que no hay red (revisión del 11 nov)
                        .listHeadRow().accessibilityIdentifier("downloads-device")
                    if model.items.isEmpty { deviceEmpty.listRowBackground(Color.clear) }
                }
                .downloadCard()
            }
            if !model.items.isEmpty {
                Section {
                    StorageBar(parts: [.init(id: "series", label: Text("Series"), bytes: model.readySeries.reduce(0) { $0 + $1.bytes }, color: DS.ListTint.series),
                                       .init(id: "movies", label: Text("Películas"), bytes: model.readyMovies.reduce(0) { $0 + $1.bytes }, color: DS.ListTint.watching)],
                               free: model.freeBytes, total: DiskSpace.totalBytes(), format: bytes)
                }
                .listRowBackground(DS.surface)
            }
            if !model.active.isEmpty {
                Section {
                    DSSectionHead(title: "Descargando", count: model.active.count, level: level, symbol: symbol("arrow.down.circle")).listHeadRow()
                    ForEach(model.active) { row($0, model) }
                }
                .downloadCard()
            }
            // Listo para ver: series (una fila cada una; dentro, sus temporadas y episodios) y películas, aparte.
            if !model.readySeries.isEmpty {
                Section {
                    DSSectionHead(title: Text("Series"), trailing: Text(verbatim: bytes(model.readySeries.reduce(0) { $0 + $1.bytes })), level: level, symbol: symbol("tv")).listHeadRow()
                    ForEach(model.readySeries) { g in
                        NavigationLink(value: DownloadSeriesRoute(metaID: g.metaID)) { seriesRow(g) }
                            .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { model.delete(g.items.map(\.id)) }.tint(DS.danger) }
                    }
                }
                .downloadCard()
            }
            if !model.readyMovies.isEmpty {
                Section {
                    DSSectionHead(title: Text("Películas"), trailing: Text(verbatim: bytes(model.readyMovies.reduce(0) { $0 + $1.bytes })), level: level, symbol: symbol("film")).listHeadRow()
                    // Un renglón por cada película, siempre (un `if` que a veces no pinta nada descuadra la lista al borrar).
                    ForEach(model.readyMovies.compactMap { g in g.items.first.map { (g, $0) } }, id: \.0.id) { g, item in
                        readyRow(title: titleName(g.title, id: g.metaID, kind: g.kind), poster: g.poster, data: [fromMedia(item), item.quality, bytes(g.bytes)].compactMap { $0 }, item: item, model: model)
                    }
                }
                .downloadCard()
            }
            if !model.items.isEmpty {
                Section {
                    // Dos flechas en círculo: «automático» (la chispa era el ícono típico de la IA; Fernando, 2 nov 2026, J1).
                    DSSectionHead(title: "Descarga inteligente", level: level, symbol: symbol(DS.Symbol.automatic)).listHeadRow()
                    DSToggleRow("Bajar el siguiente episodio", detail: "Cuando acabas de ver uno", isOn: setting(\.autoNextDownload))
                    DSToggleRow("Borrar al terminar de verlo", isOn: setting(\.deleteWhenWatched))
                    // El mismo ajuste de Ajustes › Descargas, aquí a la mano (antes era una nota que no se podía tocar; J4).
                    DSToggleRow("Solo con Wi‑Fi", symbol: "wifi", isOn: setting(\.wifiOnlyDownloads))
                }
                .listRowBackground(DS.surface)
            }
            if showsCloud { DownloadsCloudPart(sheets: $cloud) }
        }
        .overlay(alignment: .top) {
            // Sin nube y sin nada en cola ni listo: el vacío nativo, con qué hacer (con nube, cada parte tiene el suyo). Arriba,
            // donde empezaría la lista, como en Guardado e Historial (I13: aquí iba centrado y allá arriba).
            if model.items.isEmpty && !showsCloud { deviceEmpty.padding(.top, DS.Space.s2) }
        }
        .modifier(CloudSheetsHost(sheets: $cloud, active: showsCloud))
        .perfTag("downloads")   // «downloads.shown» con la lista (o el vacío), «downloads.image» con la primera imagen
        .listRowSpacing(DS.Space.s2)
        .listHeadRows()   // el rótulo a 20 de su tarjeta y unos 40 entre secciones (I2)
        // Si todo cabe (o está vacía), la lista no se mueve: antes bajaba sin nada que ver y el título se encogía.
        .scrollBounceBehavior(.basedOnSize)
        // Las tarjetas a 16 pt en todos los tamaños (la lista agrupada las metía 16 o 24 según el ancho) y los encabezados al
        // ras de ellas, como en el resto de la app.
        .listSectionMargins(.horizontal, DS.Space.gutter)
        // El espacio va pegado al selector (la lista agrupada dejaba un hueco grande arriba de su primera sección).
        .contentMargins(.top, DS.Space.s2, for: .scrollContent)
        .tint(DS.accent)   // interruptores y botones de la lista: el acento (lo interactivo)
        .scrollContentBackground(.hidden)   // el fondo lo pone la Biblioteca, el mismo en sus tres partes
        // Lo que termina pasa de «Descargando» a su lugar en Series o Películas deslizándose, no de golpe.
        .animation(DS.Motion.snap(reduceMotion) ?? DS.Motion.fade, value: model.items.map { "\($0.id):\($0.state)" })
    }

    /// Nada descargado en este aparato: qué hacer y su única salida, buscar qué ver.
    private var deviceEmpty: some View {
        DSEmptyState(symbol: "arrow.down.circle", title: Text("Nada descargado"), message: Text("En una ficha, toca Descargar y lo ves aquí sin internet.")) {
            Button("Buscar qué ver") { env.openTab = AppEnvironment.searchTab }.accessibilityIdentifier("downloads-empty-search")
        }
    }

    /// Lo que vino de tu OneDrive (Mi media), para distinguirlo de lo de Real-Debrid.
    private func fromMedia(_ item: DownloadItem) -> String? { item.addon == OneDriveLibrary.addonName ? env.message("De Mi media") : nil }

    /// Un ajuste de Descargas como interruptor (se guarda al momento, igual que en Ajustes).
    private func setting(_ key: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { env.services.appSettings[keyPath: key] }, set: { value in env.services.settings.update { $0[keyPath: key] = value }; observer.invalidate() })
    }

    /// Lo que se está bajando: póster, nombre, datos en SF Mono, el avance y pausar o seguir.
    private func row(_ item: DownloadItem, _ model: DownloadsModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: item.poster, title: titleName(item.title, id: item.metaID, kind: item.kind)).frame(width: DS.Size.thumbSmall)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Dos renglones para el nombre y el estado en el suyo: con letra grande «En pausa» se caía al final de la línea.
                let details = [fromMedia(item), item.subtitle.isEmpty ? nil : item.subtitle, item.quality].compactMap { $0 }
                if item.state == .downloading && !item.waitingForNetwork {
                    // Bajando: el nombre y siempre dos renglones de datos, sin desparramarse: qué es y cuánto lleva, y la
                    // velocidad con lo que falta (lo que no cabe se deja fuera, no se parte en más renglones).
                    Text(verbatim: titleName(item.title, id: item.metaID, kind: item.kind)).recipe(.cardTitle).lineLimit(1)
                    DataLine(parts: details + ["\(bytes(item.writtenBytes)) / \(item.expectedBytes.map(bytes) ?? "—")"])
                    DataLine(parts: speedParts(item, model))
                } else {
                    Text(verbatim: titleName(item.title, id: item.metaID, kind: item.kind)).recipe(.cardTitle).lineLimit(2)
                    if !details.isEmpty { DataLine(parts: details) }
                    if let status = status(item, model) { Text(verbatim: status).recipe(.data, color: item.state == .failed ? DS.danger : nil).lineLimit(2) }
                }
            }
            Spacer(minLength: DS.Space.s2)
            // El avance es el mismo anillo de la ficha y de la fila de un episodio, con pausar o reanudar adentro.
            switch item.state {
            case .downloading, .queued: DownloadRingButton(fraction: item.progress ?? 0, action: .pause) { Task { await model.pause(item.id) } }
            case .paused, .failed: DownloadRingButton(fraction: item.progress ?? 0, action: item.state == .failed ? .retry : .resume) { Task { await model.resume(item.id) } }
            case .done: EmptyView()
            }
        }
        .padding(.vertical, DS.Space.s1)
        .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { model.delete([item.id]) }.tint(DS.danger) }   // rojo, como en iOS (el tinte de la app lo dejaba blanco)
    }

    /// «12 MB/s · faltan 3 min» (o «Calculando…» mientras se mide).
    private func speedParts(_ item: DownloadItem, _ model: DownloadsModel) -> [String] {
        let language = env.services.appSettings.uiLanguage
        var parts: [String] = []
        if let speed = model.speeds[item.id] { parts.append(bytes(Int64(speed)) + "/s") }
        if let left = model.secondsLeft(item) {
            let units: Set<Duration.UnitsFormatStyle.Unit> = left >= 3600 ? [.hours, .minutes] : [.minutes, .seconds]
            let time = Duration.seconds(left).formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: left >= 3600 ? 2 : 1).locale(env.uiLocale))
            parts.append(String(format: Strings.tr("faltan %@", language: language), time))
        }
        return parts.isEmpty ? [Strings.tr("Calculando…", language: language)] : parts
    }

    private func status(_ item: DownloadItem, _ model: DownloadsModel) -> String? {
        let language = env.services.appSettings.uiLanguage
        let settings = env.services.appSettings
        switch item.state {
        case .queued: return Strings.tr("En cola", language: language)
        case .downloading:
            if item.waitingForNetwork { return Strings.tr(settings.wifiOnlyDownloads ? "Esperando Wi‑Fi" : "Esperando conexión", language: language) }
            // Dos renglones: «1.2 GB / 4.5 GB» y abajo «18 MB/s · faltan 3 min» (en uno solo se desparramaba).
            let progress = "\(bytes(item.writtenBytes)) / \(item.expectedBytes.map(bytes) ?? "—")"
            var parts: [String] = []
            if let speed = model.speeds[item.id] { parts.append(bytes(Int64(speed)) + "/s") }
            if let left = model.secondsLeft(item) {
                let units: Set<Duration.UnitsFormatStyle.Unit> = left >= 3600 ? [.hours, .minutes] : [.minutes, .seconds]
                let time = Duration.seconds(left).formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: left >= 3600 ? 2 : 1).locale(env.uiLocale))
                parts.append(String(format: Strings.tr("faltan %@", language: env.services.appSettings.uiLanguage), time))
            }
            return parts.isEmpty ? progress : progress + "\n" + parts.joined(separator: " · ")
        case .paused:
            let paused = Strings.tr("En pausa", language: language)
            return item.progress.map { "\(paused) · \(Int(($0 * 100).rounded())) %" } ?? paused
        case .failed: return item.lastError.map { Strings.message($0, language: language) } ?? Strings.tr("No se pudo descargar", language: language)   // los errores fijos de la descarga, también traducidos
        case .done: return nil
        }
    }

    /// Una serie descargada: su póster, cuántas temporadas y episodios, y cuánto ocupa (sin archivos sueltos).
    private func seriesRow(_ g: DownloadGroup) -> some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: g.poster, title: titleName(g.title, id: g.metaID, kind: g.kind)).frame(width: DS.Size.thumbSmall)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: titleName(g.title, id: g.metaID, kind: g.kind)).recipe(.cardTitle).lineLimit(1)
                DataLine(parts: [g.seasons.count > 1 ? seasonsText(g.seasons.count) : seasonText(g.seasons.first?.number), episodesText(g.items.count), bytes(g.bytes)].compactMap { $0 })
            }
        }
        .padding(.vertical, DS.Space.s1)
    }

    func readyRow(title: String, poster: String?, data: [String], item: DownloadItem, model: DownloadsModel) -> some View {
        Button { Task { env.play(await model.playRequest(item)) } } label: {
            HStack(spacing: DS.Space.s3) {
                if let poster { PosterView(url: poster, title: title).frame(width: DS.Size.thumbSmall) }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(title).recipe(.cardTitle).lineLimit(1)
                    DataLine(parts: data)
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "play.circle.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.text).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, DS.Space.s1)   // aire arriba y abajo: al deslizar para borrar, el póster no se corta en las esquinas
        .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { model.delete([item.id]) }.tint(DS.danger) }   // rojo, como en iOS (el tinte de la app lo dejaba blanco)
        .contextMenu { fileMenu(item, title: title, model: model) }
    }

    /// Lo que se hace con el archivo, como con cualquier otro: compartirlo (AirDrop, Guardar en Archivos, otra app) o borrarlo.
    @ViewBuilder func fileMenu(_ item: DownloadItem, title: String, model: DownloadsModel) -> some View {
        Button("Buscar subtítulos", systemImage: "captions.bubble") { subtitlesFor = item }
        ShareLink(item: DownloadedFile(item: item, model: model), preview: SharePreview(Text(verbatim: title))) {
            Label("Compartir el archivo", systemImage: "square.and.arrow.up")
        }
        Button("Borrar", systemImage: "trash", role: .destructive) { model.delete([item.id]) }
    }

    private func episodesText(_ count: Int) -> String {
        String(format: Strings.tr(count == 1 ? "%lld episodio" : "%lld episodios", language: env.services.appSettings.uiLanguage), count)
    }

    private func seasonsText(_ count: Int) -> String {
        String(format: Strings.tr("%lld temporadas", language: env.services.appSettings.uiLanguage), count)
    }

    private func seasonText(_ number: Int?) -> String? {
        guard let number, number > 0 else { return nil }
        return String(format: Strings.tr("Temporada %lld", language: env.services.appSettings.uiLanguage), number)
    }

    /// «1,2 GB» en el idioma de la app (no en el del sistema).
    private func bytes(_ n: Int64) -> String { ByteSize.text(n, locale: env.uiLocale) }   // el mismo formato en la barra, las secciones y las filas
}

/// A dónde lleva una serie descargada (sus temporadas) y una temporada (sus episodios).
struct DownloadSeriesRoute: Hashable { var metaID: String }
struct DownloadSeasonRoute: Hashable { var metaID: String; var season: Int }

/// Una serie descargada: con varias temporadas, una fila por temporada; con una sola, directo sus episodios.
struct DownloadSeriesView: View {
    @Environment(\.titleName) var titleName
    var observer: ModelObserver<DownloadsModel>
    @Environment(AppEnvironment.self) private var env
    let metaID: String

    var body: some View {
        let group = observer.model.readySeries.first { $0.metaID == metaID }
        Group {
            if let group, group.seasons.count > 1 {
                List {
                    Section {
                        ForEach(group.seasons) { season in
                            NavigationLink(value: DownloadSeasonRoute(metaID: metaID, season: season.number)) {
                                LabeledContent {
                                    Text(verbatim: ByteSize.text(season.bytes, locale: env.uiLocale))
                                } label: {
                                    Text("Temporada \(season.number)").recipe(.cardTitle)
                                    Text(verbatim: String(format: Strings.tr(season.items.count == 1 ? "%lld episodio" : "%lld episodios", language: env.services.appSettings.uiLanguage), season.items.count)).recipe(.footnote)
                                }
                            }
                            .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { observer.model.delete(season.items.map(\.id)) }.tint(DS.danger) }
                        }
                    }
                    .downloadCard()
                }
                .readableListWidth()   // iPad y Mac: al centro, no estirada a todo lo ancho
            } else if let season = group?.seasons.first {
                DownloadSeasonView(observer: observer, metaID: metaID, season: season.number)
            }
        }
        .listRowSpacing(DS.Space.s2)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: group.map { titleName($0.title, id: $0.metaID, kind: $0.kind) } ?? "")).navigationBarTitleDisplayMode(.inline)
    }
}

/// Los episodios descargados de una temporada: tocar uno lo reproduce; deslizar lo borra.
struct DownloadSeasonView: View {
    @Environment(\.titleName) var titleName
    var observer: ModelObserver<DownloadsModel>
    @Environment(AppEnvironment.self) private var env
    @State private var subtitlesFor: DownloadItem?
    let metaID: String
    let season: Int

    var body: some View {
        let model = observer.model
        let group = model.readySeries.first { $0.metaID == metaID }
        let items = group?.seasons.first { $0.number == season }?.items ?? []
        List {
            Section {
                ForEach(items) { item in
                    Button { Task { env.play(await model.playRequest(item)) } } label: {
                        HStack(spacing: DS.Space.s3) {
                            VStack(alignment: .leading, spacing: DS.Space.s1) {
                                Text(verbatim: item.subtitle.isEmpty ? titleName(item.title, id: item.metaID, kind: item.kind) : item.subtitle).recipe(.cardTitle).lineLimit(2)
                                DataLine(parts: [item.quality, ByteSize.text(item.writtenBytes, locale: env.uiLocale)].compactMap { $0 })
                            }
                            Spacer(minLength: DS.Space.s2)
                            Image(systemName: "play.circle.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.text).accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { model.delete([item.id]) }.tint(DS.danger) }
                    .contextMenu {
                        Button("Buscar subtítulos", systemImage: "captions.bubble") { subtitlesFor = item }
                        ShareLink(item: DownloadedFile(item: item, model: model), preview: SharePreview(Text(verbatim: item.subtitle.isEmpty ? titleName(item.title, id: item.metaID, kind: item.kind) : item.subtitle))) {
                            Label("Compartir el archivo", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } header: { if season > 0 { Text("Temporada \(season)") } }
            .downloadCard()
        }
        .readableListWidth()   // iPad y Mac: al centro, no estirada a todo lo ancho
        .listRowSpacing(DS.Space.s2)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: group.map { titleName($0.title, id: $0.metaID, kind: $0.kind) } ?? "")).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $subtitlesFor) { item in DownloadSubtitlesSheet(item: item, model: model).fittedSheet().presentationDragIndicator(.visible) }
    }
}

/// «Buscar subtítulos» de una descarga: los idiomas que hay (el tuyo primero) y, al tocar uno, se baja y se guarda con el video
/// (sale sin conexión). Cada toque suma otro de ese idioma, por si el primero no va a tiempo.
struct DownloadSubtitlesSheet: View {
    @Environment(\.titleName) var titleName
    let item: DownloadItem
    let model: DownloadsModel
    @Environment(AppEnvironment.self) private var env
    @Environment(\.locale) private var locale
    @State private var found: [SubtitleOption]?
    @State private var saved: [String: Int] = [:]
    @State private var saving: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSheetHeader(title: Text("Subtítulos"), subtitle: Text(verbatim: item.subtitle.isEmpty ? titleName(item.title, id: item.metaID, kind: item.kind) : "\(titleName(item.title, id: item.metaID, kind: item.kind)) · \(item.subtitle)"))
            if let found {
                if found.isEmpty {
                    DSNotice(text: "No encontré subtítulos (o no hay conexión). Vuelve a intentar.", tone: .warn)
                } else {
                    Text("Se guardan con la descarga: también los ves sin conexión.").recipe(.caption, color: DS.textMuted)
                    FlowChips {
                        ForEach(languages(found), id: \.self) { code in
                            let options = found.filter { $0.language == code }
                            let done = saved[code, default: 0]
                            PanelChip(title: Text.flagged(done == 0 ? "\(name(code)) · \(options.count)" : "\(name(code)) · \(done)/\(options.count)"),
                                      selected: done > 0, symbol: saving == code ? "arrow.down.circle.dotted" : (done > 0 ? "checkmark" : "arrow.down.circle")) {
                                Task { await save(code, options) }
                            }
                            .disabled(saving != nil || done >= options.count)
                        }
                    }
                    .id("\(saved.sorted { $0.key < $1.key })-\(saving ?? "")")   // que se redibuje al guardar (ver `FlowChips`)
                }
            } else {
                DSInlineProgress(text: Text("Buscando subtítulos…"))
            }
        }
        .padding(DS.Space.s5)
        .task { found = await model.subtitleOptions(item) }
    }

    private func save(_ code: String, _ options: [SubtitleOption]) async {
        let next = saved[code, default: 0]
        guard next < options.count else { return }
        saving = code
        let ok = await model.saveSubtitle(item, options[next])
        saving = nil
        if ok { saved[code, default: 0] += 1; env.notify("Subtítulos guardados con la descarga", tone: .success) }
        else { env.notify("No pude bajar ese subtítulo", detail: "Prueba otro") }
    }

    /// El idioma de la app primero; luego, los que más tienen.
    private func languages(_ found: [SubtitleOption]) -> [String] {
        var counts: [String: Int] = [:]
        for o in found { counts[o.language, default: 0] += 1 }
        let mine = Set([env.services.appSettings.subtitles, env.services.appSettings.audio].flatMap { [$0, Streams.languageCodes[$0] ?? $0] })
        return counts.keys.sorted { a, b in mine.contains(a) != mine.contains(b) ? mine.contains(a) : (counts[a] ?? 0) > (counts[b] ?? 0) }
    }

    private func name(_ code: String) -> String {
        let two = Streams.languageCodes.first { $0.value == code }?.key ?? code
        return LanguageFlags.flagged(locale.localizedString(forLanguageCode: two)?.capitalized(with: locale) ?? code, code)
    }
}

/// Un archivo descargado para compartir: se prepara al compartir (con su nombre legible), no al dibujar la lista.
struct DownloadedFile: Transferable {
    let item: DownloadItem
    let model: DownloadsModel

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .movie) { file in
            guard let url = await file.model.exportURL(file.item) else { throw CocoaError(.fileNoSuchFile) }
            return SentTransferredFile(url, allowAccessingOriginalFile: true)
        }
    }
}

extension View {
    /// Cada renglón que se desliza para borrar es su propia tarjeta redondeada (con aire entre una y otra): al deslizar se
    /// mueve completa, con sus esquinas (con el fondo de la sección, la orilla quedaba recta, como tapada).
    func downloadCard() -> some View {
        listRowBackground(Color.clear.dsCard(.card))
            .listRowSeparator(.hidden)
            .listSectionSpacing(DS.Layout.betweenSections - DS.ListSection.cornerClear)   // el rótulo ya trae `cornerClear` arriba
    }
}

