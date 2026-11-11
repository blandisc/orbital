import Foundation

/// Cómo salió leer un archivo tuyo.
public enum StoredRead<T> {
    /// No existe (la primera vez): se empieza vacío.
    case missing
    case loaded(T)
    /// Existe pero no se pudo leer (pasajero: el iPhone bloqueado con el archivo protegido, el disco ocupado). El archivo se
    /// deja tal cual y quien llama NO debe escribir encima hasta poder leerlo.
    case unreadable
    /// Se leyó pero no se entiende (formato roto): ya quedó apartado con fecha; se sigue con vacío.
    case corrupt

    public var value: T? { if case .loaded(let value) = self { return value }; return nil }
}

/// Leer y escribir lo tuyo en JSON sin tragarse los errores (auditoría, 31 oct 2026, C1). Antes un archivo dañado se leía
/// como vacío y la siguiente escritura lo pisaba: se perdía la biblioteca entera sin rastro.
///
/// Revisión del 11 nov 2026: se aparta SOLO lo que tiene el formato roto; un tropiezo al leer (archivo protegido con el iPhone
/// bloqueado) se reintenta y nunca se aparta ni se pisa. Las copias apartadas llevan fecha y se guardan varias.
public enum StoredFile {
    /// Cuántas copias apartadas se guardan por archivo (las más nuevas).
    public static let keptAside = 5

    /// Lee con hasta `attempts` intentos si el tropiezo es al leer.
    public static func load<T: Decodable>(_ type: T.Type, from url: URL, what: String, attempts: Int = 3) -> StoredRead<T> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        var data: Data?
        var lastError: Error?
        for attempt in 0..<max(1, attempts) {
            do { data = try Data(contentsOf: url); break } catch {
                lastError = error
                if attempt < attempts - 1 { usleep(20_000) }
            }
        }
        guard let data else {
            Log.storage.error("No se pudo leer \(what, privacy: .public) (\(url.lastPathComponent, privacy: .public)): \(lastError?.localizedDescription ?? "", privacy: .public). Se deja como está y se reintenta después")
            return .unreadable
        }
        do {
            return .loaded(try JSONDecoder().decode(T.self, from: data))
        } catch {
            let aside = setAside(url)
            Log.storage.error("\(what, privacy: .public) (\(url.lastPathComponent, privacy: .public)) tiene el formato roto: \(error.localizedDescription, privacy: .public). Apartado en \(aside?.lastPathComponent ?? "ninguna parte", privacy: .public)")
            return .corrupt
        }
    }

    /// nil si no existe, no se pudo leer o no se entiende (lo dañado ya quedó apartado). Quien vaya a escribir encima usa
    /// `load` para no pisar un archivo que solo no se pudo leer ahora.
    public static func read<T: Decodable>(_ type: T.Type, from url: URL, what: String) -> T? {
        load(type, from: url, what: what).value
    }

    /// true si quedó en disco.
    @discardableResult
    public static func write<T: Encodable>(_ value: T, to url: URL, what: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            Log.storage.error("No se pudo guardar \(what, privacy: .public) (\(url.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Mueve el archivo a `<nombre>.corrupt-<fecha>` (sin pisar otra copia) y deja solo las `keptAside` más nuevas.
    @discardableResult
    static func setAside(_ url: URL) -> URL? {
        let aside = uniqueSibling(of: url, tag: "corrupt")
        guard (try? FileManager.default.moveItem(at: url, to: aside)) != nil else { return nil }
        for old in asideCopies(url).dropLast(keptAside) { try? FileManager.default.removeItem(at: old) }
        return aside
    }

    /// Guarda junto al archivo lo que no se entendió de él (un elemento de la cola mal formado), con fecha.
    @discardableResult
    static func keepRejected(_ data: Data, near url: URL, what: String) -> URL? {
        let file = uniqueSibling(of: url, tag: "rejected")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        Log.storage.error("En \(what, privacy: .public) había elementos que no se entienden: apartados en \(file.lastPathComponent, privacy: .public); lo demás sigue")
        return file
    }

    /// Las copias apartadas de un archivo dañado, de la más vieja a la más nueva.
    public static func asideCopies(_ url: URL) -> [URL] { siblings(of: url, tag: "corrupt") }

    /// Lo que se apartó de un archivo por no entenderse, de lo más viejo a lo más nuevo.
    public static func rejectedCopies(_ url: URL) -> [URL] { siblings(of: url, tag: "rejected") }

    static func siblings(of url: URL, tag: String) -> [URL] {
        let folder = url.deletingLastPathComponent(), prefix = url.lastPathComponent + ".\(tag)"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }.sorted().map { folder.appendingPathComponent($0) }
    }

    private static func uniqueSibling(of url: URL, tag: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let base = url.lastPathComponent + ".\(tag)-" + formatter.string(from: Date())
        var candidate = url.deletingLastPathComponent().appendingPathComponent(base)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent(base + "-\(n)"); n += 1
        }
        return candidate
    }
}
