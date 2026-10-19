import SwiftUI
import UniformTypeIdentifiers
import OrbitalCore
import OrbitalModels

/// Descargas: lo que se está bajando (con su avance), lo listo para ver sin conexión agrupado por título y la descarga
/// inteligente. El espacio va en el subtítulo de la barra; el fondo toma el color de lo que se está bajando.
struct DownloadsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var observer: ModelObserver<DownloadsModel>
    @StateObject private var tint = ArtTint()
    /// La descarga a la que se le buscan subtítulos.
    @State private var subtitlesFor: DownloadItem?
    /// Mi media (tu OneDrive como biblioteca) junto a lo que ya está en el iPhone.
    @StateObject private var media = ModelObserver(MiMediaModel(AppEnvironment.shared.services))
    enum Part: Hashable { case phone, media }
    @State private var part: Part = .phone

    init() {
        _observer = StateObject(wrappedValue: ModelObserver(DownloadsModel(AppEnvironment.shared.services, freeSpace: { DiskSpace.freeBytes() })))
    }

    /// Con OneDrive conectado: «En el iPhone | Mi media» arriba.
    private var showsMedia: Bool { env.services.oneDrive.linked }

    var body: some View {
        let model = observer.model
        Group {
            if showsMedia && part == .media { MiMediaView(observer: media) } else { phoneList(model) }
        }
        .safeAreaInset(edge: .top) {
            if showsMedia {
                DSSegmented(options: [(Part.phone, "En el iPhone"), (.media, "Mi media")], selection: $part)
                    .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s2)
            }
        }
        .navigationTitle("Descargas").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .subtitle(downloadingCount(model) == 0 ? nil : Text("\(downloadingCount(model)) descargando"))   // solo las que bajan (no las en pausa)   // el espacio, en su barra
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(for: DownloadSeriesRoute.self) { DownloadSeriesView(observer: observer, metaID: $0.metaID) }
        .navigationDestination(for: DownloadSeasonRoute.self) { DownloadSeasonView(observer: observer, metaID: $0.metaID, season: $0.season) }
        .navigationDestination(for: MiMediaTitleRoute.self) { MiMediaTitleView(observer: media, id: $0.id) }
        .navigationDestination(for: MiMediaFolderRoute.self) { MiMediaFolderView(observer: media, path: $0.path) }
        .task {
            #if DEBUG
            if Demo.isOn, Demo.media { part = .media }
            #endif
            await model.run()
        }
        .task(id: model.items.map { "\($0.id)\($0.state)" }) { await media.model.refreshPhone() }   // lo que bajas de Mi media se marca allá
        .sheet(item: $subtitlesFor) { item in DownloadSubtitlesSheet(item: item, model: model).fittedSheet().presentationDragIndicator(.visible) }
        .task(id: model.active.first?.metaID) {
            // El arte de metahub solo existe para ids de IMDb; con otro id, fondo liso.
            await tint.load(model.active.first.flatMap { $0.metaID.hasPrefix("tt") ? String(format: ForYou.metahubBackground, $0.metaID) : nil })
        }
    }

    /// En el iPhone: lo que se baja y lo listo para ver sin conexión.
    private func phoneList(_ model: DownloadsModel) -> some View {
        let settings = env.services.appSettings
        return List {
            if !model.items.isEmpty {
                Section {
                    StorageBar(parts: [.init(id: "series", label: Text("Series"), bytes: model.items.filter { $0.kind == "series" }.reduce(0) { $0 + $1.writtenBytes }, color: DS.ListTint.series),
                                       .init(id: "movies", label: Text("Películas"), bytes: model.items.filter { $0.kind != "series" }.reduce(0) { $0 + $1.writtenBytes }, color: DS.ListTint.watching)],
                               free: model.freeBytes, total: DiskSpace.totalBytes(), format: bytes)
                }
                .listRowBackground(DS.surface)
            }
            if !model.active.isEmpty {
                Section { ForEach(model.active) { row($0, model) } } header: { DSSectionHead(title: "Descargando", count: model.active.count) }
                    .downloadCard()
            }
            // Listo para ver: series (una fila cada una; dentro, sus temporadas y episodios) y películas, aparte.
            if !model.readySeries.isEmpty {
                Section {
                    ForEach(model.readySeries) { g in
                        NavigationLink(value: DownloadSeriesRoute(metaID: g.metaID)) { seriesRow(g) }
                            .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { Task { for item in g.items { await model.remove(item.id) } } }.tint(DS.danger) }
                    }
                } header: {
                    DSSectionHead(title: Text("Series"), trailing: Text(verbatim: bytes(model.readySeries.reduce(0) { $0 + $1.bytes })))
                }
                .downloadCard()
            }
            if !model.readyMovies.isEmpty {
                Section {
                    ForEach(model.readyMovies) { g in
                        if let item = g.items.first {
                            readyRow(title: g.title, poster: g.poster, data: [fromMedia(item), item.quality, bytes(g.bytes)].compactMap { $0 }, item: item, model: model)
                        }
                    }
                } header: {
                    DSSectionHead(title: Text("Películas"), trailing: Text(verbatim: bytes(model.readyMovies.reduce(0) { $0 + $1.bytes })))
                }
                .downloadCard()
            }
            if !model.items.isEmpty {
                Section {
                    Toggle("Bajar el siguiente episodio al terminar uno", isOn: setting(\.autoNextDownload))
                    Toggle("Borrar al terminar de verlo", isOn: setting(\.deleteWhenWatched))
                } header: { DSSectionHead(title: "Descarga inteligente") } footer: {
                    if settings.wifiOnlyDownloads { Label("Solo con Wi‑Fi", systemImage: "wifi").recipe(.footnote) }
                }
                .listRowBackground(DS.surface)
            }
        }
        .overlay {
            // Sin nada en cola ni listo: el vacío nativo, con qué hacer.
            if model.items.isEmpty {
                DSEmptyState(symbol: "arrow.down.circle", title: Text("Nada descargado"), message: Text("En una ficha, toca Descargar y lo ves aquí sin conexión."))
            }
        }
        .listRowSpacing(DS.Space.s2)
        .tint(DS.accent)   // interruptores y botones de la lista: el acento (lo interactivo)
        .scrollContentBackground(.hidden).background(Backdrop(tint: tint.colors))
    }

    /// Lo que vino de tu OneDrive (Mi media), para distinguirlo de lo de Real-Debrid.
    private func fromMedia(_ item: DownloadItem) -> String? { item.addon == OneDriveLibrary.addonName ? env.message("De Mi media") : nil }

    private func downloadingCount(_ model: DownloadsModel) -> Int { model.active.filter { $0.state == .downloading || $0.state == .queued }.count }

    /// Un ajuste de Descargas como interruptor (se guarda al momento, igual que en Ajustes).
    private func setting(_ key: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { env.services.appSettings[keyPath: key] }, set: { value in env.services.settings.update { $0[keyPath: key] = value }; observer.objectWillChange.send() })
    }

    /// Lo que se está bajando: póster, nombre, datos en SF Mono, el avance y pausar o seguir.
    private func row(_ item: DownloadItem, _ model: DownloadsModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: item.poster, title: item.title).frame(width: DS.Size.thumbSmall)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(item.title).recipe(.cardTitle).lineLimit(1)
                DataLine(parts: [fromMedia(item), item.subtitle.isEmpty ? nil : item.subtitle, item.quality, status(item)].compactMap { $0 }, color: item.state == .failed ? DS.danger : nil)
            }
            Spacer(minLength: DS.Space.s2)
            // El avance es el mismo anillo de la ficha y de la fila de un episodio, con pausar o reanudar adentro.
            switch item.state {
            case .downloading, .queued: ringButton(item, symbol: "pause.fill", label: "Pausar") { Task { await model.pause(item.id) } }
            case .paused, .failed: ringButton(item, symbol: item.state == .failed ? "arrow.clockwise" : "play.fill", label: item.state == .failed ? "Reintentar" : "Reanudar") { Task { await model.resume(item.id) } }
            case .done: EmptyView()
            }
        }
        .padding(.vertical, DS.Space.s1)
        .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { Task { await model.remove(item.id) } }.tint(DS.danger) }   // rojo, como en iOS (el tinte de la app lo dejaba blanco)
    }

    private func ringButton(_ item: DownloadItem, symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                DownloadRing(fraction: item.progress ?? 0, tint: item.state == .failed ? DS.warning : DS.accent, lineWidth: DS.TitleAction.ringSmallLine)
                Image(systemName: symbol).font(DS.TextRecipe.caption.font.weight(.bold)).foregroundStyle(DS.text)
            }
            .frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall)
            .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private func status(_ item: DownloadItem) -> String? {
        let language = env.services.appSettings.uiLanguage
        let settings = env.services.appSettings
        switch item.state {
        case .queued: return Strings.tr("En cola", language: language)
        case .downloading:
            if item.waitingForNetwork { return Strings.tr(settings.wifiOnlyDownloads ? "Esperando Wi‑Fi" : "Esperando conexión", language: language) }
            return "\(bytes(item.writtenBytes)) / \(item.expectedBytes.map(bytes) ?? "—")"
        case .paused: return Strings.tr("En pausa", language: language)
        case .failed: return item.lastError.map { Strings.message($0, language: language) } ?? Strings.tr("No se pudo descargar", language: language)   // los errores fijos de la descarga, también traducidos
        case .done: return nil
        }
    }

    /// Una serie descargada: su póster, cuántas temporadas y episodios, y cuánto ocupa (sin archivos sueltos).
    private func seriesRow(_ g: DownloadGroup) -> some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: g.poster, title: g.title).frame(width: DS.Size.thumbSmall)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(g.title).recipe(.cardTitle).lineLimit(1)
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
        .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { Task { await model.remove(item.id) } }.tint(DS.danger) }   // rojo, como en iOS (el tinte de la app lo dejaba blanco)
        .contextMenu { fileMenu(item, title: title, model: model) }
    }

    /// Lo que se hace con el archivo, como con cualquier otro: compartirlo (AirDrop, Guardar en Archivos, otra app) o borrarlo.
    @ViewBuilder func fileMenu(_ item: DownloadItem, title: String, model: DownloadsModel) -> some View {
        Button("Buscar subtítulos", systemImage: "captions.bubble") { subtitlesFor = item }
        ShareLink(item: DownloadedFile(item: item, model: model), preview: SharePreview(Text(verbatim: title))) {
            Label("Compartir el archivo", systemImage: "square.and.arrow.up")
        }
        Button("Borrar", systemImage: "trash", role: .destructive) { Task { await model.remove(item.id) } }
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
    private func bytes(_ n: Int64) -> String { n.formatted(.byteCount(style: .file, spellsOutZero: false).locale(env.uiLocale)) }   // «0 KB», no «Zero kB»
}

/// A dónde lleva una serie descargada (sus temporadas) y una temporada (sus episodios).
struct DownloadSeriesRoute: Hashable { var metaID: String }
struct DownloadSeasonRoute: Hashable { var metaID: String; var season: Int }

/// Una serie descargada: con varias temporadas, una fila por temporada; con una sola, directo sus episodios.
struct DownloadSeriesView: View {
    @ObservedObject var observer: ModelObserver<DownloadsModel>
    @EnvironmentObject private var env: AppEnvironment
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
                                    Text(verbatim: season.bytes.formatted(.byteCount(style: .file, spellsOutZero: false).locale(env.uiLocale)))
                                } label: {
                                    Text("Temporada \(season.number)").recipe(.cardTitle)
                                    Text(verbatim: String(format: Strings.tr(season.items.count == 1 ? "%lld episodio" : "%lld episodios", language: env.services.appSettings.uiLanguage), season.items.count)).recipe(.footnote)
                                }
                            }
                            .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { Task { for item in season.items { await observer.model.remove(item.id) } } }.tint(DS.danger) }
                        }
                    }
                    .downloadCard()
                }
            } else if let season = group?.seasons.first {
                DownloadSeasonView(observer: observer, metaID: metaID, season: season.number)
            }
        }
        .listRowSpacing(DS.Space.s2)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: group?.title ?? "")).navigationBarTitleDisplayMode(.inline)
    }
}

/// Los episodios descargados de una temporada: tocar uno lo reproduce; deslizar lo borra.
struct DownloadSeasonView: View {
    @ObservedObject var observer: ModelObserver<DownloadsModel>
    @EnvironmentObject private var env: AppEnvironment
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
                                Text(verbatim: item.subtitle.isEmpty ? item.title : item.subtitle).recipe(.cardTitle).lineLimit(2)
                                DataLine(parts: [item.quality, item.writtenBytes.formatted(.byteCount(style: .file, spellsOutZero: false).locale(env.uiLocale))].compactMap { $0 })
                            }
                            Spacer(minLength: DS.Space.s2)
                            Image(systemName: "play.circle.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.text).accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { Task { await model.remove(item.id) } }.tint(DS.danger) }
                    .contextMenu {
                        Button("Buscar subtítulos", systemImage: "captions.bubble") { subtitlesFor = item }
                        ShareLink(item: DownloadedFile(item: item, model: model), preview: SharePreview(Text(verbatim: item.subtitle.isEmpty ? item.title : item.subtitle))) {
                            Label("Compartir el archivo", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } header: { if season > 0 { Text("Temporada \(season)") } }
            .downloadCard()
        }
        .listRowSpacing(DS.Space.s2)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: group?.title ?? "")).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $subtitlesFor) { item in DownloadSubtitlesSheet(item: item, model: model).fittedSheet().presentationDragIndicator(.visible) }
    }
}

/// «Buscar subtítulos» de una descarga: los idiomas que hay (el tuyo primero) y, al tocar uno, se baja y se guarda con el video
/// (sale sin conexión). Cada toque suma otro de ese idioma, por si el primero no va a tiempo.
struct DownloadSubtitlesSheet: View {
    let item: DownloadItem
    let model: DownloadsModel
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.locale) private var locale
    @State private var found: [SubtitleOption]?
    @State private var saved: [String: Int] = [:]
    @State private var saving: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Text("Subtítulos").recipe(.title)
            Text(verbatim: item.subtitle.isEmpty ? item.title : "\(item.title) · \(item.subtitle)").recipe(.footnote).lineLimit(1)
            if let found {
                if found.isEmpty {
                    DSNotice(text: "No encontré subtítulos (o no hay conexión). Vuelve a intentar.", tone: .warn)
                } else {
                    Text("Se guardan con la descarga: también los ves sin conexión.").recipe(.caption, color: DS.textMuted)
                    FlowChips {
                        ForEach(languages(found), id: \.self) { code in
                            let options = found.filter { $0.language == code }
                            let done = saved[code, default: 0]
                            PanelChip(title: Text(verbatim: done == 0 ? "\(name(code)) · \(options.count)" : "\(name(code)) · \(done)/\(options.count)"),
                                      selected: done > 0, symbol: saving == code ? "arrow.down.circle.dotted" : (done > 0 ? "checkmark" : "arrow.down.circle")) {
                                Task { await save(code, options) }
                            }
                            .disabled(saving != nil || done >= options.count)
                        }
                    }
                }
            } else {
                HStack(spacing: DS.Space.s2) { ProgressView(); Text("Buscando subtítulos…").recipe(.footnote) }
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
        if ok { saved[code, default: 0] += 1; env.notify("Subtítulos guardados con la descarga.", tone: .success) }
        else { env.notify("No pude bajar ese subtítulo: prueba otro.") }
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
        return locale.localizedString(forLanguageCode: two)?.capitalized(with: locale) ?? code
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
        listRowBackground(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).fill(DS.surface))
            .listRowSeparator(.hidden)
            .listSectionSpacing(DS.Space.s4)
    }
}

