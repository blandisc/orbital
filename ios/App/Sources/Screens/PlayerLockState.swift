import SwiftUI
import OrbitalCore
import OrbitalModels

/// El candado del reproductor: bloqueado, su aviso (entrar, encoger, subir) y la tarea que lo esconde.
/// Vive aparte de `PlayerScreen` (ver `PlayerDragState`): las vistas que lo leen se vuelven a pintar con cada cambio.
@MainActor
@Observable
final class PlayerLockState {
    /// «Bloquear» (como Netflix): sin controles y la pantalla no responde a toques ni deslizamientos (para no pausar o adelantar
    /// sin querer). Un toque enseña la cápsula de arriba con «Desbloquear».
    var locked = false
    /// La cápsula de «Pantalla bloqueada» (arriba). `showsUnlock`: tras un toque, con el botón. `collapsed`: ya es el
    /// círculo del candado. `risen`: sube y se desvanece. `generation` descarta un cierre si llegó otro aviso.
    var lockNoticeVisible = false
    var lockNoticeShowsUnlock = false
    var lockNoticeCollapsed = false
    var lockNoticeRisen = false
    var lockNoticeGeneration = 0
    var unlockHide: Task<Void, Never>?
}
