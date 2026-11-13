import Foundation
import OrbitalAddons

/// T9 · «Probar con un título»: con tus opciones de Torrentio, cuántas versiones daría un título de prueba, y si no daría
/// ninguna, el arreglo de un toque. Se hace sola cada vez que cambias algo en Ajustes › Complementos › Torrentio.
public enum TorrentioProbe {
    /// El título con que se prueba: un episodio que todos los sitios tienen.
    public static let sample = (kind: "series", videoID: "tt0386676:1:1", name: "The Office · T1 E1")

    public enum Fix: Equatable, Hashable, Sendable {
        /// «Volver a mostrar 1080p»: quitar esa calidad de las que escondes.
        case showQuality(String)
        /// «Ver también lo que se puede pedir»: apagar «Solo lo que ya está en Real-Debrid».
        case allowRequests
        /// «Volver a lo recomendado».
        case recommended
    }

    public enum Verdict: Equatable, Sendable {
        /// Lo que daría: al instante, para pedir y sin Real-Debrid (sin tu clave no se sabe cuáles arrancan).
        case found(instant: Int, toRequest: Int, other: Int)
        /// Con tus filtros no quedaría nada, y sin ellos sí: los arreglos, el más útil primero.
        case nothing(fixes: [Fix])
        /// Ni con lo recomendado hay: el problema no son tus filtros (o el título hoy no tiene).
        case titleHasNothing
    }

    /// Cuenta las versiones de una respuesta de Torrentio (los avisos de «RD error» o «descargando» no son versiones).
    public static func count(_ streams: [JSON]) -> (instant: Int, toRequest: Int, other: Int) {
        var out = (instant: 0, toRequest: 0, other: 0)
        for stream in streams where stream.object != nil {
            let name = stream["name"]?.string ?? ""
            if TorrentioNotices.notice(name: name, url: stream["url"]?.string.flatMap(URL.init(string:))) != nil { continue }
            let mark = Streams.instantMark(name: name, addon: "Torrentio", transportURL: AddonCatalog.torrentioBase)
            if mark.cached { out.instant += 1 } else if mark.debrid { out.toRequest += 1 } else { out.other += 1 }
        }
        return out
    }

    /// El veredicto: `streams` con tus opciones; `recommendedCount`, cuántas daría con lo recomendado (solo se pregunta si
    /// con las tuyas no hay nada).
    public static func verdict(streams: [JSON], options: AddonOptions, recommendedCount: Int?) -> Verdict {
        let found = count(streams)
        if found.instant + found.toRequest + found.other > 0 { return .found(instant: found.instant, toRequest: found.toRequest, other: found.other) }
        if let recommendedCount, recommendedCount == 0 { return .titleHasNothing }
        return .nothing(fixes: fixes(for: options))
    }

    /// Lo que más destapa primero: dejar ver lo que se puede pedir, luego la calidad más común que escondiste.
    public static func fixes(for options: AddonOptions) -> [Fix] {
        var out: [Fix] = []
        if options.debridOptions.contains("nodownloadlinks") { out.append(.allowRequests) }
        if let quality = ["1080p", "720p", "4k", "480p"].first(where: options.excludedQualities.contains) { out.append(.showQuality(quality)) }
        if options != recommended(keeping: options) { out.append(.recommended) }
        return out
    }

    /// Aplica un arreglo a tus opciones.
    public static func apply(_ fix: Fix, to options: AddonOptions) -> AddonOptions {
        var next = options
        switch fix {
        case .showQuality(let quality): next.excludedQualities.removeAll { $0 == quality }
        case .allowRequests: next.debridOptions.removeAll { $0 == "nodownloadlinks" }
        case .recommended: next = recommended(keeping: options)
        }
        return next
    }

    /// «Volver a lo recomendado» (T11): todo como viene, salvo lo que la app no conoce de tu Torrentio (no se ve ni se
    /// podría volver a poner) y «sin catálogo», que no tiene pantalla.
    public static func recommended(keeping options: AddonOptions) -> AddonOptions {
        var next = TorrentioConfig.recommended
        next.verbatim = options.verbatim
        next.debridOptions = options.debridOptions.filter { $0 == "nocatalog" }
        return next
    }

    /// La dirección para pedir las versiones del título de prueba (sin `/manifest.json`). Sin clave, la de Torrentio sin
    /// Real-Debrid: dice qué existe, no qué arranca.
    public static func streamURL(options: AddonOptions, token: String?) -> URL? {
        let base: String
        if let manifest = TorrentioConfig.manifestURL(options: options, token: token) { base = String(manifest.dropLast("/manifest.json".count)) }
        else {
            let parts = TorrentioConfig.parts(options).filter { !$0.hasPrefix("debridoptions=") }
            base = parts.isEmpty ? AddonCatalog.torrentioBase : "\(AddonCatalog.torrentioBase)/\(parts.joined(separator: "|"))"
        }
        return addonURL("\(base)/stream/\(sample.kind)/\(uriComponent(sample.videoID)).json")
    }
}
