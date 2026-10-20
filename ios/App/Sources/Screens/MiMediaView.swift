import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un título de Mi media (su id: «movie:tt…» o «series:tt…»).
struct MiMediaTitleRoute: Hashable { let id: String }
/// Una carpeta de tu OneDrive, tal cual (la vista de carpetas).
struct MiMediaFolderRoute: Hashable { let path: String }

/// Descargas › Mi media: tu carpeta de OneDrive como biblioteca (como Infuse). Lo recién agregado, filtros, sagas, todas
/// tus películas y series, y lo que no se reconoció para corregirlo. Lo que bajas al iPhone sale en «En el iPhone».
struct MiMediaView<Top: View>: View {
    @ObservedObject var observer: ModelObserver<MiMediaModel>
    /// Lo que va arriba de todo, deslizándose con lo demás («En el iPhone | Mi media»).
    @ViewBuilder var top: () -> Top
    @EnvironmentObject private var env: AppEnvironment
    @State private var fixing: OneDriveFile?

    var body: some View {
        let model = observer.model
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.s6) {
                top()
                if model.needsFolder {
                    DSEmptyState(symbol: "folder", title: Text("Elige la carpeta de tus películas"),
                                 message: Text("Solo se mira esa carpeta y sus subcarpetas.")) {
                        NavigationLink { OneDriveSettings() } label: { Text("Elegir carpeta") }.dsPrimaryButton()
                    }
                } else if !model.ready {
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
        .task { await model.load(); await model.localizeNames() }
        .onChange(of: model.all.map(\.imdb)) { Task { await model.localizeNames() } }
        .task { await model.followDownloads() }
        .sheet(item: $fixing) { file in FixMatchSheet(info: file.info, fileName: file.name, model: model) }
    }

    /// Tu carpeta: cuántos títulos, cuándo se revisó, revisar ahora y más (orden, carpetas, ajustes).
    private func header(_ model: MiMediaModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                if let name = OneDriveModel.folderName(model.folder) { Text("Tu OneDrive · \(name)").recipe(.cardTitle).lineLimit(1) }
                else { Text("Todo tu OneDrive").recipe(.cardTitle) }
                Text("Películas: \(model.movies) · Series: \(model.series)").recipe(.caption).lineLimit(1)
                if model.scanning { Text("Revisando…").recipe(.caption) }
                else if let at = model.scannedAt { Text("Revisada \(at, format: .relative(presentation: .named))").recipe(.caption).lineLimit(1) }
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
        .padding(.vertical, DS.Space.s1)   // sin tarjeta: el texto alinea con el margen de los pósters y del filtro
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
                PosterView(url: t.poster, title: model.name(t))
                    .overlay(alignment: .topLeading) { if model.isNew(t) { DSBadge(text: "Nuevo").padding(DS.Space.s2) } }   // placa sólida como en Inicio: se lee sobre cualquier póster
                    .overlay(alignment: .bottomTrailing) {
                        if model.onPhoneCount(t) > 0 {
                            Image(systemName: "arrow.down.circle.fill").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.good, DS.backdropDeep)
                                .padding(DS.Space.s1).accessibilityLabel(Text("En el iPhone"))
                        }
                    }
                Text(verbatim: model.name(t)).recipe(.footnote, color: DS.text).lineLimit(1)
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

/// Un título de Mi media: ver (donde ibas), bajar al iPhone, sus versiones (película) o sus episodios con los que faltan
/// (serie), los datos del archivo y «Corregir ficha». Con el color de su arte, como la ficha.
struct MiMediaTitleView: View {
    @ObservedObject var observer: ModelObserver<MiMediaModel>
    let id: String
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tint = ArtTint()
    @State private var seasons: [(season: Int, rows: [MiMediaModel.EpisodeRow])] = []
    @State private var season = 0
    @State private var next: String?
    @State private var fixing = false
    /// «Buscar fuente» de un episodio que no está en tu carpeta: la hoja de fuentes de Real-Debrid de ese episodio.
    @State private var findingSource: MissingEpisode?
    @State private var titleModel: TitleModel?
    struct MissingEpisode: Identifiable { let id: String }
    /// El idioma de la app (no el del iPhone) para fechas e idiomas.
    private var appLocale: Locale { Locale(identifier: env.services.appSettings.uiLanguage) }

    var body: some View {
        let model = observer.model
        Group {
            if let t = model.all.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.s5) {
                        hero(t, name: model.name(t))
                        actions(t, model)
                        if t.kind == "series" { episodes(t, model) } else { versions(t, model) }
                        fixRow(t)
                    }
                    .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s4)
                }
                .task(id: t.entries.count) {
                    next = await model.continueVideo(t)
                    guard t.kind == "series" else { return }
                    seasons = await model.episodes(t)
                    let wanted = next.flatMap { v in seasons.first { $0.rows.contains { $0.id == v } }?.season }
                    if let wanted { season = wanted } else if !seasons.contains(where: { $0.season == season }) { season = seasons.first?.season ?? 0 }
                }
                .task { await tint.load(String(format: ForYou.metahubBackground, t.imdb)) }
                .sheet(item: $findingSource) { missing in
                    if let tm = titleModel {
                        SourcesSheet(model: tm, videoID: missing.id, purpose: .watch) { source, purpose in
                            findingSource = nil
                            Task { await useSource(source, purpose: purpose, videoID: missing.id, tm) }
                        }
                        .presentationDetents([.large]).presentationDragIndicator(.visible)
                    }
                }
                .sheet(isPresented: $fixing) {
                    if let first = t.entries.first {
                        // Al corregir cambia la ficha (y su id): se regresa a Mi media, donde ya sale con la buena.
                        FixMatchSheet(info: first.file.info, fileName: first.file.name, model: model) { result in
                            await model.fix(t, to: result)
                            dismiss()
                        }
                    }
                }
            } else {
                DSEmptyState(symbol: "film", title: Text("Ya no está en tu carpeta"))
            }
        }
        .task { await model.followDownloads() }
        .scrollContentBackground(.hidden).background(Backdrop(tint: tint.colors))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(_ t: OneDriveLibrary.Title, name: String) -> some View {
        HStack(alignment: .bottom, spacing: DS.Space.s4) {
            PosterView(url: t.poster, title: name).frame(width: DS.Poster.railWidth)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("En tu OneDrive").recipe(.eyebrow, color: DS.eyebrow)
                Text(verbatim: name).recipe(.title).lineLimit(3)
                DataLine(parts: [Strings.kind(t.kind, language: env.services.appSettings.uiLanguage), t.year ?? "", ByteSize.text(Int64(t.bytes), locale: env.uiLocale)])
            }
        }
    }

    private func episodeName(_ videoID: String) -> String {
        let parts = videoID.split(separator: ":")
        guard parts.count >= 3, let s = Int(parts[parts.count - 2]), let e = Int(parts[parts.count - 1]) else { return "" }
        return env.services.episodeLabel(s, e)
    }

    /// Ver (donde ibas: tu copia, o la del iPhone si ya la bajaste) y bajar al iPhone (la de 1080p). En una serie, la temporada.
    @ViewBuilder private func actions(_ t: OneDriveLibrary.Title, _ model: MiMediaModel) -> some View {
        let target = next ?? (t.kind == "movie" ? t.imdb : t.entries.first?.videoID)
        HStack(spacing: DS.Space.s3) {
            Button { if let target { play(t, videoID: target, model) } } label: {
                ActionTileLabel(title: t.kind == "series" && target != nil ? Text("Ver \(episodeName(target ?? ""))") : Text("Ver"), symbol: "play.fill")
            }
            .buttonStyle(.plain).disabled(target == nil)
            if t.kind == "series" {
                let rows = seasons.first(where: { $0.season == season })?.rows ?? []
                let pending = rows.filter { !$0.missing && model.onPhone[$0.id] == nil }
                Button { Task { for r in pending { await report(model.download(t, videoID: r.id)) } } } label: {
                    ActionTileLabel(title: pending.isEmpty && !rows.isEmpty ? Text("En el iPhone") : Text("Bajar temporada"),
                                    symbol: pending.isEmpty && !rows.isEmpty ? "checkmark.circle" : "arrow.down.circle", active: pending.isEmpty && !rows.isEmpty)
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
                // Solo los idiomas que dice el nombre (sin ninguno, el lector supone inglés: eso no se enseña).
                let languages = d.languages == ["en"] ? [] : d.languages
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    HStack {
                        Text(verbatim: ([d.resolution] + d.hdr + d.audioBadges).filter { !$0.isEmpty }.joined(separator: " · ")).recipe(.cardTitle)
                        Spacer()
                        Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(e.file.size), countStyle: .file)).recipe(.data)
                    }
                    DataLine(parts: [languages.map { appLocale.localizedString(forLanguageCode: $0)?.capitalized(with: appLocale) ?? $0 }.joined(separator: ", "),
                                     e.file.added.map { env.message("Agregada") + " " + $0.formatted(Date.RelativeFormatStyle(presentation: .named, locale: appLocale)) } ?? ""])
                    Text(verbatim: e.file.path).recipe(.caption, color: DS.textFaint).lineLimit(2)
                    if t.entries.count > 1 {
                        HStack(spacing: DS.Space.s2) {
                            Button("Ver esta", systemImage: "play.fill") { play(t, videoID: e.videoID, version: e, model) }
                            Button("Bajar esta", systemImage: "arrow.down.circle") { Task { await report(model.download(t, videoID: e.videoID, entry: e)) } }
                                .disabled(model.onPhone[e.videoID] != nil)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(DS.Space.s3)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            }
            if t.entries.count > 1 { Text("«Ver» usa la mejor; «Descargar», la de 1080p.").recipe(.caption) }
        }
    }

    /// Una serie: sus temporadas y episodios; los que no están en tu carpeta, en gris con «Buscar fuente».
    private func episodes(_ t: OneDriveLibrary.Title, _ model: MiMediaModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            if seasons.count > 1 {
                let chips = seasons.map { SeasonChip(season: $0.season, isSpecials: $0.season == 0) }
                let selection = Binding(get: { SeasonChip(season: season, isSpecials: season == 0) }, set: { season = $0.season })
                let label = { (s: SeasonChip) in s.isSpecials ? Text("Especiales") : Text("Temporada \(s.season)") }
                // Como la ficha: hasta 4 temporadas como filtros a la vista; con más, un menú.
                if chips.count <= DS.Size.seasonChipsMax {
                    DSChipRow(items: chips, label: label, selection: selection).padding(.horizontal, -DS.Space.gutter)
                } else {
                    DSOptionMenu(items: chips, label: label, selection: selection)
                }
            }
            if seasons.isEmpty { ProgressView().frame(maxWidth: .infinity) }
            ForEach(seasons.first(where: { $0.season == season })?.rows ?? []) { row in episodeRow(t, row, model) }
        }
    }

    private func episodeRow(_ t: OneDriveLibrary.Title, _ row: MiMediaModel.EpisodeRow, _ model: MiMediaModel) -> some View {
        let best = row.versions.first
        let name = row.episode.hasTitle ? row.episode.title : String(format: Strings.tr("Episodio %lld", language: env.services.appSettings.uiLanguage), row.episode.episode)
        return HStack(spacing: DS.Space.s3) {
            // Tocar el episodio lo pone (un botón de verdad: VoiceOver lo anuncia); lo de la derecha es aparte.
            Button { if !row.missing { play(t, videoID: row.id, model) } } label: {
                HStack(spacing: DS.Space.s3) {
                    Text(verbatim: "\(row.episode.episode)").recipe(.data, color: DS.textMuted)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: name).recipe(.secondary, color: row.missing ? DS.textMuted : DS.text).lineLimit(1)
                        if row.missing { Text("No está en tu carpeta").recipe(.caption) }
                        else if let best {
                            DataLine(parts: [best.details.resolution, ByteCountFormatter.string(fromByteCount: Int64(best.file.size), countStyle: .file)])
                        }
                    }
                    Spacer(minLength: DS.Space.s2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(row.missing)
            .accessibilityHint(row.missing ? Text("No está en tu carpeta") : Text("Ver"))
            if row.missing {
                Button("Buscar fuente") {
                    if titleModel == nil { titleModel = TitleModel(env.services, kind: "series", metaID: t.imdb, hint: (t.name, t.poster)) }
                    findingSource = MissingEpisode(id: row.id)
                }
                .buttonStyle(.bordered)
            } else if let state = model.onPhone[row.id] {
                if state >= 1 { Image(systemName: "arrow.down.circle.fill").foregroundStyle(DS.good).accessibilityLabel(Text("En el iPhone")) }
                else { DownloadRing(fraction: state, lineWidth: DS.TitleAction.ringSmallLine).frame(width: DS.TitleAction.ringSmall, height: DS.TitleAction.ringSmall) }
            } else {
                DSIconButton(symbol: "arrow.down", label: "Descargar") { Task { await report(model.download(t, videoID: row.id)) } }
            }
        }
        .padding(.vertical, DS.Space.s2)
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
        Task {
            let request = await model.playRequest(t, videoID: videoID, version: version)
            // Con Infuse elegido: lo que ya está en el iPhone se abre allá; tu copia de OneDrive se ve aquí (Infuse no la conoce).
            if env.services.appSettings.preferInfuse, request.localFile != nil { await env.playExternal(request) } else { env.play(request) }
        }
    }

    /// Una fuente de Real-Debrid para un episodio que no tienes: verla o bajarla, como desde la ficha.
    private func useSource(_ source: Source, purpose: Purpose, videoID: String, _ tm: TitleModel) async {
        await tm.load()   // la ficha: el nombre del episodio y el siguiente
        switch purpose {
        case .watch:
            guard var request = tm.playRequest(videoID: videoID) else { return }
            request.sourceIndex = source.index
            if env.services.appSettings.preferInfuse { await env.playExternal(request, source: source) } else { env.play(request) }
        case .download:
            await report(tm.download([videoID], source: source), ownCopy: false)
        }
    }

    private func report(_ outcome: TitleModel.DownloadOutcome, ownCopy: Bool = true) async {
        switch outcome {
        case .queued: break   // lo dice el anillo
        case .noSources: env.notify(ownCopy ? "No encontré ese archivo en tu OneDrive." : "No hay fuentes de Real-Debrid para descargar.")
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
    /// Qué hacer al elegir (por omisión, corregir solo ese nombre).
    var choose: ((SearchResult) async -> Void)?
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
                        Button { Task { if let choose { await choose(r) } else { await model.fix(info, to: r) }; dismiss() } } label: {
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
        .navigationTitle(OneDriveModel.folderName(path).map { Text(verbatim: $0) } ?? Text("OneDrive")).navigationBarTitleDisplayMode(.inline)
        .task {
            do { let found = try await observer.model.listing(path); folders = found.folders; videos = found.videos }
            catch { self.error = "\(error)" }
        }
    }

    private func play(_ file: OneDriveFile) async {
        do { env.play(try await observer.model.playRequest(file: file)) } catch { env.notify("No pude pedir el archivo a OneDrive.") }
    }
}
