import Foundation

public protocol PendingStore: Sendable {
    func load() -> PendingWork
    func save(_ work: PendingWork)
    /// Leer, cambiar y guardar en un solo paso (nadie escribe en medio): así dos `WatchService` a la vez (al rearmar los
    /// servicios) o la cola y la pantalla no se pisan lo que acaban de anotar. Devuelve lo que quedó.
    @discardableResult func update(_ body: (inout PendingWork) -> Void) -> PendingWork
    /// Como `update`, pero dice si quedó en disco (la migración de `trakt-outbox` borra lo viejo solo entonces).
    func commit(_ body: (inout PendingWork) -> Void) -> Bool
}

public final class InMemoryPendingStore: PendingStore, @unchecked Sendable {
    private let lock = NSLock()
    private var work = PendingWork()
    public init() {}
    public func load() -> PendingWork { lock.withLock { work } }
    public func save(_ work: PendingWork) { lock.withLock { self.work = work } }
    @discardableResult public func update(_ body: (inout PendingWork) -> Void) -> PendingWork {
        lock.withLock { body(&work); return work }
    }
    public func commit(_ body: (inout PendingWork) -> Void) -> Bool { update(body); return true }
}

/// La cola en un archivo JSON (Application Support): sobrevive a que cierren la app.
///
/// Revisión del 11 nov 2026: un tropiezo al leer (el archivo protegido con el iPhone bloqueado) ya no se toma por «vacío»
/// ni se aparta: el archivo nunca se pisa. Mientras no se pueda leer, lo que anotes vive en memoria y se junta con el archivo
/// en cuanto se pueda leer. Un elemento mal formado se aparta solo (los demás siguen).
public final class FilePendingStore: PendingStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    /// Lo último que se leyó o escribió aquí (esta app es la única que escribe el archivo: con esto se puede seguir aunque un
    /// momento no se pueda leer).
    private var known: PendingWork?
    /// Lo que se anotó sin haber podido leer nunca el archivo: se junta con él al poder leerlo.
    private var unsaved: PendingWork?
    private let read: @Sendable (URL) -> StoredRead<PendingWork>

    public convenience init(url: URL) {
        self.init(url: url, read: { StoredFile.load(PendingWork.self, from: $0, what: "el trabajo pendiente") })
    }
    /// `read`: cómo se lee el archivo (las pruebas simulan un tropiezo pasajero).
    init(url: URL, read: @escaping @Sendable (URL) -> StoredRead<PendingWork>) { self.url = url; self.read = read }

    public func load() -> PendingWork { lock.withLock { current(setAside: false) ?? unsaved ?? PendingWork() } }

    public func save(_ work: PendingWork) { _ = commit { $0 = work } }

    @discardableResult public func update(_ body: (inout PendingWork) -> Void) -> PendingWork {
        lock.withLock { apply(body).work }
    }

    public func commit(_ body: (inout PendingWork) -> Void) -> Bool { lock.withLock { apply(body).saved } }

    /// Con el candado puesto.
    private func apply(_ body: (inout PendingWork) -> Void) -> (work: PendingWork, saved: Bool) {
        guard var work = current(setAside: true) else {
            // No se pudo leer y nunca se ha leído: no se escribe encima (lo perderías); queda en memoria hasta poder leerlo.
            var pendingHere = unsaved ?? PendingWork()
            body(&pendingHere)
            unsaved = pendingHere
            return (pendingHere, false)
        }
        body(&work)
        let saved = StoredFile.write(work, to: url, what: "el trabajo pendiente")
        if saved { known = work; unsaved = nil } else { known = work; unsaved = work }
        return (work, saved)
    }

    /// Lo que hay: lo del archivo (más lo anotado mientras no se podía leer), lo último conocido si ahora no se puede leer, o
    /// nil si nunca se ha podido. `setAside`: apartar los elementos mal formados (solo al ir a escribir: así no se apartan dos
    /// veces).
    private func current(setAside: Bool) -> PendingWork? {
        switch read(url) {
        case .loaded(var work):
            if !work.rejected.isEmpty {
                if setAside { StoredFile.keepRejected(JSON.array(work.rejected).serialized(), near: url, what: "el trabajo pendiente") }
                work.rejected = []
            }
            if let unsaved { work = work.union(unsaved) }
            known = work
            return work
        case .missing, .corrupt:
            let work = unsaved ?? PendingWork()
            known = work
            return work
        case .unreadable:
            return known
        }
    }
}
