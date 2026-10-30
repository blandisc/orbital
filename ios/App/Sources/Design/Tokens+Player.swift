import SwiftUI
import OrbitalCore

/// Tokens del reproductor: subtítulos, gestos, el panel de abajo, el iPod, «Viendo en la TV», el toast y los tiempos.
extension DS {
    /// Subtítulos: medidas relativas a la letra o al video (la letra misma sale de Ajustes › Tamaño de subtítulos).
    enum Subtitle {
        static let minFont = CGFloat(DesignTokens.Subtitle.minFont), liftWithControls = CGFloat(DesignTokens.Subtitle.liftWithControls)
        /// Con la píldora «2×» a la vista en horizontal: la línea queda justo por encima de ella (el video va a
        /// sangre y la píldora, dentro del área segura).
        static let liftWithSpeedPill: CGFloat = 120
        static let lineGap = CGFloat(DesignTokens.Subtitle.lineGap), edgeMargin = CGFloat(DesignTokens.Subtitle.edgeMargin)
        static let shadowRadius = CGFloat(DesignTokens.Subtitle.shadowRadius), outlineWidth = CGFloat(DesignTokens.Subtitle.outlineWidth)
        static let raisedMargin = CGFloat(DesignTokens.Subtitle.raisedMargin)
        static let boxPaddingH = CGFloat(DesignTokens.Subtitle.boxPaddingH), boxPaddingV = CGFloat(DesignTokens.Subtitle.boxPaddingV)
        static let boxRadius = CGFloat(DesignTokens.Subtitle.boxRadius)
    }

    /// Brillo, volumen y buscar arrastrando (como Infuse): el umbral que decide el eje (el mismo número que usa
    /// `PlayerGestures`, la aritmética pura) y el tamaño del indicador.
    enum Gesture {
        /// Doble toque: tres zonas parejas (izquierda −10 s, centro pausa, derecha +10 s), como YouTube.
        static let edgeShare: CGFloat = 1.0 / 3.0
        /// Tras un doble toque, cada toque más del mismo lado suma 10 s (+10, +20, +30) mientras no pase este rato.
        static let skipChain: TimeInterval = 0.7
        /// Un arrastre cancelado se limpia este rato después (para que uno normal termine antes con `onEnded`).
        static let cancelSettle: Duration = .milliseconds(80)
        /// ×2: deslizar hacia abajo esta distancia, desde donde apoyaste el dedo, lo fija. Si hasta el borde
        /// de abajo queda menos, se usa ese hueco, pero nunca menos de `fastForwardLockDragMin`. Hacia arriba,
        /// esta misma distancia lo quita al momento (sin esperar a soltar).
        static let fastForwardLockDrag: CGFloat = 60
        /// Lo menos que puede medir el deslizamiento hacia abajo cuando el dedo ya está cerca del borde.
        static let fastForwardLockDragMin: CGFloat = 40
        /// A cuántos segundos del destino ya se da por llegado un salto (el pulgar vuelve a seguir el avance).
        static let seekArrived: Double = 2
        static let axisThreshold = CGFloat(DesignTokens.Gesture.axisThreshold)
        /// Brillo y volumen: el recorrido de 0 a 1 es el alto del video, con tope de esta parte de la pantalla y este mínimo (`PlayerGestures.verticalTravel`).
        static let verticalTravelShare: Double = 0.5, verticalTravelMin: Double = 120
        /// La onda del doble toque: la media luna sale de la orilla y ocupa este tanto del alto del video.
        static let rippleHeight: CGFloat = 1.5
        static let indicatorBarHeight: CGFloat = 120
        static let indicatorBarWidth: CGFloat = 4
        /// Lo que mide el indicador además de la barra (el ícono y su espacio), y lo más corta que puede quedar.
        static let indicatorChrome: CGFloat = 32
        static let indicatorBarMin: CGFloat = 48
        /// Qué tan lejos de la orilla va (en vertical, casi pegado; en horizontal, fuera de la zona de la cámara y los botones).
        static let indicatorInsetPortrait: CGFloat = DS.Space.s3, indicatorInsetLandscape: CGFloat = DS.Space.s8
        /// Un toque de un dedo y uno de dos tan juntos son el mismo toque (s).
        static let twoFingerTapGuard: TimeInterval = 0.35
        /// Un pellizco que termina este rato después de girar el teléfono es el agarre, no un pellizco (no cambia el zoom).
        static let pinchAfterRotationGuard: TimeInterval = 1.0
        /// Un pellizco tiene que durar al menos esto (un toque con dos dedos es instantáneo) y no contar si hubo un toque con dos
        /// dedos en este rato (iOS los mide como si abrieras los dedos).
        static let pinchMinDuration: TimeInterval = 0.15, pinchTapGuard: TimeInterval = 0.6
        /// La burbuja de buscar no se acerca más que esto a los bordes de la pantalla.
        static let seekBubbleSideMargin: CGFloat = 64
        /// De la burbuja (su centro) al borde inferior: justo encima de la barra de avance (que vive dentro del
        /// `padding(DS.Space.s6)` de `controls`, con la hilera de tiempos debajo de la barra).
        static let seekBubbleBottomInset: CGFloat = 120
        /// La píldora «2×» en horizontal, dentro del área segura (igual que los controles): el borde de abajo
        /// queda un `s3` por encima de la hilera de tiempos y de la barra (`padding` de `controls` + `scrubHit`).
        static var fastForwardPillBottomInset: CGFloat {
            DS.Space.s6 + DS.PlayerPanel.scrubHit + DS.PlayerPanel.scrubTimes + DS.Space.s3
        }
        /// «Recortar» en vertical, con los controles a la vista: encima de la barra (aire de abajo, «Saltar intro», la propia
        /// barra y sus tiempos).
        static var fastForwardPillFillInset: CGFloat {
            DS.Space.s8 + DS.Size.touchTarget + DS.Space.s3 + DS.PlayerPanel.scrubHit + DS.PlayerPanel.scrubTimes + DS.Space.s3
        }
    }

    /// El reproductor: el video en vertical, «Audio y subtítulos» (a la derecha en horizontal, bajo el video en vertical) y los controles.
    enum PlayerPanel {
        /// El video en vertical, al arrastrarlo: lo más arriba que sube (debajo de la barra de ✕ y el nombre: botón de 44 y
        /// su aire) y lo que deja libre abajo para los controles (la barra, «Saltar intro», ±10, el botón grande y la pista).
        static let portraitTopClearance: CGFloat = 60, portraitControlsReserve: CGFloat = 260
        /// Lo más cuadrado que se le da espacio en vertical (4:3, la tele de antes); algo más angosto ya va con franjas.
        static let portraitMinAspect: Double = 4.0 / 3.0
        /// La agarradera del video en vertical: la rayita, la franja de abajo que la toma (y lo que se mete sobre el video).
        /// «Audio y subtítulos»: cuántos idiomas de otra versión se ofrecen junto a las pistas de este archivo.
        static let otherVersionsShown = 2
        /// Sin conexión, cuántos idiomas más (de los que sí hay) salen junto a Español e Inglés en Subtítulos.
        static let offlineExtraLanguages = 2
        /// La agarradera, montada en el borde de abajo del video (mitad dentro, mitad fuera): la franja que la toma (dentro del
        /// video, desde abajo, y un poco por fuera) y el aire entre el borde de abajo de la cápsula y el nombre del título.
        static let handleGrab: CGFloat = 40, handleBelow: CGFloat = 12, handleGap: CGFloat = 12, handleWidth: CGFloat = 64, handleHeight: CGFloat = 22, handleBar: CGFloat = 36, handleBarHeight: CGFloat = 5, handleLift: CGFloat = 1.1   // la cápsula de vidrio, su rayita y cuánto crece al arrastrar
        static let handleReach: CGFloat = 12
        /// Desde el borde del video hasta donde empiezan los controles: la mitad de la cápsula que cuelga por fuera más su aire
        /// (antes se contaba el aire desde el borde del video y la cápsula quedaba a 1 pt del nombre, 29 oct).
        static var handleClearance: CGFloat { handleHeight / 2 + handleGap }
        /// Cuántas funciones da el video un brinquito (hacia abajo y de regreso) para enseñar que se mueve, y de qué tamaño (parte del alto).
        static let moveHintTimes = 3
        static let moveNudge: Double = 0.025
        /// Al arrastrarlo: la sombra que lo levanta.
        static let liftShadow: CGFloat = 24
        /// VoiceOver: cuánto sube o baja el video cada vez (parte del alto).
        static let voiceOverStep: Double = 0.1
        /// Subtítulos rápidos: ancho máximo del panel.
        static let dockWidth: CGFloat = 560
        /// iPad de pie, panel fijo: lo que se aparta bajo el video para la barra de avance y sus botones antes de medirlos (al
        /// abrir aún no se han medido).
        static let pinnedControlsMin: CGFloat = 120
        /// Vertical con «Recortar»: cuánto del alto ocupan los controles abajo (los subtítulos suben por encima).
        static let portraitFillControlsShare: CGFloat = 0.3
        /// El globo del «⋯» entra un poco más chico.
        static let lockScale: CGFloat = 0.9
        /// El aviso de pantalla bloqueada: el círculo al que se encoge el candado, y cuánto sube al irse.
        static let lockNoticeIcon: CGFloat = 36, lockNoticeRise: CGFloat = 28
        static let width: CGFloat = 420, radius: CGFloat = 30, rowRadius: CGFloat = 16, icon: CGFloat = 32
        /// En horizontal, lo más que ocupa el panel de la derecha (parte del ancho), para que en iPhone chicos quede video.
        static let widthShare: CGFloat = 0.55
        /// «Episodios»: el ancho de la imagen de cada episodio y qué tan tenue se ve uno que no se puede poner (sin descargar).
        static let episodeThumb: CGFloat = 112, unavailableOpacity = 0.4
        /// «Siguiente» en los controles aparece al llegar a esta parte del episodio (antes no estorba).
        static let nextAt = 0.9
        /// El ancho del nombre del tamaño de subtítulos («Mediano») entre − y +: no brinca al cambiar.
        static let sizeValue: CGFloat = 72
        /// Tamaños de letra de muestra («Aa») para chico, mediano y grande.
        static let sampleSizes: [String: CGFloat] = ["small": 12, "medium": 15, "large": 19]
        /// En vertical: dónde va el centro del video (parte de la altura; se mueve arrastrando) y entre qué límites.
        /// En el iPad de pie (ancho regular) el video abre a media pantalla: arriba dejaba ~600 pt de negro abajo.
        static let regularCenter = 0.5
        static let portraitCenter: CGFloat = -1, portraitCenterRange: ClosedRange<CGFloat> = 0.2...0.62
        /// Mientras no lo mueves (`portraitCenter` < 0), el video queda a esta distancia bajo el área segura: la misma en todos los
        /// iPhone (antes era una fracción del alto y en un Pro Max quedaba cientos de puntos más abajo que en un SE).
        static let portraitTop: CGFloat = 24
        /// El botón de reproducir, más grande que ±10 (lo que más se toca).
        static let playButton: CGFloat = 76, playGlyph: CGFloat = 30, sideButton: CGFloat = 56
        /// ±10: la flecha en círculo, sin fondo (el botón grande es el único con círculo); va en la orilla del video, donde sale la onda del doble toque.
        static let skipGlyph: CGFloat = 32
        /// La barra de avance fina: el riel, la perilla (crece al arrastrar) y el alto que ocupa (se toca en
        /// `DS.Size.touchTarget`: la zona táctil sobresale arriba y abajo).
        static let scrubTrack: CGFloat = 3, scrubTrackActive: CGFloat = 10, scrubHit: CGFloat = 32
        /// El punto de la barra (quieta y arrastrando) y a qué altura sobre la barra va la burbuja del minuto (su centro).
        static let scrubKnob: CGFloat = 12, scrubKnobActive: CGFloat = 22, scrubBubbleLift: CGFloat = 48
        /// Las rayitas del fin de la intro y del inicio de los créditos: su grosor y cuánto sobresalen de la barra; la hilera de
        /// tiempos bajo la barra.
        static let scrubTickWidth: CGFloat = 1.5, scrubTickReach: CGFloat = 3, scrubTimes: CGFloat = 16
        /// Los sustos sobre la barra: el punto de uno fuerte quieta y arrastrando (los leves miden `scareDotMinor` de eso), qué
        /// tan cerca (parte de la película) cuenta como «encima» al arrastrar y el ancho de su nota sobre la burbuja.
        static let scareDot: CGFloat = 7, scareDotActive: CGFloat = 12, scareDotMinor: CGFloat = 0.7
        static let scareReach: Double = 0.006, scareNoteWidth: CGFloat = 220
        /// Cuántas películas con sustos te avisa qué son las marcas (después ya lo sabes).
        static let scareHintTimes = 2
        /// El menú del «⋯»: su ancho.
        static let menuWidth: CGFloat = 272
        /// «Siguiente episodio»: el ancho de la imagen del episodio y el anillo de la cuenta atrás en «Ver ahora».
        static let upNextThumb: CGFloat = 96, ring: CGFloat = 22, ringWidth: CGFloat = 2.5
        /// El degradado oscuro de arriba (detrás del nombre y el episodio), para leerlos sobre un video claro.
        static let topScrimHeight: CGFloat = 170
        /// El cuadro que se guarda al irse a segundo plano (para tenerlo a la vista al volver): lo más grande que se guarda.
        static let frozenFrameMax = CGSize(width: 1920, height: 1080)
    }

    /// «Modo iPod» del reproductor vertical: un iPod Classic blanco o negro (la caja, la pantalla con su marco y la rueda).
    /// Colores fijos a propósito: son los del aparato, no cambian con el modo claro u oscuro (se elige la cara).
    enum IPod {
        // La caja.
        static let whiteTop = Color(red: 0.96, green: 0.96, blue: 0.95), whiteBottom = Color(red: 0.88, green: 0.88, blue: 0.87)
        static let blackTop = Color(red: 0.17, green: 0.17, blue: 0.18), blackBottom = Color(red: 0.05, green: 0.05, blue: 0.06)
        // La pantalla: el marco negro, el fondo claro, la barra «Reproduciendo» y el avance azul.
        static let bezelColor = Color(red: 0.06, green: 0.06, blue: 0.06)
        static let lcd = Color(red: 0.97, green: 0.97, blue: 0.97)
        static let lcdText = Color(red: 0.07, green: 0.07, blue: 0.07), lcdMuted = Color(red: 0.28, green: 0.28, blue: 0.28)
        static let barTop = Color(red: 0.99, green: 0.99, blue: 0.99), barBottom = Color(red: 0.79, green: 0.81, blue: 0.84)
        static let barLine = Color(red: 0.55, green: 0.59, blue: 0.63)
        static let fillTop = Color(red: 0.56, green: 0.76, blue: 0.96), fillBottom = Color(red: 0.18, green: 0.5, blue: 0.82)
        /// La pantalla del iPod negro: todo oscuro (para ver de noche), con las letras claras.
        static let lcdDark = Color(red: 0.09, green: 0.09, blue: 0.1)
        static let lcdDarkText = Color(red: 0.93, green: 0.93, blue: 0.93), lcdDarkMuted = Color(red: 0.66, green: 0.66, blue: 0.68)
        static let barDarkTop = Color(red: 0.24, green: 0.24, blue: 0.26), barDarkBottom = Color(red: 0.12, green: 0.12, blue: 0.13)
        static let barDarkLine = Color(red: 0.3, green: 0.3, blue: 0.32)
        // La rueda: la cara, su orilla, el botón del centro y las letras (MENU, ⏮ ⏭ ▶❚❚), en blanco y en negro.
        static let wheelWhiteTop = Color(red: 1, green: 1, blue: 1), wheelWhiteBottom = Color(red: 0.91, green: 0.91, blue: 0.9)
        static let wheelWhiteEdge = Color(red: 0.8, green: 0.8, blue: 0.79), labelWhite = Color(red: 0.45, green: 0.45, blue: 0.45)
        static let centerWhiteTop = Color(red: 0.92, green: 0.92, blue: 0.91), centerWhiteBottom = Color(red: 0.98, green: 0.98, blue: 0.97)
        static let wheelBlackTop = Color(red: 0.23, green: 0.23, blue: 0.24), wheelBlackBottom = Color(red: 0.13, green: 0.13, blue: 0.14)
        static let wheelBlackEdge = Color(red: 0.03, green: 0.03, blue: 0.03), labelBlack = Color(red: 0.8, green: 0.8, blue: 0.8)
        static let centerBlackTop = Color(red: 0.08, green: 0.08, blue: 0.09), centerBlackBottom = Color(red: 0.18, green: 0.18, blue: 0.19)
        // Medidas: margen a los lados, marco, esquinas, la barra de arriba, lo de abajo del video y la rueda.
        static let inset: CGFloat = 12, bezel: CGFloat = 6, bezelRadius: CGFloat = 14, lcdRadius: CGFloat = 8
        static let statusHeight: CGFloat = 26, infoHeight: CGFloat = 92, progressHeight: CGFloat = 10, line: CGFloat = 1
        /// La rueda nunca baja de este ancho (en veces el del teléfono): hasta ahí puede crecer el video.
        static let wheelMinShare: CGFloat = 0.52
        /// La rueda: qué parte del ancho ocupa, el botón del centro (parte del diámetro) y dónde van las letras (desde la orilla).
        static let wheelShare: CGFloat = 0.74, centerShare: CGFloat = 0.38, labelReach: CGFloat = 0.11
        /// Cada muesca de la rueda (en grados) busca 10 s; girando rápido (muescas a menos de `fastNotch` s), un minuto.
        static let notchDegrees: Double = 30, fastNotch: Double = 0.06, fastStep: Double = 60
        static let menuTracking: CGFloat = 1.5
    }

    /// «Viendo en la TV»: cada cuánto se vuelve a dibujar la barra de avance mientras se interpola entre sondeos.
    enum NowPlaying {
        static let progressTick = DesignTokens.Timing.tick
        /// Opacidad de un botón mientras su acción sigue en vuelo (sin duplicar el toque).
        static let busyOpacity = CGFloat(DesignTokens.Opacity.faint)
    }

    /// Los avisos (`Toast`).
    enum Toast {
        /// El alto de la cápsula de la salida («Deshacer», «Reintentar»).
        static let actionHeight: CGFloat = 32
        /// El borde del que te necesita (ámbar) o del que avisa que algo se perdió (rojo): su color, tenue.
        static let toneStroke = 0.4, strokeWidth: CGFloat = 1
        /// Lo que hay que deslizar hacia abajo para quitarlo, y lo más ancho que se pone (en iPad u horizontal no cruza la pantalla).
        static let swipe: CGFloat = 12, maxWidth: CGFloat = 520
        /// Cuántos avisos esperan detrás del que tiene salida (los de más se descartan: ya no vienen al caso).
        static let queueLimit = 3
        /// Antes de esto (segundos), el aviso de pasar a la TV dice «desde el principio» y no «desde 0:12».
        static let fromStartUnder: Double = 30
    }

    /// Esperas de la interfaz (nanosegundos para `Task.sleep`).
    enum Timing {
        /// Lo que cuenta minutos a la vista («Llevas 12 min»): se vuelve a pintar cada minuto, no antes.
        static let minute: TimeInterval = 60
        /// De vuelta de segundo plano: cada cuánto se mira si el video ya está para quitar el cuadro guardado.
        static let frozenFramePoll: UInt64 = 100_000_000
        /// Cuánto espera una lista abierta (un premio) antes de dar por hecho que no llegará y mostrar el vacío.
        static let listGiveUp: UInt64 = 15_000_000_000
        /// Lo más que el pulgar espera en el destino de un salto antes de volver al avance real.
        static let seekPatience: UInt64 = 4_000_000_000
        /// Cuánto espera una confirmación («¿Ver en la TV?») antes de cerrarse sola.
        static let confirm: UInt64 = 3_500_000_000
        static let controlsHide = UInt64(DesignTokens.Timing.controlsHide * 1e9), banner = UInt64(DesignTokens.Timing.banner * 1e9)
        /// El giro de la pantalla tarda esto en asentarse. (Cuándo sale la carga lo decide `PlayerPresentation`.)
        static let rotationSettle = UInt64(0.5 * 1e9)
        /// Un toque en este rato después de que los controles empezaron a esconderse los vuelve a mostrar.
        static let controlsFadeGrace: TimeInterval = 0.4
        /// Cuánto se queda un aviso con salida («Sigue en tu Orbital · Deshacer», «Bajando · Otra»).
        static let toastAction = UInt64(8 * 1e9)
        static let searchDebounce = UInt64(DesignTokens.Timing.searchDebounce * 1e9), tick = UInt64(DesignTokens.Timing.tick * 1e9)
        static let longPressDelay = DesignTokens.Timing.longPressDelay
        /// ×2: cuánto mantener el dedo en la mitad derecha para que arranque (casi al instante, como YouTube).
        /// Fijarlo es deslizar hacia abajo sin soltar; hacia arriba lo quita y vuelve a la velocidad previa.
        static let fastForwardStart = 0.3
        /// Cada cuánto, como pronto, le pide iOS a la app mirar en segundo plano lo que dejó la TV (iOS decide si y cuándo corre).
        static let inboxRefresh: TimeInterval = 15 * 60
        /// Cada cuánto (como mínimo) iOS despierta la app para ver si un estreno ya se puede ver.
        static let releaseRefresh: TimeInterval = 30 * 60
        /// Revisar estrenos: lo más pronto que se pide la siguiente y cuánto después de que sale un episodio (para que ya tenga fuente).
        static let releaseSoonest: TimeInterval = 15 * 60, releaseAfterAiring: TimeInterval = 15 * 60
        /// La imagen del aviso de estreno: lo más que se espera por ella (en segundo plano el tiempo es poco; sin ella igual se avisa).
        static let releaseImageTimeout: TimeInterval = 5
        /// Al bloquear: la cápsula «Pantalla bloqueada» antes de encogerse.
        static let lockNotice: UInt64 = 1_000_000_000
        /// Lo que duran el encogido y la subida del candado (los mismos segundos que `DS.Motion`).
        static var lockNoticeShrink: UInt64 { UInt64(DS.Motion.lockShrinkDuration * 1_000_000_000) }
        static var lockNoticeRise: UInt64 { UInt64(DS.Motion.lockRiseDuration * 1_000_000_000) }
        /// Tras un toque con la pantalla bloqueada: la cápsula con «Desbloquear» antes de encogerse.
        static let unlockPrompt: UInt64 = 3_000_000_000
        /// Cuánto se queda a la vista el indicador de brillo o volumen tras soltar, antes de desvanecerse.
        static let gestureIndicatorHold = UInt64(DesignTokens.Timing.gestureIndicatorHold * 1e9)
        /// Quieto en el mosaico: a los 30 s el ambiente despierta solo; sobre una pieza, a los 2,2 s cobra vida.
        static let mosaicIdle = UInt64(DesignTokens.Mosaic.idleSeconds * 1e9), mosaicAlive = UInt64(DesignTokens.Mosaic.aliveSeconds * 1e9)
        static let mosaicDrift = UInt64(DesignTokens.Mosaic.driftTick * 1e9)
    }
}
