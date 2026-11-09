import SwiftUI
import OrbitalCore
import OrbitalModels

/// DS1 y DP2 (Fernando, 8 nov): «¿Qué descargo?» de una serie y bajar la temporada desde su encabezado.
extension TitleView {
    func downloadChoice(_ model: TitleModel) -> some View {
        let next = model.nextEpisodeIDs(1), five = model.nextEpisodeIDs(DS.Size.downloadNext)
        let season = model.selectedSeason, inSeason = model.seasonEpisodeIDs(season)
        let seasonMissing = model.notDownloaded(inSeason), all = model.allEpisodeIDs, allMissing = model.notDownloaded(all)
        let nextLabel = next.first.flatMap { model.episodeLabel($0) } ?? ""
        var options: [DownloadChoiceSheet.Option] = [
            .init(id: "next", symbol: "play.fill", title: Text("El siguiente: \(Text(verbatim: nextLabel))"), detail: Text("Un episodio"),
                  bytes: model.estimatedBytes(episodes: 1), main: true) { Task { await downloadRecommended(model) } },
            .init(id: "five", symbol: "square.stack.3d.down.right", title: Text("Los siguientes \(five.count)"),
                  detail: Text(verbatim: [five.first, five.last].compactMap { $0.flatMap(model.episodeLabel) }.joined(separator: " – ")),
                  bytes: model.estimatedBytes(episodes: model.notDownloaded(five).count)) { Task { await report(model.download(five), model) } },
        ]
        if inSeason.count > 1 {
            options.append(.init(id: "season", symbol: "rectangle.stack", title: Text("Toda la temporada \(season)"),
                                 detail: Text("\(inSeason.count) episodios · faltan \(seasonMissing.count)"),
                                 bytes: model.estimatedBytes(episodes: seasonMissing.count)) { Task { await report(model.download(seasonMissing), model) } })
        }
        if model.seasons.filter({ !$0.isSpecials }).count > 1 {
            options.append(.init(id: "series", symbol: "square.grid.3x3", title: Text("Toda la serie"),
                                 detail: Text("\(all.count) episodios · faltan \(allMissing.count)"),
                                 bytes: model.estimatedBytes(episodes: allMissing.count)) { Task { await report(model.download(allMissing), model) } })
        }
        let quality = model.recommendedSource.map { ([$0.resolution] + $0.hdr).filter { !$0.isEmpty }.joined(separator: " · ") } ?? ""
        return DownloadChoiceSheet(subtitle: Text(verbatim: [model.title, quality].filter { !$0.isEmpty }.joined(separator: " · ")), options: options) {
            if let target = model.downloadTarget { sourcesFor = SourcesTarget(videoID: target, purpose: .download) }
        }
    }

    /// ET1: ⬇︎ bajar la temporada (con su peso; bajando, anillo con %; toda en el iPhone, lleno en verde).
    func seasonDownload(_ model: TitleModel) -> some View {
        let state = model.seasonDownload(model.selectedSeason)
        let missing = model.notDownloaded(model.seasonEpisodeIDs(model.selectedSeason))
        let caption: Text = state.ready ? Text("Lista")
            : state.fraction != nil ? Text("Bajando")
            : model.estimatedBytes(episodes: missing.count).map { Text(verbatim: ByteSize.text($0, locale: env.uiLocale)) } ?? Text("Bajar")
        return Button { Task { await report(model.download(missing), model) } } label: {
            SeasonActionButton(symbol: "arrow.down.circle", caption: caption, progress: state.ready ? nil : state.fraction,
                               done: state.ready, tint: artAccent)
        }
        .buttonStyle(.plain)
        .disabled(missing.isEmpty)
        .accessibilityLabel(state.ready ? Text("Temporada en el iPhone") : Text("Bajar la temporada"))
        .accessibilityIdentifier("season-download")
    }
}
