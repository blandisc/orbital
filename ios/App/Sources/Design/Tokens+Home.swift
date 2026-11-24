import SwiftUI

/// Tokens del Inicio nuevo y de Para ti B (docs/producto/inicio-benchmark/): la portada, «Lo nuevo de lo tuyo», Canales, la
/// franja del tipo y las piezas de Para ti. Los del cielo, en Tokens+Sky.
extension DS {
    /// La portada de Inicio: arte de borde a borde (pasa detrás de la barra) que se desliza entre títulos.
    enum HomeHero {
        /// Ancho entre alto del arte: casi un póster en el iPhone; más bajo en pantallas cortas (el SE) y apaisado en ventana
        /// ancha (iPad, Mac), donde un póster quedaría altísimo.
        /// Cuánto espera el carrusel a que la ventana deje de cambiar de tamaño antes de volver a acomodarse en su portada.
        static let resizeSettle: Duration = .milliseconds(120)
        static let aspect: CGFloat = 0.78, aspectShort: CGFloat = 1.25, shortScreen: CGFloat = 700, aspectWide: CGFloat = 1.9
        /// Desde qué ancho la ventana es «ancha» (el iPad mini de pie mide 744: antes el umbral era 800 y le tocaba la portada
        /// del iPhone, de casi toda la pantalla). En ventana ancha y de pie (iPad vertical) la portada es menos apaisada que
        /// acostada: con 1.9 quedaba en un tercio de la pantalla.
        static let wideFrom: CGFloat = 700, aspectWidePortrait: CGFloat = 1.4
        /// La de esta ventana (la portada y su esqueleto, `HeroSkeleton`, miden lo mismo), con lo que de verdad le queda
        /// (`WindowMetrics.column`): con el control abierto a la derecha (iPad acostado, Mac) se calculaba con la ventana
        /// entera y la portada quedaba más baja y más apaisada que sin él.
        static var current: CGFloat {
            let size = WindowMetrics.column
            if WindowMetrics.size.width >= wideFrom {   // ds-exception: ancha o no la decide la ventana (con el panel sigue siendo la del iPad)
                // Acostado (iPad, Mac a pantalla completa) 1.9 dejaba la portada en casi toda la ventana y «Seguir viendo»
                // abajo, fuera de la vista: no pasa de `maxHeightShare` del alto de la ventana (más apaisada si hace falta).
                let base = size.height > size.width ? aspectWidePortrait : aspectWide
                let fitted = max(base, size.width / (size.height * maxHeightShare))
                // En la Mac no hay tope: más apaisada, el arte va a la derecha sobre su copia difuminada (`PosterView`,
                // `sideFade`), así en un monitor ultrawide la portada no pasa de su parte del alto (antes llenaba la ventana).
                return ProcessInfo.processInfo.isiOSAppOnMac ? fitted : min(aspectWideMax, fitted)
            }
            return size.height < shortScreen ? aspectShort : aspect
        }
        /// En ventana ancha, la portada mide a lo más esta parte del alto de la ventana (iPad acostado, Mac), sin pasar de
        /// `aspectWideMax`: más apaisada, el fondo 16:9 ya no llenaba el marco (`ArtFit.narrowLimit`) y salía con franjas.
        static let maxHeightShare: CGFloat = ProcessInfo.processInfo.isiOSAppOnMac ? DS.Mac.heroHeightShare : 0.6, aspectWideMax: CGFloat = 2.4
        /// Un arte a sangre mucho más angosto que su marco (la Mac, sobre todo un monitor ultrawide) va a la derecha y se funde
        /// hacia la izquierda en su copia difuminada (`PosterView`): esta parte de su ancho, desde la izquierda, se funde.
        static let sideFade: CGFloat = 0.45
        /// Cuánto se enciman «Seguir viendo» sobre el borde de abajo de la portada (se ve sin bajar).
        static let overlap: CGFloat = 44
    }

    /// «Lo nuevo de lo tuyo»: el ancho de cada pieza, el renglón del día, la marca de hoy y lo apagado de lo que viene.
    enum HomeTimeline {
        static let width: CGFloat = 112, labelRow: CGFloat = 18, dot: CGFloat = 7
        /// El punto de «Nuevo» en la esquina del póster (en vez del listón, que tapaba media portada).
        static let newDot: CGFloat = 10
        /// Con letra grande la tarjeta crece con el texto hasta este múltiplo (más, y la línea ya no se recorre de un vistazo);
        /// la hora o el día se encoge a lo más hasta `labelShrink` antes de cortarse.
        static let maxGrowth: CGFloat = 1.5, labelShrink: CGFloat = 0.8
        static let markLine: CGFloat = 2
        /// Dónde queda HOY al abrir (de 0 a 1 en el ancho): lo de antes a la izquierda y un poco de lo que viene.
        static let todayAnchor: CGFloat = 0.62
        /// La primera vez: cuánto espera antes de deslizarse hasta HOY (que se vea el paseo) y cuánto crece la marca al latir.
        static let settleDelay: Double = 0.4, pulseScale: CGFloat = 1.18
    }

    /// Canales: el ancho de cada canal, su logo, el velo, cada cuánto se recalcula, el acercamiento lento de la imagen del
    /// capítulo (el «cachito») y la hoja para elegir.
    /// El «+» de crear algo nuevo (`DSAddTile`): el círculo, sin caja detrás.
    enum AddTile {
        static let circle: CGFloat = 64
    }

    enum HomeChannels {
        static let width: CGFloat = 268, addWidth: CGFloat = 150
        /// En la Mac los canales crecen hasta llenar el renglón (con 268 quedaba un hueco a la derecha; Fernando, 16 nov 2026),
        /// sin pasar de `macMax`.
        static func width(count: Int) -> CGFloat {
            guard WindowMetrics.roomy, count > 0 else { return width }
            let row = WindowMetrics.column.width - 2 * DS.Space.gutter - CGFloat(count) * DS.Space.s2 - addWidth
            return min(macMax, max(width, row / CGFloat(count)))
        }
        static let macMax: CGFloat = 420
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
        /// El muro: ocho columnas (con siete, girado, quedaba una orilla sin pósters) de trece pósters cada vuelta.
        static let coverHeight: CGFloat = 300, coverWall: CGFloat = 828, coverColumns = 8, coverPosters = 96, coverTilt: Double = -10
        static let coverRows = 13, coverWallHeight: CGFloat = 1900
        /// Tope de columnas del muro: en ventana más ancha, columnas más anchas en vez de más (rendimiento en la Mac, 17 nov 2026).
        static let coverMaxColumns = 9
        /// Cada cuánto entra otra columna del muro la primera vez (`MosaicCover`): una por paso, sin trabar el cambio de pestaña.
        static let coverColumnStep: Duration = .milliseconds(45)
        /// En ventana ancha (iPad acostado o grande, Mac) el muro suma columnas del mismo ancho hasta cubrir la ventana (con
        /// las ocho de siempre quedaba una cuña en blanco a la izquierda). Hasta el ancho del iPad de pie, las ocho de siempre.
        /// Inclinado, el muro deja una cuña sin pósters abajo a la izquierda: se cuenta `coverTiltSlack` de más en cada orilla
        /// (Fernando, 22 nov 2026: «un carril adicional a la extrema izquierda en el mosaico»).
        static func coverColumns(forWidth width: CGFloat) -> Int {
            let needed = Int((CGFloat(coverColumns) * (width + 2 * coverTiltSlack) / coverWall).rounded(.up))
            return max(needed, coverColumns)
        }
        static let coverTiltSlack: CGFloat = 140
        static let coverClearAt: Double = 0.25, coverBaseVeil: Double = 0.8, coverBaseAt: Double = 0.6
        /// Cuánto sube el muro (hasta la orilla de la pantalla, detrás del título y la barra: sin corte) y cuánto baja bajo los
        /// círculos; qué tanto se ve hasta arriba y el velo que deja leer el título encima.
        static let coverBleedUp: CGFloat = 900, coverTitleZone: CGFloat = 260, coverBleedDown: CGFloat = 72, coverUnderBar: Double = 0.85, coverTitleVeil: Double = 0.72
        /// Cada columna del muro baja sola, a su ritmo (puntos por segundo, una por columna: ninguna va pareja con su vecina), y
        /// arranca en otra parte de su vuelta (`coverPhaseStep`). Corre solo con la portada a la vista (`coverVisibleFrom`). Lo
        /// mueve Core Animation (`CoreDrift`), no SwiftUI: por eso van en números y no como `Animation`.
        /// «Marea lenta» (Fernando, 1 nov 2026: antes de 7 a 19 y dos columnas se sentían apuradas): casi parejas y despacio, y
        /// una baja mientras la de al lado sube (`coverAlternates`). La diagonal del muro se queda. Un poco más lenta (Fernando,
        /// 2 nov 2026): un cuarto menos (antes de 8 a 9.5).
        static let coverPace: [Double] = [6, 6.75, 6.4, 7.1, 6, 6.75, 6.4, 7.1], coverPhaseStep = 0.37, coverVisibleFrom: Double = 0.1
        static let coverAlternates = true
        static let deckShift: CGFloat = 14, deckTurn: Double = 5, deckBehind: Double = 0.6
        /// La puerta de «Decide por mí» (DM-A, Fernando, 18 nov 2026): el abanico más chico y junto (88 + 2 × 8 = 104 de ancho)
        /// para que el dado con «Decide por mí» y «Tres que caben · Una por una» quepan en un renglón en el 17 Pro (antes 132 de abanico y
        /// 182 de texto: los dos se partían). Si aun así no cabe (SE, letra grande), se achica hasta `doorTitleScale`.
        static let doorPoster: CGFloat = 88, doorShift: CGFloat = 8, doorTitleScale: CGFloat = 0.85
        /// Cuántos pósters lleva el abanico de «¿Qué vemos hoy?» (y cuántos de la portada se saltan para no repetirlos).
        static let matchFan = 3
        /// En la Mac, la puerta de «Decide por mí» lleva a la derecha una tira de más carteles que se desvanece hacia el texto
        /// (a lo ancho, la tarjeta quedaba vacía: Fernando, 16 nov 2026, «hay que pulir el decide por mí»).
        /// La tira crece con la ventana: llena lo que sobra hasta la orilla, como los renglones de al lado (en el ultrawide, con
        /// ocho la tarjeta quedaba media vacía; Fernando, 17 nov 2026: «hay unas que siguen y otras que no»). `DecideStrip` enseña
        /// solo las que caben.
        static let stripPoster: CGFloat = 78, stripFadeFrom: Double = 0.15
        static var stripCount: Int { min(stripMax, max(8, Int(WindowMetrics.column.width * stripShare / (stripPoster + DS.Space.s2)))) }
        /// Hasta la mitad del ancho y 16 carteles: con 36 en el ultrawide muchos se veían vacíos mientras llegaban.
        static let stripShare: CGFloat = 0.5, stripMax = 16
        /// Cuánto la tiñe el color de acento desde el abanico (Fernando, 17 nov 2026: «hazlo más vistoso»; el turquesa es voz).
        static let doorGlow: Double = 0.3
        /// «La temporada»: cuánto la tiñe su color (sus pósters son los de la puerta, `doorPoster`). Un renglón de «Tuyo»:
        /// cuánto asoma cada póster.
        static let seasonGlow: Double = 0.42, rowShift: CGFloat = 14
        /// La puerta grande de un renglón (`ListRow(large:)`, «Lo que ves» en la Mac y el iPad): pósters casi del doble.
        static let largePoster: CGFloat = 92, largeShift: CGFloat = 30
        /// Su ícono, su altura mínima, su anillo del color y cuántos más asoman en la tira de la Mac (17 nov 2026).
        static let seasonIcon: CGFloat = 72, seasonHeight: CGFloat = 168, seasonRing: Double = 0.5, seasonStrip = 7
        /// MO1 · la portada es la puerta del mosaico (Fernando, 13 nov 2026). `doorPull`: cuánto se estira la orilla de arriba
        /// para entrar (más allá de «actualizar», `DS.Refresh.threshold`: lo corto actualiza, lo largo entra). Al abrirse el muro
        /// se endereza, crece `doorGrow` y su velo se aclara `doorUnveil`; el mosaico entra desde `doorEnterScale`, arriba.
        /// La puerta abre más pausada que un cambio normal (23 nov 2026: «que la transición sea más suave»).
        static let doorSeconds = 0.6
        static let doorPull: CGFloat = 150, doorGrow: CGFloat = 0.1, doorUnveil: Double = 0.5, doorEnterScale: CGFloat = 0.96
        /// Tocarla: se hunde a `doorPressed` y se endereza este rato antes de que entre el mosaico. La primera vez (sola, una
        /// vez): espera `doorHintDelay`, se queda derecha `doorHintHold` y regresa.
        static let doorPressed: CGFloat = 0.98, doorLead: Duration = .milliseconds(260)
        /// Cuántas pide la puerta de «Decide por mí» (Inicio y Explorar, la misma): en la Mac, también las de la tira que se asoma.
        static var doorFan: Int { matchFan + (WindowMetrics.roomy ? stripCount : 0) }
        static let doorHintDelay: Duration = .milliseconds(1200), doorHintHold: Duration = .milliseconds(650)
    }

    /// Las tarjetas de Plataformas, Premios y Estudios (Explorar). Aquí y no en Tokens+Screens: ese archivo llegó a su tope.
    enum PlatformFan {
        /// El subrayado de la lista elegida en la página de una plataforma.
        static let tabUnderline: CGFloat = 3
        /// Dos tarjetas y un pedazo de la tercera (como «Próximos estrenos»): en un iPhone de 375 pt las dos de 168 llenaban casi todo
        /// el ancho y dejaban 11 pt a la derecha contra 16 a la izquierda.
        static var width: CGFloat {
            if WindowMetrics.roomy { return maxWidth }
            return min(maxWidth, (WindowMetrics.column.width - DS.Space.gutter - DS.Space.s2 - DS.Poster.peek) / 2)
        }
        /// En la Mac las tarjetas (Plataformas, Premios, Estudios) crecen hasta que `perRow` llenan el renglón, sin pasar de
        /// `maxScale`: con su tamaño de iPhone dejaban media pantalla vacía a la derecha (Fernando, 16 nov 2026).
        /// En ventana muy ancha caben más de `perRow` (si no, topaban en `maxScale` y volvía a quedar hueco a la derecha):
        /// tantas como quepan sin pasar de `maxScale`, y todas crecen lo justo para llegar a la orilla.
        static var scale: CGFloat {
            guard WindowMetrics.roomy else { return 1 }
            let room = WindowMetrics.column.width - 2 * DS.Space.gutter
            let count = max(perRow, Int(ceil((room + DS.Space.s2) / (maxScale * baseWidth + DS.Space.s2))))
            let row = room - CGFloat(count - 1) * DS.Space.s2
            return min(maxScale, max(1, row / (CGFloat(count) * baseWidth)))
        }
        static let perRow = 6, maxScale: CGFloat = 2, baseWidth: CGFloat = 168
        static var maxWidth: CGFloat { baseWidth * scale }
        static var height: CGFloat { 176 * scale }
        static let radius = DS.Radius.xxl
        static var poster: CGFloat { 66 * scale }
        static var posterTop: CGFloat { 26 * scale }
        static let angle: Double = 15
        static var spread: CGFloat { 8 * scale }
        static var lift: CGFloat { 6 * scale }
        static var logo: CGFloat { 34 * scale }
        static var glow: CGFloat { 18 * scale }
        /// El logo redondo con que eliges plataforma (el Top 10 de Inicio): 40 pt, con el anillo en la elegida.
        static var pickLogo: CGFloat { ProcessInfo.processInfo.isiOSAppOnMac ? 60 : WindowMetrics.roomy ? 52 : 40 }   // en la Mac, más grande: con 50 seguían diminutos junto a los pósters
        static let tintTop: Double = 0.42, tintEdge: Double = 0.45
        /// El logo grande de la página de la plataforma y su halo.
        static let headerLogo: CGFloat = 72, headerGlow: CGFloat = 44
        /// El brillo de los números de un ranking.
        static let numberTint: Double = 0.55
    }
}
