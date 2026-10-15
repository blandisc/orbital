import SwiftUI
import OrbitalCore
import OrbitalModels

/// La ficha de una película o serie: continuar, Mi lista, descargar, watchlist de Trakt, temporadas y episodios.
struct TitleView: View {
    let route: TitleRoute
    @EnvironmentObject private var env: AppEnvironment
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
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                hero(model)
                actions(model)
                if let message = model.message { DSNotice(text: LocalizedStringKey(message), tone: .warn) }
                if model.traktAvailable { watchlistToggle(model) }
                if let error = model.error, model.info.description.isEmpty { DSNotice(text: LocalizedStringKey(error), tone: .warn) }
                if !model.info.description.isEmpty { Text(model.info.description).font(DS.font(.md)).foregroundStyle(DS.textMuted) }
                if model.kind == "series" { episodes(model) }
                credits(model)
            }
            .padding(.horizontal, DS.Space.gutter).padding(.bottom, DS.Space.s10)
        }
        .background(TintedBackground(tint: tint.color))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(); await tint.load(model.poster) }
        .sheet(item: $sourcesFor) { target in
            SourcesSheet(model: model, videoID: target.videoID, purpose: target.purpose) { source in
                sourcesFor = nil
                handle(source: source, videoID: target.videoID, purpose: target.purpose, model: model)
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
    private func hero(_ model: TitleModel) -> some View {
        ZStack(alignment: .bottomLeading) {
            PosterView(url: model.background ?? model.poster, title: model.title, aspect: DS.Poster.heroAspect)
            LinearGradient(colors: [.clear, DS.bg], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(model.title).font(DS.font(.display, weight: .bold)).foregroundStyle(DS.text).lineLimit(3)
                Text(meta(model)).font(DS.font(.sm)).foregroundStyle(DS.textMuted)
            }
            .padding(DS.Space.s3)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xxl))
    }

    private func meta(_ model: TitleModel) -> String {
        ([model.info.year, model.info.genres.prefix(2).joined(separator: ", "), model.info.runtime, model.info.rating.isEmpty ? "" : "★ \(model.info.rating)"]).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func actions(_ model: TitleModel) -> some View {
        let label = model.continueLabel
        return VStack(spacing: DS.Space.s3) {
            Button { start(model, videoID: nil) } label: {
                Label { primaryLabel(label, model).lineLimit(1) } icon: { Image(systemName: "play.fill") }.frame(maxWidth: .infinity)
            }
            .dsPrimaryButton().controlSize(.large).disabled(model.continueVideoID == nil)
            HStack(spacing: DS.Space.s2) {
                secondary(model.inLibrary ? "En Mi lista" : "Mi lista", symbol: model.inLibrary ? "checkmark" : "plus") { Task { await model.toggleLibrary() } }
                    .sensoryFeedback(.success, trigger: model.inLibrary)
                secondary("Descargar", symbol: "arrow.down.circle") { downloadMenu = true }
                secondary("Fuentes", symbol: "list.bullet") { if let v = model.continueVideoID { sourcesFor = SourcesTarget(videoID: v, purpose: .watch) } }
                    .disabled(model.continueVideoID == nil)
            }
        }
    }

    /// Una acción secundaria con su nombre (no solo el ícono): Mi lista, Descargar, Fuentes.
    private func secondary(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DS.Space.s1) { Image(systemName: symbol); Text(title).font(DS.font(.xs)).lineLimit(1) }.frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass).buttonBorderShape(.roundedRectangle(radius: DS.Radius.lg)).controlSize(.large)
    }

    private func primaryLabel(_ label: (isResume: Bool, season: Int?, episode: Int?), _ model: TitleModel) -> Text {
        if let s = label.season, let e = label.episode { return label.isResume ? Text("Continuar T\(s) E\(e)") : Text("Reproducir T\(s) E\(e)") }
        return label.isResume ? Text("Continuar") : Text("Reproducir")
    }

    private func watchlistToggle(_ model: TitleModel) -> some View {
        Toggle(isOn: Binding(get: { model.inWatchlist }, set: { _ in Task { await model.toggleWatchlist() } })) {
            Label("En tu watchlist de Trakt", systemImage: "bookmark")
        }
        .font(DS.font(.md)).foregroundStyle(DS.text)
        .padding(DS.Space.s3).background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
        .sensoryFeedback(.success, trigger: model.inWatchlist)
    }

    @ViewBuilder private func episodes(_ model: TitleModel) -> some View {
        if model.seasons.count > 1 {
            DSChipRow(items: model.seasons.map { SeasonChip(season: $0.season, isSpecials: $0.isSpecials) },
                      label: { season in season.isSpecials ? Text("Especiales") : Text("Temporada \(season.season)") },
                      selection: Binding(get: { SeasonChip(season: model.selectedSeason, isSpecials: model.selectedSeason == 0) }, set: { model.select(season: $0.season) }))
                .padding(.horizontal, -DS.Space.gutter)
        }
        VStack(spacing: 0) {
            ForEach(model.rows) { row in
                EpisodeRowView(row: row, play: { start(model, videoID: row.id) }, download: { Task { await report(model.download([row.id]), model) } },
                               markWatched: { Task { await model.markWatched(row.id) } }, chooseSource: { sourcesFor = SourcesTarget(videoID: row.id, purpose: .watch) })
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
            Text(title).font(DS.font(.xs)).foregroundStyle(DS.textFaint)
            Text(names.joined(separator: ", ")).font(DS.font(.sm)).foregroundStyle(DS.textMuted)
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
        case .queued(let n): env.banner = n == 1 ? "Descargando. Lo verás en Descargas." : "Descargando \(n) episodios. Los verás en Descargas."
        case .noSources: env.banner = "No hay fuentes de Real-Debrid para descargar."
        case .notEnoughSpace(let text): env.banner = text
        case .already: env.banner = "Ya está descargado."
        case .failed(let text): env.banner = text
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

    var body: some View {
        Button(action: play) {
            HStack(alignment: .top, spacing: DS.Space.s3) {
                ZStack(alignment: .bottom) {
                    PosterView(url: row.thumbnail, title: "\(row.number)", aspect: DS.Poster.stillAspect)
                    if let progress = row.progress { DSProgress(fraction: progress) }
                }
                .frame(width: DS.Poster.episodeThumbWidth, height: DS.Poster.episodeThumbWidth / DS.Poster.stillAspect).clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    (row.hasTitle ? Text("\(row.number) · \(row.title)") : Text("Episodio \(row.number)")).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(2)
                    status.font(DS.font(.xs)).foregroundStyle(DS.textMuted)
                    if !row.overview.isEmpty { Text(row.overview).font(DS.font(.xs)).foregroundStyle(DS.textFaint).lineLimit(2) }
                }
                Spacer(minLength: 0)
                stateIcon
            }
            .padding(.vertical, DS.Space.s3)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Marcar como visto", systemImage: "checkmark.circle", action: markWatched)
            Button("Descargar", systemImage: "arrow.down.circle", action: download)
            Button("Elegir fuente", systemImage: "list.bullet", action: chooseSource)
        }
    }

    @ViewBuilder private var status: some View {
        if row.watched { Text("Visto") }
        else if row.leftMinutes > 0 { Text(timeLeftText(minutes: row.leftMinutes)) }
        else if row.download == .done { Text("Descargado") }
        else { Text("") }
    }

    @ViewBuilder private var stateIcon: some View {
        if row.watched { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.good) }
        else if row.download == .done { Image(systemName: "arrow.down.circle.fill").foregroundStyle(DS.good) }
        else if row.download == .downloading || row.download == .queued { ProgressView() }
        else { Button(action: download) { Image(systemName: "arrow.down.circle").foregroundStyle(DS.textMuted) }.accessibilityLabel(Text("Descargar")) }
    }
}
