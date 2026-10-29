import Foundation
import OrbitalCore

/// «Un Simpson al azar»: elige un episodio de las temporadas de Ajustes (por omisión, las clásicas T5–T15), arma la tira de
/// la ruleta y tiene uno listo de antemano para que la tele no espere a la red. Sin interfaz: la ruleta (`SimpsonsRoulette`)
/// y Ajustes lo usan; se prueba con un Cinemeta fingido.
@MainActor
public final class SimpsonsModel: ObservableModel {
    /// Los episodios (para la ruleta) y el elegido (el último de la tira).
    public struct Draw: Equatable {
        public var meta: JSON
        public var name: String
        public var reel: [(season: Int, episode: Episode)]
        public var chosen: (season: Int, episode: Episode) { reel[reel.count - 1] }
        public static func == (a: Draw, b: Draw) -> Bool { a.reel.map(\.episode.id) == b.reel.map(\.episode.id) }
    }

    public static let seriesID = "tt0096697"
    /// Las clásicas: el valor por omisión de «Un Simpson al azar».
    public static let classics = Array(5...15)
    /// Hasta qué temporada se ofrece en Ajustes si Cinemeta no contesta.
    public static let knownSeasons = 37
    /// Cuánto espera, tras entregar el listo, para preparar el siguiente (no mientras la tele se anima).
    public static let refillDelay: Double = 15
    /// La imagen de un episodio (metahub).
    public static func still(season: Int, episode: Int) -> String { "https://episodes.metahub.space/\(seriesID)/\(season)/\(episode)/w780.jpg" }

    private let services: Services
    /// Cuántos canales enseña la ruleta antes del elegido (un token de la interfaz).
    public let reelLength: Int
    /// Baja a la caché las imágenes de la tira (la app pone `ImagePipeline`).
    public var warmImages: ([String]) async -> Void = { _ in }
    /// Qué decir cuando Cinemeta no contesta (texto y detalle en español; la app los traduce).
    public var onError: (_ text: String, _ detail: String) -> Void = { _, _ in }
    private var next: Draw?
    /// Cuántas veces hubo uno listo al pedirlo (para las pruebas y la bitácora).
    public private(set) var servedFromPrefetch = 0

    public init(_ services: Services, reelLength: Int) {
        self.services = services
        self.reelLength = reelLength
        super.init()
    }

    /// Elige uno y arma la tira de la ruleta (otros al azar y, al final, el elegido). nil si Cinemeta no contesta.
    public func draw(quiet: Bool = false) async -> Draw? {
        guard let meta = try? await services.cinemeta.meta(kind: "series", id: Self.seriesID, persist: true) else { return failed(quiet) }
        // Leer ~700 episodios cuesta: fuera del hilo principal (si no, la animación de la tele se trababa).
        let seasons = Set(services.appSettings.simpsonsSeasons)
        let pool = await Task.detached(priority: .userInitiated) { Self.pool(meta, seasons: seasons) }.value
        guard pool.count > 1, let chosen = pool.randomElement() else { return failed(quiet) }
        let others = (0..<max(0, reelLength - 1)).compactMap { _ in pool.randomElement() }
        return Draw(meta: meta, name: meta["name"]?.string ?? "The Simpsons", reel: others + [chosen])
    }

    /// Los episodios de las temporadas elegidas; si ninguna existe todavía (o no eligió ninguna), de todas.
    nonisolated static func pool(_ meta: JSON, seasons: Set<Int>) -> [(season: Int, episode: Episode)] {
        let all = CinemetaParsing.seasons(meta).filter { $0.season > 0 }
        let picked = all.filter { seasons.contains($0.season) }
        return (picked.isEmpty ? all : picked).flatMap { season in season.episodes.map { (season: season.season, episode: $0) } }
    }

    private func failed(_ quiet: Bool) -> Draw? {
        if !quiet { onError("No pude traer los episodios de Los Simpson", "Revisa tu internet") }
        return nil
    }

    /// La lista de episodios, pedida antes de que toques la dona, y el siguiente ya elegido con sus imágenes en caché:
    /// al tocar la dona, la tele tiene todo listo.
    public func prefetch() async {
        guard next == nil, let draw = await draw(quiet: true) else { return }
        await warmImages(draw.reel.map { Self.still(season: $0.season, episode: $0.episode.episode) })
        next = draw
    }

    /// El que ya estaba listo (y se prepara el siguiente), o uno nuevo.
    public func take() async -> Draw? {
        if let ready = next {
            next = nil
            servedFromPrefetch += 1
            Task { try? await Task.sleep(nanoseconds: UInt64(Self.refillDelay * 1_000_000_000)); await prefetch() }
            return ready
        }
        return await draw()
    }

    /// Lo que se reproduce del elegido: en el iPhone, desde el principio y de pie (sale de la tele vertical, sin girar).
    public func request(_ draw: Draw) -> PlayRequest {
        let (season, episode) = draw.chosen
        let label = services.episodeLabel(season, episode.episode) + (episode.hasTitle ? " · \(episode.title)" : "")
        var request = PlayRequest(kind: "series", metaID: Self.seriesID, videoID: episode.id, originalTitle: draw.name, displayTitle: draw.name, episodeLabel: label,
                                  poster: String(format: ForYou.metahubPoster, Self.seriesID), meta: draw.meta, fromStart: true)
        request.startPortrait = true
        return request
    }

    /// Las temporadas que existen (para Ajustes), de lo que Cinemeta ya tiene guardado; si no contesta, 1 a `knownSeasons`.
    public func seasonNumbers() async -> [Int] {
        guard let meta = try? await services.cinemeta.meta(kind: "series", id: Self.seriesID, persist: true) else { return Array(1...Self.knownSeasons) }
        let found = await Task.detached(priority: .userInitiated) { CinemetaParsing.seasons(meta).map(\.season).filter { $0 > 0 } }.value
        return found.isEmpty ? Array(1...Self.knownSeasons) : found.sorted()
    }

    /// Cambiaron las temporadas en Ajustes: el que ya estaba listo se descarta (podía ser de otra temporada).
    public func seasonsChanged() { next = nil }
}
