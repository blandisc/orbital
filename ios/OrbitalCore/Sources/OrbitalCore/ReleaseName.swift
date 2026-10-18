import Foundation

/// Lo que dice el nombre de un archivo de video («Dune.Part.Two.2024.2160p.WEB-DL.mkv», «The.Office.S02E05.720p.mkv»):
/// el nombre, el año y, en una serie, temporada y episodio. Para reconocer una película que te pasaron (AirDrop, Archivos).
public struct ReleaseName: Sendable, Equatable {
    public var title: String
    public var year: Int?
    public var season: Int?
    public var episode: Int?
    public var isSeries: Bool { season != nil && episode != nil }

    public static func parse(_ filename: String) -> ReleaseName {
        var name = (filename as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: #"[\._]+"#, with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*(?:rip|web|bluray|1080|720|2160)[^)]*\)"#, with: " ", options: [.regularExpression, .caseInsensitive])
        let ns = name as NSString
        func first(_ pattern: String) -> NSTextCheckingResult? {
            (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.firstMatch(in: name, range: NSRange(location: 0, length: ns.length))
        }
        var cut = ns.length
        var season: Int?, episode: Int?, year: Int?
        if let m = first(#"\bS(\d{1,2})\s?E(\d{1,3})\b|\b(\d{1,2})x(\d{2})\b"#) {
            let s = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 3)
            let e = m.range(at: 2).location != NSNotFound ? m.range(at: 2) : m.range(at: 4)
            season = Int(ns.substring(with: s)); episode = Int(ns.substring(with: e))
            cut = min(cut, m.range.location)
        }
        // Un año de verdad (no el «2049» de Blade Runner): hasta el que viene.
        let thisYear = Calendar.current.component(.year, from: Date())
        if let m = first(#"[\s(\[](19\d{2}|20\d{2})(?=[\s)\]]|$)"#), let y = Int(ns.substring(with: m.range(at: 1))), y <= thisYear + 1 {
            year = y
            cut = min(cut, m.range.location)
        }
        if let m = first(#"\b(2160p|1080p|720p|480p|4k|uhd|web[- ]?dl|webrip|bluray|brrip|hdrip|dvdrip|x26[45]|hevc|remux|hdr)\b"#) {
            cut = min(cut, m.range.location)
        }
        let title = ns.substring(to: cut).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " -([")).trimmingCharacters(in: .whitespaces)
        return ReleaseName(title: title.isEmpty ? (filename as NSString).deletingPathExtension : title, year: year, season: season, episode: episode)
    }
}
