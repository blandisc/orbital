import Foundation

/// Leer y escribir lo tuyo en JSON sin tragarse los errores (auditoría, 31 oct 2026, C1). Antes un archivo dañado se leía
/// como vacío y la siguiente escritura lo pisaba: se perdía la biblioteca entera sin rastro.
public enum StoredFile {
    /// nil si no existe. Si existe pero no se puede leer o no se entiende, se aparta como `<nombre>.corrupt` (para poder
    /// rescatarlo) y se registra; quien llama sigue con vacío.
    public static func read<T: Decodable>(_ type: T.Type, from url: URL, what: String) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        } catch {
            let aside = corruptCopy(url)
            try? FileManager.default.removeItem(at: aside)
            let moved = (try? FileManager.default.moveItem(at: url, to: aside)) != nil
            Log.storage.error("No se pudo leer \(what, privacy: .public) (\(url.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public). Apartado: \(moved)")
            return nil
        }
    }

    public static func write<T: Encodable>(_ value: T, to url: URL, what: String) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            Log.storage.error("No se pudo guardar \(what, privacy: .public) (\(url.lastPathComponent, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Dónde queda la copia apartada de un archivo dañado.
    public static func corruptCopy(_ url: URL) -> URL { url.appendingPathExtension("corrupt") }
}
