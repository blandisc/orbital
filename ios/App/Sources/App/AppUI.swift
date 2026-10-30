import SwiftUI
import OrbitalModels

/// Lo que solo pinta la raíz de la app: el reproductor a pantalla completa, los avisos y lo que se pide abrir.
@MainActor
/// `@Observable`: cada vista se vuelve a pintar solo con lo que lee (el aviso no redibuja el reproductor).
@Observable
final class AppUI {
    /// «Viendo en la TV» va junto a la barra minimizada (al desplazar) y no encima de ella: la pastilla de calificar baja.
    var tvAccessoryInline = false
    var playing: PlayRequest?
    var pendingTitle: TitleRoute?
    var askFinished: PlayRequest?
    var handoff: AppEnvironment.TVHandoff?
    var openTab: Int?
    /// El Centro de control pidió el control de tu Orbital.
    var openRemote = false
    /// El Centro de control pidió «Un Simpson al azar»: Inicio abre la ruleta.
    var openSimpsons = false
    /// Abrir Ajustes (desde un aviso, como «Tu sesión de Trakt se cerró · Conectar»).
    var openSettings = false
    /// La guía de la primera vez a la vista (al abrir la primera vez, o desde Ajustes › «Cómo funciona Orbital»).
    var showingGuide = false
    /// «Atrás» de la barra de menús (⌘[): regresa una pantalla en la pestaña que ves.
    var goBack = false
    /// Tocaste «Buscar» estando ya en Buscar: se abre el campo con el teclado listo.
    var focusSearch = false
    /// La entrada de la app está a la vista (el logotipo de Inicio espera escondido a que llegue el de la entrada).
    var splashing = false
    /// Dónde está el logotipo de Inicio en la pantalla, si se ve: ahí termina la entrada.
    var homeLogoFrame: CGRect?
}
