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

    /// DP2: «⬇︎ Temporada · 7.6 GB» junto a «Marcar como vista».
    func seasonDownload(_ model: TitleModel) -> some View {
        let ids = model.seasonEpisodeIDs(model.selectedSeason), missing = model.notDownloaded(ids)
        return SeasonDownloadButton(missing: missing.count, total: ids.count, bytes: model.estimatedBytes(episodes: missing.count), tint: artAccent) {
            Task { await report(model.download(missing), model) }
        }
    }
}
