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

    init() {
        _observer = StateObject(wrappedValue: ModelObserver(DownloadsModel(AppEnvironment.shared.services, freeSpace: { DiskSpace.freeBytes() })))
    }

    var body: some View {
        let model = observer.model
        let settings = env.services.appSettings
        List {
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
                            .swipeActions { Button("Borrar", role: .destructive) { Task { for item in g.items { await model.remove(item.id) } } }.tint(DS.danger) }
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
                            readyRow(title: g.title, poster: g.poster, data: [item.quality, bytes(g.bytes)].compactMap { $0 }, item: item, model: model)
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
                ContentUnavailableView {
                    Label("Nada descargado", systemImage: "arrow.down.circle")
                } description: {
                    Text("En una ficha, toca Descargar y lo ves aquí sin conexión.")
                }
            }
        }
        .listRowSpacing(DS.Space.s2)
        .tint(DS.accent)   // interruptores y botones de la lista: el acento (lo interactivo)
        .scrollContentBackground(.hidden).background(Backdrop(tint: tint.colors))
        .navigationTitle("Descargas").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .subtitle(model.active.isEmpty ? nil : Text("\(model.active.count) descargando"))   // el espacio, en su barra
        .toolbar { ToolbarItem(placement: .topBarTrailing) { ProfileButton() } }
        .titleDestinations()
        .navigationDestination(for: SettingsRoute.self) { _ in SettingsView() }
        .navigationDestination(for: DownloadSeriesRoute.self) { DownloadSeriesView(observer: observer, metaID: $0.metaID) }
        .navigationDestination(for: DownloadSeasonRoute.self) { DownloadSeasonView(observer: observer, metaID: $0.metaID, season: $0.season) }
        .task { await model.run() }
        .task(id: model.active.first?.metaID) {
            // El arte de metahub solo existe para ids de IMDb; con otro id, fondo liso.
            await tint.load(model.active.first.flatMap { $0.metaID.hasPrefix("tt") ? String(format: ForYou.metahubBackground, $0.metaID) : nil })
        }
    }

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
                DataLine(parts: [item.subtitle.isEmpty ? nil : item.subtitle, item.quality, status(item)].compactMap { $0 }, color: item.state == .failed ? DS.danger : nil)
                if let progress = item.progress { DSProgress(fraction: progress) }
            }
            Spacer(minLength: DS.Space.s2)
            switch item.state {
            case .downloading, .queued: DSIconButton(symbol: "pause.fill", label: "Pausar") { Task { await model.pause(item.id) } }
            case .paused, .failed: DSIconButton(symbol: "play.fill", label: "Reanudar") { Task { await model.resume(item.id) } }
            case .done: EmptyView()
            }
        }
        .padding(.vertical, DS.Space.s1)
        .swipeActions { Button("Borrar", role: .destructive) { Task { await model.remove(item.id) } }.tint(DS.danger) }   // rojo, como en iOS (el tinte de la app lo dejaba blanco)
    }

    private func status(_ item: DownloadItem) -> String? {
        let language = env.services.appSettings.uiLanguage
        switch item.state {
        case .queued: return Strings.tr("En cola", language: language)
        case .downloading: return "\(bytes(item.writtenBytes)) / \(item.expectedBytes.map(bytes) ?? "—")"
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
        .swipeActions { Button("Borrar", role: .destructive) { Task { await model.remove(item.id) } }.tint(DS.danger) }   // rojo, como en iOS (el tinte de la app lo dejaba blanco)
        .contextMenu { fileMenu(item, title: title, model: model) }
    }

    /// Lo que se hace con el archivo, como con cualquier otro: compartirlo (AirDrop, Guardar en Archivos, otra app) o borrarlo.
    @ViewBuilder func fileMenu(_ item: DownloadItem, title: String, model: DownloadsModel) -> some View {
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
                                    Text(verbatim: season.bytes.formatted(.byteCount(style: .file)))
                                } label: {
                                    Text("Temporada \(season.number)").recipe(.cardTitle)
                                    Text("\(season.items.count) episodios").recipe(.footnote)
                                }
                            }
                            .swipeActions { Button("Borrar", role: .destructive) { Task { for item in season.items { await observer.model.remove(item.id) } } }.tint(DS.danger) }
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
                                DataLine(parts: [item.quality, item.writtenBytes.formatted(.byteCount(style: .file))].compactMap { $0 })
                            }
                            Spacer(minLength: DS.Space.s2)
                            Image(systemName: "play.circle.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.text).accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button("Borrar", role: .destructive) { Task { await model.remove(item.id) } }.tint(DS.danger) }
                    .contextMenu {
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

