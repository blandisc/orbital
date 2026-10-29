import SwiftUI
import OrbitalCore
import OrbitalModels

/// Lo que el reproductor dice encima del video: el aviso del modelo, el de subtítulos, los que esperan su turno y el ícono fugaz.
/// Vive aparte de `PlayerScreen` (ver `PlayerDragState`): las vistas que lo leen se vuelven a pintar con cada cambio.
@MainActor
@Observable
final class PlayerNoticeState {
    /// «Subtítulos desactivados» o «Español · 1 de 4», un momento, al apagar o prender con el botón.
    var subtitleToast: String?
    /// Lo que pasó al pedir «Descargar» (el mismo aviso que en el resto de la app, arriba: abajo están los controles).
    var notice: PlayerScreen.PlayerNotice?
    /// Avisos que llegaron con la cápsula del candado en pantalla. Salen, en orden, cuando esa cápsula se va.
    var heldNotices = HeldNotices<PlayerScreen.QueuedNotice>()
    var heldDrain: Task<Void, Never>?
    var heldDrainGeneration = 0
    /// El ícono que aparece un momento al centro tras un doble toque (pausa, ±10 s).
    var flashSymbol: String?
    var flashTask: Task<Void, Never>?
}
