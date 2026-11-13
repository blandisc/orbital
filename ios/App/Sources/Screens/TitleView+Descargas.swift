import SwiftUI
import OrbitalCore
import OrbitalModels

/// El mosaico «Descargar» de la ficha. F1 (Fernando, 12 nov 2026: «integrar los dos botones que están abajo, los de descargar y
/// vista, a estos tres de ahí arriba»): en una serie, tocarlo pregunta qué con el menú del sistema (este episodio, los siguientes,
/// la temporada con su peso o toda la serie); antes eran la hoja «¿Qué descargo?» (DS1) y el círculo de la temporada (ET1/DP2).
/// En una película, un toque baja la recomendada, como siempre.
extension TitleView {
    /// Descargar: un toque baja la recomendada y el círculo se vuelve el anillo de su avance; tocar el anillo da sus opciones.
    @ViewBuilder func downloadAction(_ model: TitleModel) -> some View {
        let target = model.downloadTarget
        let fraction = model.downloadFraction(target)
        let series = model.kind == "series"
        Group {
            switch model.downloadState(target) {
            case .downloading?, .queued?:
                Menu {
                    if let fraction { Text("Lleva \(Int(fraction * 100)) %") }
                    Button("Pausar", systemImage: "pause.fill") { if let target { Task { await model.pauseDownload(target) } } }
                    Button("Ver en Descargas", systemImage: "arrow.down.circle") { env.openTab = AppEnvironment.downloadsTab }
                    Button("Cancelar la descarga", systemImage: "xmark", role: .destructive) { if let target { Task { await model.cancelDownload(target) } } }
                    if series { Section { seriesDownloads(model, episode: false) } }
                } label: {
                    ActionTileLabel(title: fraction.map { Text(verbatim: "\(Int($0 * 100)) %") } ?? Text("En espera"), symbol: "pause.fill", active: true, progress: fraction ?? 0, tint: artAccent)
                }
            case .paused?, .failed?:
                let failed = model.downloadState(target) == .failed
                Menu {
                    Button("Ver en Descargas", systemImage: "arrow.down.circle") { env.openTab = AppEnvironment.downloadsTab }
                    Button("Cancelar la descarga", systemImage: "xmark", role: .destructive) { if let target { Task { await model.cancelDownload(target) } } }
                    if series { Section { seriesDownloads(model, episode: false) } }
                } label: {
                    ActionTileLabel(title: failed ? Text("Reintentar") : Text("En pausa"), symbol: failed ? "arrow.clockwise" : "play.fill", active: true, progress: fraction, tint: failed ? DS.warning : artAccent)
                } primaryAction: {
                    if let target { Task { await model.resumeDownload(target) } }
                }
            case .done?:
                Menu {
                    Button("Ver sin internet", systemImage: "play.fill") { start(model, videoID: target) }
                    Button("Ver en Descargas", systemImage: "arrow.down.circle") { env.openTab = AppEnvironment.downloadsTab }
                    Button("Borrar la descarga", systemImage: "trash", role: .destructive) { if let target { Task { await model.cancelDownload(target) } } }
                    if series { Section { seriesDownloads(model, episode: false) } }
                } label: {
                    // DB1: «Lista» o, en una serie, «Listos» con cuántos episodios tienes (antes «Descargada» se cortaba).
                    ActionTileLabel(title: series ? Text("Listos") : Text("Lista"), symbol: "checkmark.circle.fill", active: true, tint: artAccent,
                                    badge: series ? model.downloadedCount : nil)
                }
            default:
                let label = ActionTileLabel(title: Text("Descargar"), symbol: DS.Symbol.download, tint: artAccent, badge: series ? model.downloadedCount : nil)
                if series {
                    // Una serie pregunta qué, con su peso; «Elegir versión…» aparte, abajo.
                    Menu {
                        Section { seriesDownloads(model, episode: true) }
                        Section { chooseVersion(model, target) }
                    } label: { label }
                } else {
                    Menu { chooseVersion(model, target) } label: { label } primaryAction: { Task { await downloadRecommended(model) } }
                }
            }
        }
        .menuStyle(.button).buttonStyle(.plain)
        .disabled(target == nil || (model.debridOffer != nil && model.recommendedSource?.instant != true))   // IOS-17, R2-A: con «Pedirlo y avisarme», apagado
        .accessibilityIdentifier("title-download")
    }

    private func chooseVersion(_ model: TitleModel, _ target: String?) -> some View {
        Button("Elegir versión…", systemImage: "list.bullet.rectangle") { if let target { sourcesFor = SourcesTarget(videoID: target, purpose: .download) } }
    }

    /// Lo que se puede bajar de una serie: el episodio que toca (si `episode`), los siguientes, la temporada elegida y toda la
    /// serie, cada uno con lo que pesa lo que falta (y si no cabe). Lo que ya está entero en el iPhone sale apagado.
    @ViewBuilder func seriesDownloads(_ model: TitleModel, episode: Bool) -> some View {
        let next = model.nextEpisodeIDs(DS.Size.downloadNext)
        let season = model.selectedSeason, inSeason = model.seasonEpisodeIDs(season)
        let seasonMissing = model.notDownloaded(inSeason), all = model.allEpisodeIDs, allMissing = model.notDownloaded(all)
        let free = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        let size = { (what: Text, bytes: Int64?) in Self.size(what, bytes: bytes, free: free, locale: env.uiLocale) }
        if episode, let target = model.downloadTarget {
            Button { Task { await downloadRecommended(model) } } label: {
                Text("Este episodio")
                size(Text(verbatim: model.episodeLabel(target) ?? ""), model.estimatedBytes(episodes: 1))
                Image(systemName: DS.Symbol.download)
            }
            .accessibilityIdentifier("download-episode")
        }
        if episode, next.count > 1 {
            let missing = model.notDownloaded(next)
            Button { Task { await report(model.download(next), model) } } label: {
                Text("Los siguientes \(next.count)")
                size(Text(verbatim: [next.first, next.last].compactMap { $0.flatMap(model.episodeLabel) }.joined(separator: " – ")), model.estimatedBytes(episodes: missing.count))
                Image(systemName: "square.stack.3d.down.right")
            }
            .disabled(missing.isEmpty)
            .accessibilityIdentifier("download-next")
        }
        if inSeason.count > 1 {
            Button { Task { await report(model.download(seasonMissing), model) } } label: {
                Text("Temporada \(season)")
                seasonMissing.isEmpty ? Text("En el iPhone") : size(Text("faltan \(seasonMissing.count)"), model.estimatedBytes(episodes: seasonMissing.count))
                Image(systemName: "rectangle.stack")
            }
            .disabled(seasonMissing.isEmpty)
            .accessibilityIdentifier("download-season")
        }
        if model.seasons.filter({ !$0.isSpecials }).count > 1 {
            Button { Task { await report(model.download(allMissing), model) } } label: {
                Text("Toda la serie")
                allMissing.isEmpty ? Text("En el iPhone") : size(Text("faltan \(allMissing.count)"), model.estimatedBytes(episodes: allMissing.count))
                Image(systemName: DS.Symbol.wholeSeries)
            }
            .disabled(allMissing.isEmpty)
            .accessibilityIdentifier("download-series")
        }
    }

    /// «T2 E5 · 1,2 GB» o, si no cabe en lo libre del iPhone, «… · no cabe en tu iPhone» (lo que decía «¿Qué descargo?»).
    private static func size(_ what: Text, bytes: Int64?, free: Int64?, locale: Locale) -> Text {
        guard let bytes else { return what }
        let weight = Text(verbatim: ByteSize.text(bytes, locale: locale))
        if let free, bytes > free { return Text("\(what) · \(weight) · no cabe en tu iPhone") }
        return Text("\(what) · \(weight)")
    }
}
