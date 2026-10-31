import Foundation

/// Lo último que se vio (historial de Trakt, Inicio, Para ti, Buscar, los Top 10), cada clave en su archivo dentro de
/// Caches. Antes iba en UserDefaults y se codificaba en el hilo principal: UserDefaults guarda todo en un solo plist que
/// crece con cada lista y se reescribe entero (auditoría, 31 oct 2026, B3).
///
/// - Leer es inmediato (la pantalla se pinta con lo guardado en el primer cuadro): lo recién guardado sale de memoria y lo
///   demás del archivo.
/// - Guardar no espera: `set(_:encode:)` recibe cómo codificarlo y lo hace el escritor (un actor), fuera del hilo principal.
///   Si llegan varios cambios de la misma clave antes de escribir, solo se escribe el último.
/// - Migración: si una clave no tiene archivo pero sí está en el almacén viejo (`legacy`), se usa esa, se copia al archivo y
///   solo después de escribirlo se borra de UserDefaults. Así abrir la versión nueva no deja el historial vacío.
/// - Sin carpeta (`directory: nil`: pruebas y demostración sin `-demo-persist`) guarda en `legacy` tal cual.
public final class CacheStore: KeyValueStore, @unchecked Sendable {
    private enum Held { case data(Data?), pending(@Sendable () -> Data?) }

    private let directory: URL?
    private let legacy: KeyValueStore
    fileprivate let lock = NSLock()
    private var memory: [String: (generation: Int, held: Held)] = [:]
    private var generation = 0
    private let writer: CacheWriter

    public init(directory: URL?, legacy: KeyValueStore) {
        self.directory = directory
        self.legacy = legacy
        self.writer = CacheWriter(legacy: legacy)
    }

    /// El archivo de una clave («charts:netflix:series» → `charts%3Anetflix%3Aseries.json`).
    func file(_ key: String) -> URL? {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? key
        return directory?.appendingPathComponent(safe + ".json")
    }

    public func data(_ key: String) -> Data? {
        guard let file = file(key) else { return legacy.data(key) }
        if let held = lock.withLock({ memory[key]?.held }) {
            switch held {
            case .data(let data): return data
            case .pending(let encode): return encode()
            }
        }
        if let data = try? Data(contentsOf: file) { return data }
        // La versión anterior lo guardaba en UserDefaults: se usa y se pasa al archivo (se borra de allá al escribirlo).
        guard let old = legacy.data(key) else { return nil }
        enqueue(key, .data(old))
        return old
    }

    /// Guardar ya codificado (lo que ya viene en `Data`).
    public func set(_ key: String, data: Data?) {
        guard directory != nil else { return legacy.set(key, data: data) }
        enqueue(key, .data(data))
    }

    /// Guardar sin codificar en quien llama: `encode` corre en el escritor. Debe capturar solo valores (no el modelo).
    public func set(_ key: String, encode: @escaping @Sendable () -> Data?) {
        guard directory != nil else { return legacy.set(key, data: encode()) }
        enqueue(key, .pending(encode))
    }

    private func enqueue(_ key: String, _ held: Held) {
        guard let file = file(key) else { return }
        lock.withLock {
            generation += 1
            memory[key] = (generation, held)
        }
        Task { [writer] in await writer.write(key, file: file, from: self) }
    }

    /// Lo último que se pidió guardar de una clave (el escritor siempre escribe eso, aunque sus turnos lleguen desordenados).
    fileprivate func latest(_ key: String) -> (stamp: Int, encode: @Sendable () -> Data?)? {
        guard let entry = lock.withLock({ memory[key] }) else { return nil }
        switch entry.held {
        case .data(let data): return (entry.generation, { data })
        case .pending(let encode): return (entry.generation, encode)
        }
    }

    /// Ya está en el archivo: se suelta de memoria (si nadie guardó algo más nuevo mientras tanto).
    fileprivate func release(_ key: String, _ stamp: Int) {
        lock.withLock { if memory[key]?.generation == stamp { memory[key] = nil } }
    }

    /// Espera a que todo lo guardado esté en disco (pruebas).
    public func flush() async {
        while lock.withLock({ !memory.isEmpty }) {
            await writer.idle()
            await Task.yield()
        }
    }
}

/// Escribe los archivos de `CacheStore` uno tras otro, fuera del hilo principal.
actor CacheWriter {
    private let legacy: KeyValueStore
    init(legacy: KeyValueStore) { self.legacy = legacy }

    func write(_ key: String, file: URL, from store: CacheStore) {
        guard let (stamp, encode) = store.latest(key) else { return }   // otro turno ya lo escribió
        defer { store.release(key, stamp) }
        guard let data = encode() else {
            try? FileManager.default.removeItem(at: file)
            legacy.set(key, data: nil)
            return
        }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            if legacy.data(key) != nil { legacy.set(key, data: nil) }   // la copia de UserDefaults, solo cuando el archivo ya está
        } catch {
            Log.cache.error("No se pudo guardar la caché \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func idle() {}
}
