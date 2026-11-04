import Foundation

extension Streams {
    /// «¿Otro episodio?»: Torrentio a veces pone en un episodio el archivo de otra temporada («Breaking Bad T4 720p Dual
    /// Latino-Ingles · 04 - CAPITULO 01» en T1 E1). Baja como «¿Otro título?»: nunca la recomendada ni la ofrecida (análisis
    /// de fondo con la TV, 3 nov). Solo con temporada (los de Kitsu van de corrido).
    public static let otherEpisodeTag = "¿Otro episodio?"
    static let episodeMark = r(#"\bs(\d{1,2})[ ._-]?e\d{1,3}\b|\b(\d{1,2})x\d{2,3}\b"#)
    static let seasonWord = r(#"\b(?:s|season|temporada|saison|stagione|staffel|sezon)[ ._-]?(\d{1,2})\b"#)
    static let seasonLetter = r(#"\bT(\d{1,2})\b"#, caseInsensitive: false)   // «T4» (temporada), solo en mayúscula
    static let seasonRange = r(#"\bs\d{1,2}[ ._]*(?:-|~|a|to)[ ._]*s?\d{1,2}\b|\b(?:seasons?|temporadas?)[ ._]*\d{1,2}[ ._]*(?:-|~|a|to|&|y)[ ._]*\d{1,2}\b|\bt\d{1,2}[ ._]*-[ ._]*t?\d{1,2}\b"#)

    /// La temporada de un video de serie de IMDb («tt0903747:1:2» → 1); nil si no es de ese tipo.
    public static func season(of videoID: String) -> Int? {
        let parts = videoID.split(separator: ":")
        guard parts.count == 3, parts[0].hasPrefix("tt") else { return nil }
        return Int(parts[1])
    }

    /// El archivo o el nombre dicen otra temporada (y ninguno dice esta).
    static func otherEpisode(release: String, filename: String, season: Int) -> Bool {
        func seasons(_ regex: NSRegularExpression, _ text: String) -> [Int] {
            regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
                (1..<m.numberOfRanges).lazy.compactMap { Range(m.range(at: $0), in: text).flatMap { Int(text[$0]) } }.first
            }
        }
        for text in [filename, release] {
            let marked = seasons(episodeMark, text)
            if !marked.isEmpty { return !marked.contains(season) }
        }
        if matches(seasonRange, release) { return false }
        let named = seasons(seasonWord, release) + seasons(seasonLetter, release)
        return !named.isEmpty && !named.contains(season)
    }

    /// Le pone «¿Otro episodio?» a una versión de serie que trae otra temporada.
    public static func markOtherEpisode(_ source: inout Source, videoID: String, filename: String) {
        guard let season = season(of: videoID), otherEpisode(release: source.release, filename: filename, season: season),
              !source.tags.contains(otherEpisodeTag) else { return }
        source.tags.append(otherEpisodeTag)
    }
}
