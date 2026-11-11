import Foundation

/// La cola de lo que espera a la red para Trakt.
extension WatchService {
    // MARK: la cola
    /// Sube lo que quedó esperando, por la cola única (`TraktQueue`, F4), que se vacía de uno en uno en toda la app aunque haya
    /// dos `WatchService` (al rearmar los servicios). Un avance viejo no pisa algo más nuevo hecho en otro aparato. Lo que
    /// llegue a la cola mientras tanto se conserva.
    @discardableResult
    public func flushPending() async -> PendingWork {
        guard let trakt else { return pending.load() }
        return await traktQueue.flush(trakt, checkpoint: { [weak self] event, target in try await self?.sendCheckpoint(event, target) })
    }

    /// Desde cuántos vistos pendientes se suben juntos.
    static let batchFrom = 4
}
