import Foundation

/// Lo que enseña el botón grande del reproductor: la carga o el play/pausa. Antes vivía suelto en la pantalla, con relojes sin
/// pruebas, y cada arreglo rompía otra cosa (carga que parpadeaba, play que brincaba, carga al pausar). Aquí, una sola regla y
/// probada:
/// - Carga **ya** (`now`): abriendo el video hasta que suena por primera vez, o pidiéndolo otra vez (se cortó, volver a la app).
///   Ahí el play no haría nada, así que ni se asoma.
/// - Carga **si dura** (`soon`): pediste que sonara y no avanza, o se atoró sonando. Un momento (`stallDelay`); más en los
///   primeros segundos de un video (`settleDelay`), cuando el motor hace sus últimos ajustes. Así pausar y seguir nunca la enseñan.
/// - Sin carga (`none`): listo, o en pausa sin nada pendiente.
/// Y el glifo dice lo que tú pediste al momento; si el motor cambia solo, lo sigue solo si el cambio dura (`glyphSettle`).
@MainActor
public final class PlayerPresentation: ObservableModel {
    public enum LoadKind: Equatable, Sendable { case none, soon, now }

    public static let settleWindow: TimeInterval = 5, settleDelay: TimeInterval = 2.5, stallDelay: TimeInterval = 1
    public static let glyphSettle: TimeInterval = 1.2

    public var showsLoading: Bool { track(); return loading }
    public var showsPlaying: Bool { track(); return playing }
    private var loading = true { didSet { if oldValue != loading { changed() } } }
    private var playing = true { didSet { if oldValue != playing { changed() } } }

    private let clock: () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void
    private var loadingTask: Task<Void, Never>?
    private var glyphTask: Task<Void, Never>?
    private var playedVideo: String?
    private var playedAt = Date.distantPast

    public init(clock: @escaping () -> Date = Date.init,
                sleep: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1e9)) }) {
        self.clock = clock
        self.sleep = sleep
    }

    /// Qué tanto carga, solo del estado del reproductor (sin relojes).
    public static func loadKind(_ model: PlayerModel) -> LoadKind {
        if model.phase == .preparing || !model.hasPlayed || model.reconnecting { return .now }
        if model.awaitingPlayback || model.snapshot.state == .loading || model.snapshot.state == .buffering { return .soon }
        return .none
    }

    /// El reproductor cambió: qué tanto carga, si suena y qué video es.
    public func update(_ kind: LoadKind, playing enginePlaying: Bool, videoID: String) {
        loadingTask?.cancel()
        switch kind {
        case .none:
            loading = false
            if enginePlaying, playedVideo != videoID { playedVideo = videoID; playedAt = clock() }
        case .now:
            loading = true
        case .soon:
            let settling = playedVideo != videoID || clock().timeIntervalSince(playedAt) < Self.settleWindow
            let wait = settling ? Self.settleDelay : Self.stallDelay
            loadingTask = Task { [weak self, sleep] in
                await sleep(wait)
                guard !Task.isCancelled else { return }
                self?.loading = true
            }
        }
    }

    /// Tocaste play o pausa: el glifo cambia ya, sin esperar al motor.
    public func userToggled(toPlaying: Bool) {
        glyphTask?.cancel()
        playing = toPlaying
    }

    /// El motor cambió solo: el glifo lo sigue si el cambio dura; entonces dice lo que de verdad pasa (`current`).
    public func engineChanged(current: @escaping @MainActor () -> Bool) {
        glyphTask?.cancel()
        glyphTask = Task { [weak self, sleep] in
            await sleep(Self.glyphSettle)
            guard !Task.isCancelled else { return }
            self?.playing = current()
        }
    }

    /// Al cerrar: ningún reloj sigue vivo.
    public func cancel() { loadingTask?.cancel(); glyphTask?.cancel() }

    /// Para las pruebas: espera a que terminen los relojes en curso.
    func settle() async { await loadingTask?.value; await glyphTask?.value }
}
