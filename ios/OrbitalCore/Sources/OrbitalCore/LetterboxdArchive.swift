import Foundation
#if canImport(Compression)
import Compression
#endif

/// El archivo de exportación de Letterboxd (letterboxd.com › Settings › Data › Export): un .zip con tu diario, tus
/// calificaciones, tus reseñas, lo visto, tu watchlist y tus listas, en CSV. Se lee una vez y queda en el iPhone. También
/// se aceptan los CSV sueltos (si el .zip ya se abrió en Archivos).
public struct LetterboxdArchive: Sendable, Equatable {
    /// Todo lo que viste o calificaste (lo del diario con su fecha; lo demás, sin fecha).
    public var entries: [LetterboxdEntry] = []
    public var watchlist: [LetterboxdFilm] = []
    /// Tus listas, también las privadas, con sus películas.
    public var lists: [(list: LetterboxdList, films: [LetterboxdFilm])] = []

    public init() {}

    public static func == (a: Self, b: Self) -> Bool {
        a.entries == b.entries && a.watchlist == b.watchlist && a.lists.map(\.list) == b.lists.map(\.list) && a.lists.map(\.films) == b.lists.map(\.films)
    }

    public enum Failure: Error, Sendable, CustomStringConvertible {
        case notAnExport
        public var description: String { "Ese archivo no es una exportación de Letterboxd" }
    }

    /// Un .zip de Letterboxd o sus CSV sueltos (nombre → contenido).
    public static func read(files: [(name: String, data: Data)]) throws -> LetterboxdArchive {
        var csv: [String: String] = [:]
        for file in files {
            if file.name.lowercased().hasSuffix(".zip") {
                for (name, data) in try Zip.entries(file.data) where name.lowercased().hasSuffix(".csv") { csv[name] = String(decoding: data, as: UTF8.self) }
            } else if file.name.lowercased().hasSuffix(".csv") {
                csv[file.name] = String(decoding: file.data, as: UTF8.self)
            }
        }
        let found = parse(csv)
        guard !found.entries.isEmpty || !found.watchlist.isEmpty || !found.lists.isEmpty else { throw Failure.notAnExport }
        return found
    }

    /// Los CSV por su nombre dentro del archivo («diary.csv», «lists/mi-lista.csv»…).
    static func parse(_ csv: [String: String]) -> LetterboxdArchive {
        func file(_ name: String) -> [[String: String]] {
            guard let text = csv.first(where: { ($0.key as NSString).lastPathComponent.lowercased() == name && !$0.key.contains("deleted/") })?.value else { return [] }
            return CSV.records(text)
        }
        var out = LetterboxdArchive()
        var byKey: [String: LetterboxdEntry] = [:], order: [String] = []
        func upsert(_ row: [String: String], _ apply: (inout LetterboxdEntry) -> Void) {
            guard let title = row["Name"], !title.isEmpty else { return }
            let year = row["Year"].flatMap { Int($0) }
            let watched = (row["Watched Date"]?.isEmpty == false ? row["Watched Date"] : nil).flatMap(LetterboxdEntry.day)
            // Una por película y día (el diario y sus reseñas se juntan); sin fecha, una por película.
            let key = "\(title.lowercased())|\(year ?? 0)|\(watched.map { Int($0.timeIntervalSince1970 / 86400) } ?? -1)"
            var entry = byKey[key] ?? LetterboxdEntry(title: title, year: year)
            if byKey[key] == nil { entry.id = "archive|\(key)"; entry.watched = watched; order.append(key) }
            apply(&entry)
            byKey[key] = entry
        }
        for row in file("diary.csv") {
            upsert(row) { e in
                if let r = row["Rating"].flatMap(Double.init) { e.rating = r }
                e.rewatch = row["Rewatch"] == "Yes"
            }
        }
        for row in file("reviews.csv") {
            upsert(row) { e in
                if let r = row["Rating"].flatMap(Double.init) { e.rating = r }
                if let text = row["Review"]?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { e.review = text }
            }
        }
        // Calificadas o vistas sin entrada en el diario: una entrada sin fecha (si ya hay una con fecha, se le pone la estrella).
        let dated = Set(byKey.values.map { "\($0.title.lowercased())|\($0.year ?? 0)" })
        for row in file("ratings.csv") {
            let k = "\((row["Name"] ?? "").lowercased())|\(row["Year"].flatMap { Int($0) } ?? 0)"
            if dated.contains(k) {
                for (key, e) in byKey where "\(e.title.lowercased())|\(e.year ?? 0)" == k && e.rating == nil { byKey[key]?.rating = row["Rating"].flatMap(Double.init) }
            } else { upsert(row) { e in e.rating = row["Rating"].flatMap(Double.init) } }
        }
        let rated = Set(byKey.values.map { "\($0.title.lowercased())|\($0.year ?? 0)" })
        for row in file("watched.csv") where !rated.contains("\((row["Name"] ?? "").lowercased())|\(row["Year"].flatMap { Int($0) } ?? 0)") {
            upsert(row) { _ in }
        }
        let liked = Set(file("films.csv").map { "\(($0["Name"] ?? "").lowercased())|\($0["Year"].flatMap { Int($0) } ?? 0)" })
        for key in byKey.keys where liked.contains("\(byKey[key]!.title.lowercased())|\(byKey[key]!.year ?? 0)") { byKey[key]?.liked = true }
        // Lo más reciente primero (sin fecha, al final).
        out.entries = order.compactMap { byKey[$0] }.sorted { ($0.watched ?? .distantPast) > ($1.watched ?? .distantPast) }
        out.watchlist = file("watchlist.csv").compactMap(film)
        for (name, text) in csv where name.lowercased().contains("lists/") && !name.contains("deleted/") {
            if let list = Self.list(text, file: (name as NSString).lastPathComponent) { out.lists.append(list) }
        }
        out.lists.sort { $0.list.name.localizedStandardCompare($1.list.name) == .orderedAscending }
        return out
    }

    /// Una película de un CSV: su nombre en Letterboxd sale de su dirección («…/film/dune-part-two/»), si la trae.
    static func film(_ row: [String: String]) -> LetterboxdFilm? {
        guard let title = row["Name"], !title.isEmpty else { return nil }
        let url = row["URL"] ?? row["Letterboxd URI"] ?? ""
        let slug = url.range(of: #"/film/[^/]+"#, options: .regularExpression).map { String(url[$0].dropFirst("/film/".count)) } ?? ""
        return LetterboxdFilm(slug: slug, title: title, year: row["Year"].flatMap { Int($0) })
    }

    /// Una lista exportada: unos renglones con su nombre y, tras un renglón vacío, sus películas.
    static func list(_ text: String, file: String) -> (list: LetterboxdList, films: [LetterboxdFilm])? {
        let parts = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        guard parts.count >= 2 else { return nil }
        let head = CSV.records(parts[0].components(separatedBy: "\n").drop { !$0.hasPrefix("Date,") }.joined(separator: "\n")).first
        let films = CSV.records(parts[1...].joined(separator: "\n\n")).compactMap(film)
        let url = head?["URL"] ?? ""
        let slug = url.range(of: #"/list/[^/]+"#, options: .regularExpression).map { String(url[$0].dropFirst("/list/".count)) } ?? (file as NSString).deletingPathExtension
        guard let name = head?["Name"], !name.isEmpty else { return nil }
        return (LetterboxdList(slug: slug, name: name, count: films.count), films)
    }
}

/// CSV con comillas (comas y saltos de línea dentro de un campo, «""» es una comilla).
enum CSV {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character?
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let next = chars.next() { if next == "\"" { field.append("\"") } else { quoted = false; pending = next } } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" { row.append(field); rows.append(row); row = []; field = "" }
            else { field.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }

    /// Con el primer renglón como nombres de columna.
    static func records(_ text: String) -> [[String: String]] {
        let all = rows(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = all.first else { return [] }
        return all.dropFirst().map { values in
            Dictionary(uniqueKeysWithValues: header.enumerated().map { ($0.element, $0.offset < values.count ? values[$0.offset] : "") })
        }
    }
}

/// Lo mínimo para leer un .zip: su índice del final y cada archivo guardado tal cual o comprimido (deflate).
enum Zip {
    struct Failure: Error {}

    static func entries(_ data: Data) throws -> [(String, Data)] {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { i + 1 < bytes.count ? Int(bytes[i]) | Int(bytes[i + 1]) << 8 : 0 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        // El final del índice: la firma 0x06054b50, buscando desde atrás.
        guard bytes.count > 22, let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1).first(where: { u32($0) == 0x0605_4B50 })
        else { throw LetterboxdArchive.Failure.notAnExport }
        var p = u32(end + 16), out: [(String, Data)] = []
        for _ in 0..<u16(end + 10) {
            guard u32(p) == 0x0201_4B50 else { break }
            let method = u16(p + 10), compressed = u32(p + 20), size = u32(p + 24)
            let nameLength = u16(p + 28), extra = u16(p + 30), comment = u16(p + 32), local = u32(p + 42)
            let name = String(decoding: bytes[(p + 46)..<min(bytes.count, p + 46 + nameLength)], as: UTF8.self)
            p += 46 + nameLength + extra + comment
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count, !name.hasSuffix("/") else { continue }
            let raw = Data(bytes[start..<(start + compressed)])
            if method == 0 { out.append((name, raw)) }
            else if method == 8, let inflated = inflate(raw, size: size) { out.append((name, inflated)) }
        }
        return out
    }

    static func inflate(_ data: Data, size: Int) -> Data? {
        #if canImport(Compression)
        guard size > 0 else { return Data() }
        var out = Data(count: size)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, size, src.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return written == size ? out : nil
        #else
        return nil
        #endif
    }
}
