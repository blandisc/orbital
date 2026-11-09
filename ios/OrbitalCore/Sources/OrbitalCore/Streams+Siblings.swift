import Foundation

extension Streams {
    /// Otra serie con casi el mismo nombre (Fernando, 8 nov: «Star Wars: Clone Wars» de 2003 bajaba «Star.Wars.The.Clone.Wars»
    /// de 2008, que Comet le daba por el nombre). El nombre de la serie en el archivo (lo de antes de «S01E01») es uno de sus
    /// títulos pero con un artículo de más («The», «El», «La»…): es la otra. Igual o sin artículo, es esta.
    static let articles: Set<String> = ["the", "a", "an", "el", "la", "los", "las", "le", "les", "il", "der", "die", "das"]
    /// Donde acaba el nombre de la serie: «S01E01», pero también un paquete («S01-S07», «Season 1», «Complete»), el año o la
    /// calidad (Fernando, 8 nov: «Star.Wars.The.Clone.Wars.S01-S07.1080p» no traía «S01E01» y se colaba).
    static let seriesEpisodeMark = r(#"(?i)[ ._\-\[(](?:s\d{1,2}(?:[ ._]?e\d{1,3})?|seasons?|temporadas?|complete|completa|\d{3,4}p|(?:19|20)\d{2})(?=[ ._\-\])]|$)"#)
    public static func namesAnotherSeries(_ titles: [String], _ release: String) -> Bool {
        let clean = release.replacingOccurrences(of: "📄", with: "")
        guard let mark = seriesEpisodeMark.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
              let cut = Range(mark.range, in: clean) else { return false }
        let show = plain(String(clean[..<cut.lowerBound])).split(separator: " ").map(String.init).filter { Int($0) == nil }
        guard !show.isEmpty else { return false }
        for title in titles {
            let words = plain(title).split(separator: " ").map(String.init)
            if words == show { return false }
            let extra = show.filter { !words.contains($0) }
            if !extra.isEmpty, extra.allSatisfy(articles.contains), show.filter({ !articles.contains($0) }) == words.filter({ !articles.contains($0) }) {
                return true
            }
        }
        return false
    }
}
