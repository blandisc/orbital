import Foundation

/// Lo que enseña el botón grande del reproductor: la carga o el play/pausa. Antes vivía suelto en la pantalla, con relojes sin
/// pruebas, y cada arreglo rompía otra cosa (carga que parpadeaba, play que brincaba, carga al pausar). Aquí, una sola regla y
/// probada:
/// - Carga **ya** (`now`): abriendo el video hasta que corre de verdad (`PlayerModel.playbackSettled`: unos segundos avanzados,
///   no el primer «suena» del motor, que enseguida se detiene a llenar el búfer o recarga por la pista de audio), o pidiéndolo otra
///   vez (se cortó, volver a la app). Ahí el play no haría nada, así que ni se asoma.
/// - Carga **si dura** (`soon`): pediste que sonara y no avanza, o se atoró sonando. Un momento (`stallDelay`); más en los
///   primeros segundos de un video (`settleDelay`), cuando el motor hace sus últimos ajustes. Así pausar y seguir nunca la enseñan.
/// - Sin carga (`none`): listo, o en pausa sin nada pendiente.
/// Y el glifo dice lo que tú pediste al momento; si el motor cambia solo, lo sigue solo si el cambio dura (`glyphSettle`).
/// Siempre lo opuesto a lo que pasa: sonando (o llenando el búfer), pausa; en pausa, play. Al abrir: carga → pausa, nada más.
@MainActor
public final class PlayerPresentation: ObservableModel {
    public enum LoadKind: Equatable, Sendable { case none, soon, now }

    public static let settleWindow: TimeInterval = 5, settleDelay: TimeInterval = 1.2, stallDelay: TimeInterval = 0.8
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
        // Sonó un instante y se detuvo a llenar el búfer (o recarga por la pista de audio): sigue la misma carga, no pausa → carga.
        if !model.playbackSettled, model.wantsToPlay || model.snapshot.state == .loading { return .now }
        if model.awaitingPlayback || model.snapshot.state == .loading || model.snapshot.state == .buffering { return .soon }
        return .none
    }

    /// El reproductor cambió: qué tanto carga, si suena y qué video es.
    public func update(_ kind: LoadKind, playing enginePlaying: Bool, videoID: String) {
        loadingTask?.cancel()
        switch kind {
        case .none:
            // Al terminar de cargar, el glifo dice lo que pasa de verdad (casi siempre «pausa»: ya suena). Antes se quedaba con
            // lo que el motor dijo a media carga y, con el video sonando, enseñaba play.
            if loading { glyphTask?.cancel(); playing = enginePlaying }
            loading = false
            if enginePlaying, playedVideo != videoID { playedVideo = videoID; playedAt = clock() }
        case .now:
            loading = true
            // Mientras carga, el glifo no sigue al motor (que arranca, se detiene un instante y sigue); al terminar de cargar
            // dice «pausa» (va a sonar). Antes se veía carga → play → pausa.
            glyphTask?.cancel()
            playing = true
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

    /// El motor cambió solo: el glifo lo sigue si el cambio dura; entonces dice lo que de verdad pasa (`current`). `current`
    /// cuenta llenar el búfer como sonar (`PlayerModel.wantsToPlay`): un atorón enseña la carga, nunca el play.
    public func engineChanged(current: @escaping @MainActor () -> Bool) {
        glyphTask?.cancel()
        guard !loading else { return }   // cargando, el botón enseña la carga: nada que seguir
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
