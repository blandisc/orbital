import SwiftUI
import OrbitalCore
import OrbitalModels

/// La ficha de una película o serie: continuar, Mi lista, descargar, watchlist de Trakt, temporadas y episodios.
struct TitleView: View {
    let route: TitleRoute
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @StateObject private var observer: ModelObserver<TitleModel>
    @StateObject private var tint = ArtTint()
    @State private var sourcesFor: SourcesTarget?
    @State private var downloadMenu = false

    struct SourcesTarget: Identifiable { var videoID: String; var purpose: Purpose; var id: String { "\(videoID)-\(purpose)" } }

    init(route: TitleRoute) {
        self.route = route
        _observer = StateObject(wrappedValue: ModelObserver(TitleModel(AppEnvironment.shared.services, kind: route.kind, metaID: route.metaID, hint: (route.title, route.poster))))
    }

    var body: some View {
        let model = observer.model
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(model)
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    actions(model)
                    if let message = model.message { DSNotice(verbatim: env.message(message), tone: .error) }
                    if model.traktAvailable { watchlistToggle(model) }
                    if let error = model.error, model.overview.isEmpty { DSNotice(verbatim: env.message(error), tone: .warn) }
                    if !model.overview.isEmpty { Text(model.overview).font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted) }
                    if model.kind == "series" { episodes(model) }
                    credits(model)
                }
                .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s10)
                .padding(.top, scheme == .dark ? 0 : DS.Space.s4)   // en claro el arte es una tarjeta: las acciones no se le pegan
            }
        }
        .background(Backdrop(tint: tint.colors))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)     // el arte llega hasta arriba y la barra flota encima
        .toolbar { topBar(model) }
        .task { await model.followDownloads() }
        .task { await model.loadConsoleDetails() }     // la sinopsis en español, si tu Orbital está conectada
        .onChange(of: env.watchedSomething) { Task { await model.refreshState() } }   // vuelves de ver: avance, visto y «Continuar» al día
        .task {
            await model.load()
            #if DEBUG
            if Demo.isOn, Demo.open == "play" { start(model, videoID: nil) }
            if Demo.isOn, Demo.open == "sources", let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .watch) }
            if Demo.isOn, Demo.open == "download" || Demo.open == "download-here" { await report(model.download([model.continueVideoID ?? model.metaID]), model); if Demo.open == "download" { dismiss() } }
            #endif
            await tint.load(model.background ?? model.poster)
        }
        .sheet(item: $sourcesFor) { target in
            SourcesSheet(model: model, videoID: target.videoID, purpose: target.purpose) { source, purpose in
                sourcesFor = nil
                handle(source: source, videoID: target.videoID, purpose: purpose, model: model)   // lo que quedó en el selector de la hoja
            }
            .presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .confirmationDialog("Descargar", isPresented: $downloadMenu, titleVisibility: .visible) {
            if model.kind == "series" {
                Button("Los siguientes 3 episodios") { Task { await report(model.downloadNext(3), model) } }
                Button("Elegir la fuente de este episodio") { if let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .download) } }
            }
            Button("Descargar con la fuente recomendada") { Task { await report(model.download([model.continueVideoID ?? model.metaID]), model) } }
        }
    }

    // MARK: partes
    /// Arte a sangre que se funde con el fondo, el logo del título (o su nombre) y, debajo, de dónde es y hasta cuatro datos
    /// (año · género · duración · calificación, como `detail-panel.js`).
    private func hero(_ model: TitleModel) -> some View {
        BleedArt(url: model.background ?? model.poster, title: model.title, aspect: DS.Poster.heroAspect) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                TitleLogo(url: model.info.logo ?? Artwork.logoURL(metaID: model.metaID), title: model.title, size: .hero, dark: model.logoIsDark)
                let language = env.services.appSettings.uiLanguage
                let facts = [Strings.kind(model.kind, language: language)]
                    + Vocabulary.titleFacts(year: model.info.year, genres: Vocabulary.genres(model.info.genres, language: language), runtime: model.info.runtime, rating: model.info.rating)
                Text(verbatim: Vocabulary.factLine(facts)).recipe(.secondary, color: DS.onArtSecondary).lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    /// Mi lista y En la TV: botones de ícono en la barra de arriba (con su nombre para VoiceOver).
    @ToolbarContentBuilder private func topBar(_ model: TitleModel) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if env.services.orbital.isConfigured {
                Button { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: model.continueVideoID, title: model.title) } } label: { Image(systemName: "tv") }
                    .disabled(model.continueVideoID == nil)
                    .accessibilityLabel(Text("En la TV"))
            }
            // Mi lista vive en la rejilla de acciones; arriba, compartir (la ficha de IMDb, que abre en cualquier app).
            if model.metaID.hasPrefix("tt"), let url = URL(string: "https://www.imdb.com/title/\(model.metaID)/") {
                ShareLink(item: url, subject: Text(verbatim: model.title)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel(Text("Compartir"))
            }
        }
    }

    /// El botón principal (papel), a qué hora terminas y, debajo, las acciones secundarias en una rejilla (Mi lista,
    /// Descargar, Fuentes). En la TV está arriba, en la barra.
    private func actions(_ model: TitleModel) -> some View {
        let label = model.continueLabel
        return VStack(spacing: DS.Space.s3) {
            Button { start(model, videoID: nil) } label: {
                Label { primaryLabel(label, model).lineLimit(1) } icon: { Image(systemName: "play.fill") }.frame(maxWidth: .infinity)
            }
            .dsArtButton(tint.colors).controlSize(.large).disabled(model.continueVideoID == nil)   // el color del arte, como en la TV
            if let minutes = model.minutesToFinish {
                DataLine(parts: [Strings.endsAt(minutesLeft: minutes, now: env.services.now(), language: env.services.appSettings.uiLanguage)])
            }
            ActionGrid(actions: [
                ProjectionAction(id: "list", title: model.inLibrary ? "En Mi lista" : "Mi lista", symbol: model.inLibrary ? "checkmark" : "plus", active: model.inLibrary) { Task { await model.toggleLibrary() } },
                downloadAction(model),
                ProjectionAction(id: "sources", title: "Elegir fuente", symbol: "list.bullet", disabled: model.continueVideoID == nil) {
                    if let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .watch) }
                },
            ])
        }
    }

    /// En una película dice cómo va su descarga; en una serie abre el menú (siguientes episodios, elegir fuente).
    private func downloadAction(_ model: TitleModel) -> ProjectionAction {
        switch model.kind == "movie" ? model.downloadState(model.metaID) : nil {
        case .done?:
            return ProjectionAction(id: "download", title: "Descargado", symbol: "checkmark.circle", active: true) { env.notify("Ya está descargado. Lo encuentras en Descargas.", tone: .info) }
        case .downloading?, .queued?:
            let percent = model.downloadFraction(model.metaID).map { Int($0 * 100) }
            return ProjectionAction(id: "download", title: percent.map { LocalizedStringKey("\($0) %") } ?? "Descargando", symbol: "arrow.down.circle.dotted", active: true) {
                env.notify("Descargando. Lo verás en Descargas.", tone: .info)
            }
        default:
            return ProjectionAction(id: "download", title: "Descargar", symbol: "arrow.down.circle") { downloadMenu = true }
        }
    }

    private func primaryLabel(_ label: (isResume: Bool, season: Int?, episode: Int?), _ model: TitleModel) -> Text {
        if let s = label.season, let e = label.episode { return label.isResume ? Text("Continuar T\(s) E\(e)") : Text("Ver T\(s) E\(e)") }
        return label.isResume ? Text("Continuar") : Text("Ver")   // los nombres de la TV (`core/watch.js`)
    }

    private func watchlistToggle(_ model: TitleModel) -> some View {
        Toggle(isOn: Binding(get: { model.inWatchlist }, set: { _ in Task { await model.toggleWatchlist() } })) {
            Label("En tu watchlist", systemImage: "bookmark")
        }
        .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
        .padding(DS.Space.s3).background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .sensoryFeedback(.success, trigger: model.inWatchlist)
    }

    @ViewBuilder private func episodes(_ model: TitleModel) -> some View {
        if model.seasons.count > 1 {
            let chips = model.seasons.map { SeasonChip(season: $0.season, isSpecials: $0.isSpecials) }
            let selection = Binding(get: { SeasonChip(season: model.selectedSeason, isSpecials: model.selectedSeason == 0) }, set: { model.select(season: $0.season) })
            let label = { (season: SeasonChip) in season.isSpecials ? Text("Especiales") : Text("Temporada \(season.season)") }
            // Hasta 4 temporadas caben como filtros a la vista; con más, un menú (como Apple TV y Netflix).
            if chips.count <= DS.Size.seasonChipsMax {
                DSChipRow(items: chips, label: label, selection: selection).padding(.horizontal, -DS.Space.gutter)
            } else {
                DSOptionMenu(items: chips, label: label, selection: selection)
            }
        }
        VStack(spacing: 0) {
            ForEach(model.rows) { row in
                EpisodeRowView(row: row, play: { start(model, videoID: row.id) }, download: { Task { await report(model.download([row.id]), model) } },
                               markWatched: { Task { await model.markWatched(row.id) } }, chooseSource: { sourcesFor = SourcesTarget(videoID: row.id, purpose: .watch) },
                               downloadFraction: model.downloadFraction(row.id),
                               playOnTV: env.services.orbital.isConfigured ? { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: row.id, title: model.title) } } : nil)
                Divider().overlay(DS.hairline)
            }
        }
    }

    @ViewBuilder private func credits(_ model: TitleModel) -> some View {
        if !model.credits.cast.isEmpty || !model.credits.directors.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                if !model.credits.cast.isEmpty { creditLine("Reparto", model.credits.cast) }
                if !model.credits.directors.isEmpty { creditLine("Dirección", model.credits.directors) }
                if !model.credits.writers.isEmpty { creditLine("Guion", model.credits.writers) }
            }
        }
    }

    private func creditLine(_ title: LocalizedStringKey, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(title).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint)
            Text(names.joined(separator: ", ")).font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
        }
    }

    // MARK: acciones
    private func start(_ model: TitleModel, videoID: String?, source: Source? = nil) {
        guard var request = model.playRequest(videoID: videoID) else { return }
        request.sourceIndex = source?.index
        if env.services.appSettings.preferInfuse { Task { await env.playExternal(request, source: source) } } else { env.play(request) }
    }

    private func handle(source: Source, videoID: String, purpose: Purpose, model: TitleModel) {
        switch purpose {
        case .watch: start(model, videoID: videoID, source: source)
        case .download: Task { await report(model.download([videoID]), model) }
        }
    }

    private func report(_ outcome: TitleModel.DownloadOutcome, _ model: TitleModel) async {
        switch outcome {
        case .queued(let n): if n == 1 { env.notify("Descargando. Lo verás en Descargas.", tone: .success) } else { env.notify(format: "Descargando %lld episodios. Los verás en Descargas.", n, tone: .success) }
        case .noSources: env.notify("No hay fuentes de Real-Debrid para descargar.")
        case .notEnoughSpace(let text): env.notify(text)
        case .already: env.notify("Ya está descargado.", tone: .info)
        case .failed(let text): env.notify(text)
        }
        await model.refreshState()
    }
}

/// Una temporada en la tira de filtros.
struct SeasonChip: Hashable, Identifiable {
    var season: Int
    var isSpecials: Bool
    var id: Int { season }
}

struct EpisodeRowView: View {
    let row: EpisodeRow
    let play: () -> Void
    let download: () -> Void
    let markWatched: () -> Void
    let chooseSource: () -> Void
    var downloadFraction: Double?
    var playOnTV: (() -> Void)?

    var body: some View {
        // El botón de descargar va junto, no dentro, del que reproduce: anidados, tocar la flecha ponía el episodio.
        // Miniatura, texto y estado en una misma línea central: el estado siempre cae en la misma columna.
        HStack(alignment: .center, spacing: DS.Space.s3) {
            Button(action: play) {
                HStack(alignment: .center, spacing: DS.Space.s3) {
                    ZStack(alignment: .bottom) {
                        PosterView(url: row.thumbnail, title: "\(row.number)", aspect: DS.Poster.stillAspect)
                        if let progress = row.progress { DSProgress(fraction: progress) }
                    }
                    .frame(width: DS.Poster.episodeThumbWidth, height: DS.Poster.episodeThumbWidth / DS.Poster.stillAspect).clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        (row.hasTitle ? Text("\(row.number) · \(row.title)") : Text("Episodio \(row.number)")).font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text).lineLimit(2)
                        if hasStatus { status.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted) }
                        if !row.overview.isEmpty { Text(row.overview).font(DS.TextRecipe.caption.font).foregroundStyle(DS.textFaint).lineLimit(2) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            stateIcon.frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
        }
        .padding(.vertical, DS.Space.s3)
        .contextMenu {
            Button("Marcar como visto", systemImage: "checkmark.circle", action: markWatched)
            Button("Descargar", systemImage: "arrow.down.circle", action: download)
            Button("Elegir fuente", systemImage: "list.bullet", action: chooseSource)
            if let playOnTV { Button("Ver en la TV", systemImage: "tv", action: playOnTV) }
        }
    }

    private var hasStatus: Bool { row.watched || row.leftMinutes > 0 || row.download == .done }

    @ViewBuilder private var status: some View {
        if row.watched { Text("Visto") }
        else if row.leftMinutes > 0 { Text(timeLeftText(minutes: row.leftMinutes)) }
        else if row.download == .done { Text("Descargado") }
    }

    @ViewBuilder private var stateIcon: some View {
        if row.watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.good) }
        else if row.download == .done { Image(systemName: "arrow.down.circle.fill").foregroundStyle(DS.good) }
        else if row.download == .downloading || row.download == .queued {
            if let downloadFraction { Gauge(value: downloadFraction) { EmptyView() }.gaugeStyle(.accessoryCircularCapacity).tint(DS.primary).scaleEffect(DS.Gauge.episodeScale) }
            else { ProgressView() }
        }
        else { Button(action: download) { Image(systemName: "arrow.down.circle").foregroundStyle(DS.textMuted).frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget) }.buttonStyle(.plain).accessibilityLabel(Text("Descargar")) }
    }
}
