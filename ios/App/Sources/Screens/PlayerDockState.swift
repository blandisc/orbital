import SwiftUI
import OrbitalCore
import OrbitalModels

/// El panel de abajo del reproductor (audio y subtítulos, episodios, versiones, sincronía): qué página, qué sección y lo que trae.
/// Vive aparte de `PlayerScreen` (ver `PlayerDragState`): las vistas que lo leen se vuelven a pintar con cada cambio.
@MainActor
@Observable
final class PlayerDockState {
    /// Subtítulos rápidos (el panel chico sobre el video) y su lista de idiomas.
    var subtitleDock = false
    var dockPage: PlayerScreen.DockPage = .media
    /// Las temporadas de la serie que suena, para «Episodios» (se leen al abrirlo: son cientos de episodios).
    var episodeSeasons: [Season] = []
    /// Viendo un archivo descargado, los episodios que también están bajados (los demás no se pueden poner).
    var playableEpisodes: Set<String>?
    var dockOpens: SubtitleDock.Section? = .subtitles
    var versionShowsAll = false
    /// Una versión que Real-Debrid aún no tiene: se pregunta antes de abrirla (puede tardar o no abrir).
    var slowPick: Int?
    /// Lo que mide la hoja (para que en vertical ocupe lo suyo y, si no cabe, se recorra).
    var dockLanguages = false
    /// «Todas las versiones» desde el panel chico: media hoja (el video sigue a la vista arriba).
    var dockVersions = false
    /// «Sincronizar con una línea»: las frases congeladas (nil: no está abierto), la que tocaste y el ajuste que quedó.
    var syncLines: [SubtitleLine]?
    var syncPicked: Double?
    var syncResult: Double?
    /// El alto que pide «Audio y subtítulos» en vertical (para subir el video lo justo y que quepa sin desplazarse).
    var dockNeed: CGFloat = 0
}
