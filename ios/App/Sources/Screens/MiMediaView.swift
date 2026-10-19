import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un título de Mi media (su id: «movie:tt…» o «series:tt…»).
struct MiMediaTitleRoute: Hashable { let id: String }
/// Una carpeta de tu OneDrive, tal cual (la vista de carpetas).
struct MiMediaFolderRoute: Hashable { let path: String }

/// Descargas › Mi media: tu carpeta de OneDrive como biblioteca (como Infuse). Lo recién agregado, filtros, sagas, todas
/// tus películas y series, y lo que no se reconoció para corregirlo. Lo que bajas al iPhone sale en «En el iPhone».
struct MiMediaView: View {
    @ObservedObject var observer: ModelObserver<MiMediaModel>
    @EnvironmentObject private var env: AppEnvironment
    @State private var fixing: OneDriveFile?

    var body: some View {
        let model = observer.model
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.s6) {
                if !model.ready {
                    DSEmptyState(symbol: "cloud", title: Text("Conecta tu OneDrive"),
                                 message: Text("Tus películas y series de OneDrive, aquí: se ven al instante y se bajan al iPhone.")) {
                        NavigationLink { OneDriveSettings() } label: { Text("Conectar OneDrive") }.dsPrimaryButton()
                    }
                } else {
                    header(model).padding(.horizontal, DS.Space.gutter)
                    DSSegmented(options: [(MiMediaModel.Filter.all, LocalizedStringKey("Todo")), (.movies, "Películas"), (.series, "Series"), (.unwatched, "Sin ver")],
                                selection: Binding(get: { model.filter }, set: { model.filter = $0 }))
                        .padding(.horizontal, DS.Space.gutter)
                    if model.all.isEmpty {
                        DSEmptyState(symbol: "film.stack", title: model.scanning ? Text("Revisando tu carpeta…") : Text("Nada reconocido todavía"),
                                     message: Text("Cada video se reconoce por su nombre: «Dune Part Two (2024).mkv», «Severance S01E03.mkv»."))
                    }
                    if model.filter == .all, !model.recent.isEmpty {
                        Shelf(title: Text("Recién agregado"), eyebrow: Text("Lo último que subiste")) {
                            ForEach(model.recent) { t in poster(t, model) }
                        }
                    }
                    if model.filter == .all || model.filter == .movies {
                        ForEach(model.sagas) { saga in
                            Shelf(title: Text(verbatim: saga.name), eyebrow: Text("Saga")) {
                                ForEach(saga.titles) { t in poster(t, model) }
                            }
                        }
                    }
                    grid(model)
                    if !model.unmatched.isEmpty { unmatched(model) }
                }
            }
            .padding(.vertical, DS.Space.s4)
        }
        .refreshable { await model.rescan() }
        .task { await model.load() }
        .sheet(item: $fixing) { file in FixMatchSheet(info: file.info, fileName: file.name, model: model) }
    }

    /// Tu carpeta: cuántos títulos, cuándo se revisó, revisar ahora y más (orden, carpetas, ajustes).
    private func header(_ model: MiMediaModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "cloud.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("Tu OneDrive · \((model.folder as NSString).lastPathComponent)").recipe(.cardTitle).lineLimit(1)
                if model.scanning { Text("Revisando…").recipe(.caption) }
                else if let at = model.scannedAt {
                    Text("\(model.movies) películas · \(model.series) series · \(at, format: .relative(presentation: .named))").recipe(.caption)
                }
            }
            Spacer(minLength: DS.Space.s2)
            DSMoreMenu {
                Picker("Ordenar", selection: Binding(get: { model.sort }, set: { model.sort = $0 })) {
                    Text("Recién agregado").tag(MiMediaModel.Sort.added)
                    Text("Por nombre").tag(MiMediaModel.Sort.name)
                }
                NavigationLink(value: MiMediaFolderRoute(path: model.folder)) { Label("Ver carpetas", systemImage: "folder") }
                Button("Revisar ahora", systemImage: "arrow.clockwise") { Task { await model.rescan() } }
                NavigationLink { OneDriveSettings() } label: { Label("Ajustes de OneDrive", systemImage: "gearshape") }
            }
        }
        .padding(DS.Space.s3)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private func grid(_ model: MiMediaModel) -> some View {
        let shown = model.shown
        return VStack(alignment: .leading, spacing: DS.Space.s3) {
            if !shown.isEmpty {
                DSSectionHead(title: model.filter == .series ? Text("Series") : model.filter == .movies ? Text("Películas") : Text("Todo"), count: shown.count)
                    .padding(.horizontal, DS.Space.gutter)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Poster.gridMinimum), spacing: DS.Space.s3)], alignment: .leading, spacing: DS.Space.s4) {
                ForEach(shown) { t in poster(t, model, fill: true) }
            }
            .padding(.horizontal, DS.Space.gutter)
        }
    }

    /// Un póster de Mi media: «Nuevo» si lo subiste hace poco y una palomita si ya está en el iPhone.
    private func poster(_ t: OneDriveLibrary.Title, _ model: MiMediaModel, fill: Bool = false) -> some View {
        NavigationLink(value: MiMediaTitleRoute(id: t.id)) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                PosterView(url: t.poster, title: t.name)
                    .overlay(alignment: .topLeading) { if model.isNew(t) { DSChip(text: "Nuevo", tone: .good).padding(DS.Space.s1) } }
                    .overlay(alignment: .bottomTrailing) {
                        if model.onPhoneCount(t) > 0 {
                            Image(systemName: "arrow.down.circle.fill").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.good, DS.backdropDeep)
                                .padding(DS.Space.s1).accessibilityLabel(Text("En el iPhone"))
                        }
                    }
                Text(verbatim: t.name).recipe(.footnote, color: DS.text).lineLimit(1)
                DataLine(parts: [t.bestResolution, t.kind == "series" ? count("%lld episodios", t.entries.count) : (t.entries.count > 1 ? count("%lld versiones", t.entries.count) : "")])
            }
            .frame(width: fill ? nil : DS.Poster.railWidth)
        }
        .buttonStyle(.plain)
    }

    /// «3 episodios» en el idioma de la app.
    private func count(_ key: String, _ n: Int) -> String { String(format: Strings.tr(key, language: env.services.appSettings.uiLanguage), n) }

    /// Lo que no se reconoció por su nombre: corrígelo a mano y se recuerda.
    private func unmatched(_ model: MiMediaModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            DSSectionHead(title: Text("Sin ficha"), count: model.unmatched.count, meta: Text("No los reconocí por su nombre: elige cuál es."))
            ForEach(model.unmatched, id: \.id) { file in
                HStack(spacing: DS.Space.s3) {
                    Image(systemName: "questionmark.square.dashed").foregroundStyle(DS.textMuted)
                    Text(verbatim: file.name).recipe(.footnote, color: DS.text).lineLimit(2)
                    Spacer(minLength: DS.Space.s2)
                    Button("Corregir") { fixing = file }.buttonStyle(.bordered)
                }
                .padding(DS.Space.s3)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
        }
        .padding(.horizontal, DS.Space.gutter)
    }
}

/// Un título de Mi media: ver, bajar al iPhone, sus versiones (película) o sus episodios con los que faltan (serie), los
/// datos del archivo y «Corregir ficha».
struct MiMediaTitleView: View {
    @ObservedObject var observer: ModelObserver<MiMediaModel>
    let id: String
    @EnvironmentObject private var env: AppEnvironment
    @State private var seasons: [(season: Int, rows: [MiMediaModel.EpisodeRow])] = []
    @State private var season = 0
    @State private var fixing = false
    /// El idioma de la app (no el del iPhone) para fechas e idiomas.
    private var appLocale: Locale { Locale(identifier: env.services.appSettings.uiLanguage) }

    var body: some View {
        let model = observer.model
        Group {
            if let t = model.all.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s5) {
                        hero(t)
                        actions(t, model)
                        if t.kind == "series" { episodes(t, model) } else { versions(t, model) }
                        fixRow(t)
                    }
                    .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s4)
                }
                .task(id: t.entries.count) {
                    guard t.kind == "series" else { return }
                    seasons = await model.episodes(t)
                    if !seasons.contains(where: { $0.season == season }) { season = seasons.first?.season ?? 0 }
                }
                .sheet(isPresented: $fixing) {
                    if let first = t.entries.first { FixMatchSheet(info: first.file.info, fileName: first.file.name, model: model) }
                }
            } else {
                DSEmptyState(symbol: "film", title: Text("Ya no está en tu carpeta"))
            }
        }
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ t: OneDriveLibrary.Title) -> some View {
        HStack(alignment: .bottom, spacing: DS.Space.s4) {
            PosterView(url: t.poster, title: t.name).frame(width: DS.Poster.railWidth)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("En tu OneDrive").recipe(.eyebrow, color: DS.eyebrow)
                Text(verbatim: t.name).recipe(.title).lineLimit(3)
                DataLine(parts: [t.kind == "series" ? env.message("Serie") : env.message("Película"), t.year ?? "", ByteCountFormatter.string(fromByteCount: Int64(t.bytes), countStyle: .file)])
            }
        }
    }

    /// Ver (tu copia, la mejor) y bajar al iPhone (la de 1080p). En una serie: el primer episodio que tienes y la temporada.
    @ViewBuilder private func actions(_ t: OneDriveLibrary.Title, _ model: MiMediaModel) -> some View {
        let first = t.kind == "series" ? seasons.first(where: { $0.season == season })?.rows.first(where: { !$0.missing })?.id ?? t.entries.first?.videoID : t.imdb
        HStack(spacing: DS.Space.s3) {
            Button { if let first { play(t, videoID: first, model) } } label: {
                ActionTileLabel(title: t.kind == "series" ? Text("Ver") : Text("Ver"), symbol: "play.fill")
            }
            .buttonStyle(.plain)
            if t.kind == "series" {
                let rows = seasons.first(where: { $0.season == season })?.rows ?? []
                let pending = rows.filter { !$0.missing && (model.onPhone[$0.id] ?? -1) < 0 }
                Button { Task { for r in pending { await report(model.download(t, videoID: r.id)) } } } label: {
                    ActionTileLabel(title: Text("Bajar temporada"), symbol: "arrow.down.circle", active: pending.isEmpty && !rows.isEmpty)
                }
                .buttonStyle(.plain).disabled(pending.isEmpty)
            } else {
                let state = model.onPhone[t.imdb]
                Button { Task { await report(model.download(t, videoID: t.imdb)) } } label: {
                    ActionTileLabel(title: state == 1 ? Text("En el iPhone") : Text("Descargar"), symbol: state == 1 ? "checkmark.circle" : "arrow.down.circle",
                                    active: state == 1, progress: state.flatMap { $0 < 1 ? $0 : nil })
                }
                .buttonStyle(.plain).disabled(state != nil)
            }
        }
    }

    /// Una película: sus versiones (la de la TV y la de bajar) y lo que dice cada archivo.
    private func versions(_ t: OneDriveLibrary.Title, _ model: MiMediaModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: t.entries.count > 1 ? Text("Versiones en tu carpeta") : Text("El archivo"))
            ForEach(t.entries, id: \.file.id) { e in
                let d = e.details
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack {
                        Text(verbatim: ([d.resolution] + d.hdr + d.audioBadges).filter { !$0.isEmpty }.joined(separator: " · ")).recipe(.cardTitle)
                        Spacer()
                        Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(e.file.size), countStyle: .file)).recipe(.data)
                    }
                    DataLine(parts: [d.languages.map { appLocale.localizedString(forLanguageCode: $0)?.capitalized(with: appLocale) ?? $0 }.joined(separator: ", "),
                                     e.file.added.map { env.message("Agregada") + " " + $0.formatted(Date.RelativeFormatStyle(presentation: .named, locale: appLocale)) } ?? ""])
                    Text(verbatim: e.file.path).recipe(.caption, color: DS.textFaint).lineLimit(2)
                }
                .padding(DS.Space.s3)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .contextMenu {
                    Button("Ver esta", systemImage: "play.fill") { play(t, videoID: e.videoID, version: e, model) }
                    Button("Bajar esta", systemImage: "arrow.down.circle") { Task { await report(model.download(t, videoID: e.videoID, entry: e)) } }
                }
            }
            if t.entries.count > 1 { Text("Para ver se usa la mejor; para bajar, la de 1080p. Mantén presionada una para elegirla.").recipe(.caption) }
        }
    }

    /// Una serie: sus temporadas y episodios; los que no están en tu carpeta, en gris con «Buscar fuente».
    private func episodes(_ t: OneDriveLibrary.Title, _ model: MiMediaModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if seasons.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Space.s2) {
                        ForEach(seasons, id: \.season) { s in
                            if s.season == season { Button("Temporada \(s.season)") { season = s.season }.buttonStyle(.borderedProminent).foregroundStyle(DS.onPrimary) }
                            else { Button("Temporada \(s.season)") { season = s.season }.buttonStyle(.bordered) }
                        }
                    }
                }
            }
            if seasons.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            ForEach(seasons.first(where: { $0.season == season })?.rows ?? []) { row in episodeRow(t, row, model) }
        }
    }

    private func episodeRow(_ t: OneDriveLibrary.Title, _ row: MiMediaModel.EpisodeRow, _ model: MiMediaModel) -> some View {
        let best = row.versions.first
        return HStack(spacing: DS.Space.s3) {
            Text(verbatim: "\(row.episode.episode)").recipe(.data, color: DS.textMuted)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: row.episode.hasTitle ? row.episode.title : String(format: Strings.tr("Episodio %lld", language: env.services.appSettings.uiLanguage), row.episode.episode)).recipe(.secondary, color: row.missing ? DS.textMuted : DS.text).lineLimit(1)
                if row.missing { Text("No está en tu carpeta").recipe(.caption) }
                else if let best {
                    DataLine(parts: [best.details.resolution, ByteCountFormatter.string(fromByteCount: Int64(best.file.size), countStyle: .file)])
                }
            }
            Spacer(minLength: DS.Space.s2)
            if row.missing {
                NavigationLink(value: TitleRoute(kind: "series", metaID: t.imdb, title: t.name, poster: t.poster)) { Text("Buscar fuente") }.buttonStyle(.bordered)
            } else if let state = model.onPhone[row.id] {
                if state >= 1 { Image(systemName: "arrow.down.circle.fill").foregroundStyle(DS.good).accessibilityLabel(Text("En el iPhone")) }
                else { DownloadRing(fraction: state, lineWidth: DS.TitleAction.ringSmallLine).frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall) }
            } else {
                DSIconButton(symbol: "arrow.down", label: "Descargar") { Task { await report(model.download(t, videoID: row.id)) } }
            }
        }
        .padding(.vertical, DS.Space.s2)
        .contentShape(Rectangle())
        .onTapGesture { if !row.missing { play(t, videoID: row.id, model) } }
        .opacity(row.missing ? DesignTokens.Opacity.disabled : 1)
    }

    private func fixRow(_ t: OneDriveLibrary.Title) -> some View {
        Button { fixing = true } label: {
            HStack(spacing: DS.Space.s3) {
                Image(systemName: "pencil").foregroundStyle(DS.eyebrow)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.kind == "series" ? "¿No es esta serie?" : "¿No es esta película?").recipe(.cardTitle)
                    Text("Corregir ficha: búscala por nombre").recipe(.caption)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(DS.textFaint)
            }
            .padding(DS.Space.s3)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func play(_ t: OneDriveLibrary.Title, videoID: String, version: OneDriveLibrary.Entry? = nil, _ model: MiMediaModel) {
        Task { env.play(await model.playRequest(t, videoID: videoID, version: version)) }
    }

    private func report(_ outcome: TitleModel.DownloadOutcome) async {
        switch outcome {
        case .queued: break   // lo dice el anillo
        case .noSources: env.notify("No encontré ese archivo en tu OneDrive.")
        case .notEnoughSpace(let text): env.notify(text)
        case .already: env.notify("Ya está descargado.", tone: .info)
        case .failed(let text): env.notify(text)
        }
    }
}

/// «Corregir ficha»: buscar el título por nombre y elegir el bueno. Vale para todos los archivos con ese nombre.
struct FixMatchSheet: View {
    let info: OneDriveName
    let fileName: String
    let model: MiMediaModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var searching = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Busca el título", text: $query).submitLabel(.search).onSubmit { Task { await search() } }
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                } footer: { Text(verbatim: fileName) }
                .listRowBackground(DS.surface)
                Section {
                    if searching { ProgressView().frame(maxWidth: .infinity) }
                    else if results.isEmpty { Text("Sin resultados: prueba con el título en inglés.").recipe(.footnote) }
                    ForEach(results) { r in
                        Button { Task { await model.fix(info, to: r); dismiss() } } label: {
                            HStack(spacing: DS.Space.s3) {
                                PosterView(url: r.poster, title: r.title).frame(width: DS.Size.thumbSmall)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: r.title).recipe(.cardTitle)
                                    Text(verbatim: r.year).recipe(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(DS.surface)
            }
            .scrollContentBackground(.hidden).background(Backdrop())
            .navigationTitle("Corregir ficha").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .task { query = info.title; await search() }
        }
    }

    private func search() async {
        searching = true
        results = await model.search(query, kind: info.kind)
        searching = false
    }
}

/// Tu OneDrive tal cual, por carpetas: para lo que no se reconoce (o para ver un video suelto).
struct MiMediaFolderView: View {
    @ObservedObject var observer: ModelObserver<MiMediaModel>
    let path: String
    @EnvironmentObject private var env: AppEnvironment
    @State private var folders: [OneDriveFolder]?
    @State private var videos: [OneDriveFile] = []
    @State private var error: String?

    var body: some View {
        List {
            if let error { DSNotice(verbatim: env.message(error), tone: .warn).listRowBackground(DS.surface) }
            else if let folders {
                if folders.isEmpty && videos.isEmpty { Text("Esta carpeta está vacía.").recipe(.footnote).listRowBackground(DS.surface) }
                Section {
                    ForEach(folders) { f in
                        NavigationLink(value: MiMediaFolderRoute(path: f.path)) { Label(f.name, systemImage: "folder") }
                    }
                    ForEach(videos, id: \.id) { file in
                        Button { Task { await play(file) } } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Label(file.name, systemImage: "film").recipe(.secondary, color: DS.text).lineLimit(2)
                                DataLine(parts: [OneDriveLibrary.describe(file).resolution, ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file)])
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(DS.surface)
            } else { ProgressView().frame(maxWidth: .infinity).listRowBackground(DS.surface) }
        }
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: (path as NSString).lastPathComponent)).navigationBarTitleDisplayMode(.inline)
        .task {
            do { let found = try await observer.model.listing(path); folders = found.folders; videos = found.videos }
            catch { self.error = "\(error)" }
        }
    }

    private func play(_ file: OneDriveFile) async {
        do { env.play(try await observer.model.playRequest(file: file)) } catch { env.notify("No pude pedir el archivo a OneDrive.") }
    }
}
