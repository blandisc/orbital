import SwiftUI
import OrbitalCore

/// Los tokens de la imagen: el fondo de pantalla, cómo se pide y se muestra el arte, y los pósters. Salieron de `Tokens.swift`
/// (27 nov 2026) para que no pasara de su tope de líneas (`FileBudgetTests`). También los compila el widget.
extension DS {
    /// El fondo de pantalla: tono del arte, estrellas del espacio vivo y el fundido del arte a sangre.
    enum Backdrop {
        /// Cuánto se mezcla el color del arte con el fondo de cada modo, y hasta dónde llega antes de fundirse con el fondo.
        static let lightMix = DesignTokens.Projection.lightMix, fadeTo = DesignTokens.Projection.fadeTo
        static let tintFloor = DesignTokens.Backdrop.tintFloor
        /// Dónde empieza el velo sobre el arte, dónde llega a medio y (al pie) a fondo.
        static let scrimStart = DesignTokens.Backdrop.scrimStart, scrimMid = DesignTokens.Backdrop.scrimMid
        static let artFadeStart = DesignTokens.Backdrop.artFadeStart
        /// Un segundo brillo del mismo tono, abajo a un lado: lo de debajo del destacado no queda en negro liso.
        static let lowGlow: Double = 0.22
        static let lowGlowCenter = UnitPoint(x: 0.85, y: 0.75)
        static let lowGlowRadius: CGFloat = 420
        /// La ficha inmersiva (como un álbum en Música): toda la pantalla del tono del arte, que se hunde hacia el pie.
        static let immersiveDeep: Double = 0.55, immersiveGlow: Double = 0.35
        static let immersiveGlowRadius: CGFloat = 520
    }

    /// Tamaño de los pósters (relación 2:3, como en la TV).
    /// A qué tamaño (lado más largo, en puntos) se reduce cada imagen remota al bajarla (`RemoteImage`).
    enum Image {
        /// `bleed`: el arte a sangre (la ficha, «En tendencia»). Un fondo 16:9 que llena un marco alto se dibuja más ancho que la
        /// pantalla (en la ficha de un iPhone, ~800 pt): con 480 se veía agrandado y suave.
        static let card: CGFloat = 200, mosaic: CGFloat = 192, logo: CGFloat = 240, platformLogo: CGFloat = 96
        /// En la Mac el arte a sangre mide la ventana (con 800 la portada se veía pixeleada, 16 nov 2026); iPhone y iPad, 800
        /// (más era casi el triple de memoria por imagen en el iPad sin que se notara).
        static var bleed: CGFloat { ProcessInfo.onMac ? max(bleedPhone, WindowMetrics.column.width) : bleedPhone }
        static let bleedPhone: CGFloat = 800
        /// Una tarjeta ancha de lado a lado (la portada de un estreno, `CoverCard`): con `card` se pedía la versión chica (480 px).
        static var wide: CGFloat { ProcessInfo.onMac ? max(widePhone, WindowMetrics.column.width / 2) : widePhone }   // en la Mac la tarjeta crece con la columna
        static let widePhone: CGFloat = 420
        /// El desenfoque de la copia que rellena el marco cuando la imagen va completa (`ArtFit.whole`).
        static let wholeBlur: CGFloat = 28
        /// Hasta dónde se ve nítido un fondo ancho completo arriba (`ArtFit.wholeTop`) antes de fundirse en su copia difuminada.
        static let wholeTopFade: CGFloat = 0.7
        /// Basta una miniatura para sacar el color medio del fondo.
        static let tintPixels: CGFloat = 48
        /// La imagen de un aviso («Ya está para ver»): el lado más largo y la calidad del JPEG.
        static let notification = 1000, notificationQuality: CGFloat = 0.82
    }

    enum Poster {
        static let aspect = DesignTokens.Aspect.poster
        static let stillAspect = DesignTokens.Aspect.still
        /// El póster de una tira: 112 pt en el iPhone; en una ventana ancha (iPad, Mac, desde `gridWideWidth`) más grande: con
        /// el tamaño del teléfono se veían diminutos en una pantalla de 13". Se lee al pintar: cambia solo al cambiar la ventana.
        static var railWidth: CGFloat {   // con espacio, C5 (`filling`); si no, sin el panel de la derecha
            let wide = ProcessInfo.onMac ? Mac.railWidth : railWidthWide
            return WindowMetrics.roomy ? filling(target: wide, columns: railColumns) : WindowMetrics.column.width >= gridWideWidth ? wide : railWidthCompact
        }
        static let railWidthCompact: CGFloat = 112, railWidthWide: CGFloat = 148
        static let gridMinimum: CGFloat = 100
        /// `DSPosterGrid`: columnas fijas que llenan el ancho (3; 4 en pantallas anchas; 2 con letra de accesibilidad) y
        /// desde qué ancho de contenido cuenta como ancha (iPhone horizontal, iPad).
        static let gridColumns = 3, gridColumnsWide = 4, gridColumnsLarge = 2
        static let gridWideWidth: CGFloat = 600
        /// Cuántas columnas en `width` (el ancho del contenido, con sus márgenes).
        static func gridColumns(for width: CGFloat) -> Int {
            guard width >= gridWideWidth else { return gridColumns }
            let inner = width - DS.Space.gutter * 2 + DS.Space.s2
            // Los pósters de una cuadrícula miden lo mismo que los de las filas (26 nov 2026: en Buscar, los resultados salían
            // más chicos que «Lo más popular hoy» justo arriba): tantas columnas como quepan del ancho de una fila.
            return max(gridColumnsWide, Int(inner / (railWidth + DS.Space.s2)))
        }
        /// Las cuadrículas «de dos en dos» del iPhone (Top 10 completo, tus listas, Seguir viendo): en una ventana ancha (iPad,
        /// Mac) dos columnas hacían pósters de ~500 pt; ahí van tantas como quepan de al menos `wideMin`. El iPhone (vertical
        /// siempre, menos de `gridWideWidth`) queda igual: dos.
        static func pairColumns(spacing: CGFloat, wideMin: CGFloat = pairWideMin) -> [GridItem] {
            guard WindowMetrics.column.width >= gridWideWidth else { return Array(repeating: GridItem(.flexible(), spacing: spacing), count: 2) }
            return [GridItem(.adaptive(minimum: wideMin), spacing: spacing, alignment: .top)]
        }
        static let pairWideMin: CGFloat = 170, stillWideMin: CGFloat = 280
        static let episodeThumbWidth: CGFloat = 122
        /// Una tarjeta de «Próximos estrenos»: dos y un pedazo (`peek`) de la tercera, en cualquier ancho (con un ancho fijo, en un
        /// iPhone de 375 pt las dos llenaban la pantalla y parecía una cuadrícula que terminaba a 5 pt del borde).
        static let peek: CGFloat = 28
        /// Una pieza ancha (16:9) de un riel: «Todo lo que sigues», episodios nuevos.
        static var stillWidth: CGFloat {   // con espacio, C5 (`filling`)
            WindowMetrics.roomy ? filling(target: stillWidthWide, columns: stillColumns) : WindowMetrics.column.width >= gridWideWidth ? stillWidthWide : stillWidthCompact
        }
        static let stillWidthCompact: CGFloat = 220, stillWidthWide: CGFloat = 280
        static let heroHeight: CGFloat = 300
        /// El póster pequeño de «Viendo en la TV» (misma relación 2:3, más chico que el de la tira).
        static let nowPlayingWidth: CGFloat = 56
        /// La tarjeta «Desde la TV»: arte ancho con su logo, datos y acciones encima.
        static let fromTVHeight: CGFloat = 220
    }
}
