import SwiftUI

/// Tokens del Inicio nuevo y de Para ti B (docs/producto/inicio-benchmark/): la portada, «Lo nuevo de lo tuyo», Canales, la
/// franja del tipo y las piezas de Para ti. Los del cielo, en Tokens+Sky.
extension DS {
    /// La portada de Inicio: arte de borde a borde (pasa detrás de la barra) que se desliza entre títulos.
    enum HomeHero {
        /// Ancho entre alto del arte: casi un póster en el iPhone; más bajo en pantallas cortas (el SE) y apaisado en ventana
        /// ancha (iPad, Mac), donde un póster quedaría altísimo.
        static let aspect: CGFloat = 0.78, aspectShort: CGFloat = 1.25, shortScreen: CGFloat = 700, aspectWide: CGFloat = 1.9
        /// Desde qué ancho la ventana es «ancha» (el iPad mini de pie mide 744: antes el umbral era 800 y le tocaba la portada
        /// del iPhone, de casi toda la pantalla). En ventana ancha y de pie (iPad vertical) la portada es menos apaisada que
        /// acostada: con 1.9 quedaba en un tercio de la pantalla.
        static let wideFrom: CGFloat = 700, aspectWidePortrait: CGFloat = 1.4
        /// La de esta ventana (la portada y su esqueleto, `HeroSkeleton`, miden lo mismo).
        static var current: CGFloat {
            let size = WindowMetrics.size
            if size.width >= wideFrom {
                // Acostado (iPad, Mac a pantalla completa) 1.9 dejaba la portada en casi toda la ventana y «Seguir viendo»
                // abajo, fuera de la vista: no pasa de `maxHeightShare` del alto de la ventana (más apaisada si hace falta).
                let base = size.height > size.width ? aspectWidePortrait : aspectWide
                return min(aspectWideMax, max(base, size.width / (size.height * maxHeightShare)))
            }
            return size.height < shortScreen ? aspectShort : aspect
        }
        /// En ventana ancha, la portada mide a lo más esta parte del alto de la ventana (iPad acostado, Mac), sin pasar de
        /// `aspectWideMax`: más apaisada, el fondo 16:9 ya no llenaba el marco (`ArtFit.narrowLimit`) y salía con franjas.
        static let maxHeightShare: CGFloat = 0.6, aspectWideMax: CGFloat = 2.4
        /// Cuánto se enciman «Seguir viendo» sobre el borde de abajo de la portada (se ve sin bajar).
        static let overlap: CGFloat = 44
    }

    /// «Lo nuevo de lo tuyo»: el ancho de cada pieza, el renglón del día, la marca de hoy y lo apagado de lo que viene.
    enum HomeTimeline {
        static let width: CGFloat = 112, labelRow: CGFloat = 18, dot: CGFloat = 7
        static let markLine: CGFloat = 2
        /// Dónde queda HOY al abrir (de 0 a 1 en el ancho): lo de antes a la izquierda y un poco de lo que viene.
        static let todayAnchor: CGFloat = 0.62
        /// La primera vez: cuánto espera antes de deslizarse hasta HOY (que se vea el paseo) y cuánto crece la marca al latir.
        static let settleDelay: Double = 0.4, pulseScale: CGFloat = 1.18
    }

    /// Canales: el ancho de cada canal, su logo, el velo, cada cuánto se recalcula, el acercamiento lento de la imagen del
    /// capítulo (el «cachito») y la hoja para elegir.
    enum HomeChannels {
        static let width: CGFloat = 268, addWidth: CGFloat = 150
        static let logoWidth: CGFloat = 96, logoHeight: CGFloat = 30
        static let veilStart: Double = 0.4
        static let tick: TimeInterval = 30
        static let drift: Double = 14, driftScale: CGFloat = 1.1
        /// El acercamiento a 30 cuadros (no a los 120 de la pantalla) y desde qué parte visible cuenta como «se ve».
        static let driftFrame: TimeInterval = 1.0 / 30, visibleShare = 0.01
        static let searchDelay: Duration = .milliseconds(350)
        static let gridColumns = 4, resultPoster: CGFloat = 44
    }

    /// Para ti B: los círculos del índice, la portada del mosaico (su muro inclinado y el velo) y la tarjeta de «¿Qué vemos hoy?».
    enum ParaTiB {
        /// El botón del mosaico sobre el muro de Para ti (blanco, redondo, abajo a la derecha).
        static let walkButton: CGFloat = 52
        /// El muro: ocho columnas (con siete, girado, quedaba una orilla sin pósters) de trece pósters cada vuelta.
        static let coverHeight: CGFloat = 300, coverWall: CGFloat = 828, coverColumns = 8, coverPosters = 96, coverTilt: Double = -10
        static let coverRows = 13, coverWallHeight: CGFloat = 1900
        /// En ventana ancha (iPad acostado o grande, Mac) el muro suma columnas del mismo ancho hasta cubrir la ventana (con
        /// las ocho de siempre quedaba una cuña en blanco a la izquierda). Hasta el ancho del iPad de pie, las ocho de siempre.
        static func coverColumns(forWidth width: CGFloat) -> Int {
            let needed = Int((CGFloat(coverColumns) * width / coverWall).rounded(.up))
            return needed > coverColumns ? needed + 1 : coverColumns
        }
        static let coverClearAt: Double = 0.25, coverBaseVeil: Double = 0.8, coverBaseAt: Double = 0.6
        /// Cuánto sube el muro (hasta la orilla de la pantalla, detrás del título y la barra: sin corte) y cuánto baja bajo los
        /// círculos; qué tanto se ve hasta arriba y el velo que deja leer el título encima.
        static let coverBleedUp: CGFloat = 900, coverTitleZone: CGFloat = 260, coverBleedDown: CGFloat = 72, coverUnderBar: Double = 0.85, coverTitleVeil: Double = 0.55
        /// Cada columna del muro baja sola, a su ritmo (puntos por segundo, una por columna: ninguna va pareja con su vecina), y
        /// arranca en otra parte de su vuelta (`coverPhaseStep`). Corre solo con la portada a la vista (`coverVisibleFrom`). Lo
        /// mueve Core Animation (`CoreDrift`), no SwiftUI: por eso van en números y no como `Animation`.
        /// «Marea lenta» (Fernando, 1 nov 2026: antes de 7 a 19 y dos columnas se sentían apuradas): casi parejas y despacio, y
        /// una baja mientras la de al lado sube (`coverAlternates`). La diagonal del muro se queda. Un poco más lenta (Fernando,
        /// 2 nov 2026): un cuarto menos (antes de 8 a 9.5).
        static let coverPace: [Double] = [6, 6.75, 6.4, 7.1, 6, 6.75, 6.4, 7.1], coverPhaseStep = 0.37, coverVisibleFrom: Double = 0.1
        static let coverAlternates = true
        static let deckPoster: CGFloat = 84, deckShift: CGFloat = 10, deckTurn: Double = 5, deckBehind: Double = 0.6
        /// Cuántos pósters lleva el abanico de «¿Qué vemos hoy?» (y cuántos de la portada se saltan para no repetirlos).
        static let matchFan = 3
        /// «La temporada»: el ancho de sus pósters y cuánto la tiñe su color. Un renglón de «Tuyo»: cuánto asoma cada póster.
        static let seasonPoster: CGFloat = 76, seasonGlow: Double = 0.35, rowShift: CGFloat = 14
    }
}
