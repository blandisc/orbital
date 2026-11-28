import Foundation
import OrbitalCore

extension TitleModel {
    /// Cómo vas con este título (G1-A). `dropped`: la serie está escondida (lo sabe `FollowModel`).
    public func status(dropped: Bool, now: Date = Date()) -> TitleStatus {
        let series = kind == "series"
        let released = series ? videos(in: .series, now: now) : [metaID]
        let upcoming = series && seasons.filter { !$0.isSpecials }.flatMap(\.episodes)
            .contains { ($0.released.flatMap(Self.day) ?? .distantPast) > now }
        // Solo los episodios estrenados de la serie (sin especiales): 3 especiales vistos ya no completan una que va en 7 de 10.
        var seen = series ? released.filter { watched.contains($0) }.count : (watched.contains(metaID) ? 1 : 0)
        // Una serie que vas a medias o que ya pasó del primer episodio también la estás viendo, aunque aún no llegue lo visto.
        let first = seasons.first { !$0.isSpecials }?.episodes.first?.id
        if series, seen == 0, resumeFraction != nil || (continueVideoID != nil && continueVideoID != first) { seen = 1 }
        return .decide(isSeries: series, inList: inLibrary, watchedCount: seen, releasedCount: released.count, upcoming: upcoming, dropped: dropped)
    }

    /// «La dejé» en una película: sale de Mi lista y de Seguir viendo (Trakt no guarda películas dejadas).
    public func dropMovie() async {
        if inLibrary { await toggleLibrary() }
        await services.watch.dismissContinue(metaID: metaID)
    }
    /// «Deshacer» de «La dejé» en una película: vuelve a «Seguir viendo» (y a Mi lista, si estaba).
    public func undoDropMovie(wasInList: Bool) async {
        await services.watch.restoreContinue(metaID: metaID)
        if wasInList, !inLibrary { await toggleLibrary() }
    }
}
