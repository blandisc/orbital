import SwiftUI
import OrbitalCore

/// Los íconos propios de Orbital (los mismos de la TV: orbital/web/js/core/icons.js, copiados al catálogo por
/// scripts/list_icons.mjs). Regla de íconos del iPhone: las secciones no llevan ícono (el color lo pone el arte); los
/// renglones de ajustes usan símbolos del sistema en su color; los controles, símbolos del sistema en blanco. Los propios
/// quedan solo como marca (la pestaña «Para ti»).
enum OrbitalIcon: String, CaseIterable {
    case spark, watching, library, bookmark, series, calendar, list, addon, trend, flame, chart, fresh, trophy

    /// Su nombre en el catálogo (para `Tab(_:image:)`).
    var asset: String { "Icons/" + rawValue }
}

/// Los símbolos del sistema que dicen lo mismo en toda la app: uno por idea, para que no cambie de pantalla a pantalla.
extension DS {
    enum Symbol {
        /// Lo que la app hace sola («Descarga inteligente»): dos flechas en círculo (Fernando, 2 nov 2026, J1). Nunca la chispa,
        /// que es el ícono típico de la IA.
        static let automatic = "arrow.triangle.2.circlepath"
        /// Seguir una descarga en pausa: la flecha hacia abajo, siempre con «Seguir» debajo (`DownloadRingButton`).
        static let resumeDownload = "arrow.down"
        /// PT5 (Fernando, 4 nov 2026): todo lo de Real-Debrid (pedir a la nube, bajando en la nube, tus pedidos) es la nube con
        /// flecha; la flecha en círculo es solo «Descargar» a este aparato. Los estados de un pedido: `DebridRequestWords.Icon`.
        static let cloud = DebridRequestWords.Icon.cloud
        static let cloudFill = DebridRequestWords.Icon.cloud + ".fill"
        static let download = "arrow.down.circle"
        /// Revisión 2 del 11 nov: un ícono por idea, con su tabla en `docs/ios-interfaz.md` § «Íconos» (DesignTests la cuida).
        /// Guardar en una lista: el marcador, relleno cuando ya está en alguna.
        static let save = "bookmark", saved = "bookmark.fill"
        /// Más detalle técnico, escondido detrás de la ⓘ.
        static let info = "info.circle"
        /// Saltar segundos en lo que se reproduce (solo eso: nunca para moverse en una fila).
        static let skipBack = "gobackward.10", skipForward = "goforward.10"
        /// Saltar 5 en la fila de la TV (el control).
        static let rowBack = "arrow.left.square", rowForward = "arrow.right.square"
        /// Hecho (lo que llegó a la TV, lo que ya viste): la palomita, nunca el carácter «✓».
        static let done = "checkmark"
        /// PT10: cancelar un pedido en camino (⊗) y quitar de tu Real-Debrid lo que ya terminó (basura).
        static let cancelRequest = DebridRequestWords.Icon.cancel
        static let removeRequest = DebridRequestWords.Icon.remove
        /// La versión recomendada (el destello): solo eso. La leyenda de «Versión» lo explica la primera vez.
        static let recommended = "sparkles"
        /// Lista al instante (ya está en la nube): el rayo, solo eso.
        static let instant = "bolt.fill"
        /// «¿Otro título?»: el nombre de la versión dice otro año. Una vez explicado arriba de la lista, en cada renglón solo el ícono.
        static let otherTitle = "questionmark.circle"
        /// Cambiar de versión para oír ese idioma (el panel de audio del reproductor): antes «↻» como letra.
        static let switchVersion = "arrow.triangle.swap"
        /// La que estás viendo (una lista de secciones): antes «✓» como letra.
        static let current = "checkmark"
        /// Los botones de los controles de otras consolas, en el acompañante (antes ✕ ○ □ △ ☰ ⧉ como letras).
        static let padCross = "xmark", padCircle = "circle", padSquare = "square", padTriangle = "triangle"
        static let padMenu = "line.3.horizontal", padView = "rectangle.on.rectangle"
    }
}
