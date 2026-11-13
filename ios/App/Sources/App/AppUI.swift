import SwiftUI
import OrbitalModels

/// Lo que solo pinta la raíz de la app: el reproductor a pantalla completa, los avisos y lo que se pide abrir.
@MainActor
/// `@Observable`: cada vista se vuelve a pintar solo con lo que lee (el aviso no redibuja el reproductor).
@Observable
final class AppUI {
    /// «Viendo en la TV» va junto a la barra minimizada (al desplazar) y no encima de ella: la pastilla de calificar baja.
    var tvAccessoryInline = false
    /// Sube cada vez que regresas a la app después de un rato fuera (la misma regla que refresca Inicio): la pantalla que
    /// dejaste abierta (Explorar, una ficha) se pone al día y no enseña lo de antes (Fernando, 2 nov 2026: «cuando sales y
    /// regresas te muestra una pantalla no actualizada del último lugar donde dejaste la app»).
    var returnedToApp = 0
    var playing: PlayRequest?
    /// La tarjeta de la que nace el reproductor (la pone quien toca «Ver»); se olvida al cerrarlo, ya que regresó a ella.
    var playerSource: PlayerZoomID?
    var pendingTitle: TitleRoute?
    var askFinished: PlayRequest?
    var handoff: AppEnvironment.TVHandoff?
    /// Lo que se está mandando a tu Orbital (su `metaID`): el botón de la tele gira y no se manda dos veces.
    var sendingToTV: String?
    /// Lo que flota sobre la barra de pestañas en la pantalla de ahora (el pie del mosaico): los avisos suben eso para
    /// no taparlo.
    var noticeLift: CGFloat = 0
    /// Una pantalla encima de todo (el mazo de «¿Qué vemos hoy?») pinta los avisos ella misma: la raíz no los repite (vibraría
    /// dos veces y VoiceOver los leería dos veces).
    var coverShowsNotices = false
    var openTab: Int?
    /// Un aviso de descargas, «Ver en Descargas» o «Tus pedidos»: Biblioteca abre en su parte «Descargas» (no donde la dejaste).
    var showDownloads = false
    /// Tocaste el aviso «Ya está…» o «Sigue sin bajar» de un pedido a Real-Debrid: Biblioteca › Descargas abre con la hoja de
    /// ese pedido (su huella).
    var openCloudRequest: String?
    /// N1: una descarga que empezó: su póster vuela a la pestaña Biblioteca (`DownloadFlightLayer`).
    var downloadFlight: DownloadFlight?
    /// «Otra fecha» del aviso de «Vista» (gestor ola 3): la vista que se acaba de marcar y que pasa a otro día.
    var redate: RedateRequest?
    /// Biblioteca › Descargas está a la vista: la marca de la pestaña no sale (ya lo estás viendo).
    var seeingDownloads = false
    /// Lo que mide «¿Qué tal…?» flotando sobre la barra (0 si no está): Guardado le aparta ese lugar abajo (GD2).
    var ratingReminderHeight: CGFloat = 0
    /// El Centro de control pidió el control de tu Orbital.
    var openRemote = false
    /// V9: lo que hacen el botón del control de Inicio y abrir una ficha en el panel (iPad, Mac), por ventana (`window`). Las
    /// pone la raíz de cada ventana; el entorno solo lleva datos (`RemoteOpener`, `TitlePanelOpener`), así no se vuelve a
    /// pintar quien lo lee con cada pasada de la raíz.
    @ObservationIgnored var remoteButtons: [Int: () -> Void] = [:]
    @ObservationIgnored var titlePanels: [Int: (TitleRoute, CGRect?) -> Void] = [:]
    @ObservationIgnored private var lastWindow = 0
    /// Un número para cada ventana (lo guarda su raíz en un `@State`).
    func newWindow() -> Int { lastWindow += 1; return lastWindow }
    /// El Centro de control pidió «Un Simpson al azar»: Inicio abre la ruleta.
    var openSimpsons = false
    /// Abrir Ajustes (desde un aviso, como «Tu sesión de Trakt se cerró · Conectar»).
    var openSettings = false
    /// Abrir Ajustes › Tus idiomas (N4-A; la historia «Tus idiomas» de la guía termina aquí). Se apaga sola al abrirla.
    var openLanguages = false
    /// La guía de la primera vez a la vista (al abrir la primera vez, o desde Ajustes › Aprende Orbital).
    var showingGuide = false
    /// Una historia de «Aprende Orbital» a pantalla completa (su id), desde los círculos de Inicio, Ajustes o un aviso.
    var openStory: String?
    /// Abrir la búsqueda avanzada (el botón final de su historia).
    var openAdvancedFilter = false
    /// «Atrás» de la barra de menús (⌘[): regresa una pantalla en la pestaña que ves.
    var goBack = false
    /// Tocaste «Buscar» estando ya en Buscar: se abre el campo con el teclado listo.
    var focusSearch = false
    /// La entrada de la app está a la vista (el logotipo de Inicio espera escondido a que llegue el de la entrada).
    var splashing = false
    /// Dónde está el logotipo de Inicio en la pantalla, si se ve: ahí termina la entrada.
    var homeLogoFrame: CGRect?
}

/// La vista recién marcada que pasa a otro día (gestor ola 3).
struct RedateRequest: Identifiable, Equatable {
    var kind: String
    var videoID: String
    var at: Date
    var id: String { "\(videoID)@\(at.timeIntervalSince1970)" }
}
