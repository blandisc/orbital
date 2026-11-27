import SwiftUI
import OrbitalCore

// Tu avatar, el color de cada lista, el control remoto, el mosaico, lo guardado y la cinta (aparte de Tokens+Screens.swift por su presupuesto de 600 renglones).
extension DS {
    /// Tu avatar: en Inicio (junto al saludo) y en Ajustes.
    enum Avatar {
        /// En la Mac crece con la letra (17 nov 2026): de 34 pt salía de ~26 px junto a las pestañas; DK (22 nov) un paso más.
        static let toolbar: CGFloat = ProcessInfo.onMac ? DS.Mac.sized(38) : 34, picker: CGFloat = 64
        /// La esquina de un ícono de app (la curva de iOS: 22.37 % del lado).
        static let iconCorner: CGFloat = 0.2237
    }

    /// El color de cada lista (su ícono en Inicio y Para ti): fijo, el mismo siempre, para encontrarla de un vistazo. Tonos de
    /// brillo parecido para que ninguno grite más que los demás. En claro, el mismo tono más oscuro (`DesignTokens.ListTint`).
    enum ListTint {
        private static func tint(_ name: String) -> Color {
            guard let hex = DesignTokens.ListTint.hex[name] else { return .clear }
            return adaptive(dark: hex.dark, light: hex.light)
        }
        static let watching = tint("watching")   // ámbar
        static let library = tint("library")     // azul cielo
        static let bookmark = tint("bookmark")   // rosa
        static let spark = tint("spark")         // violeta
        static let calendar = tint("calendar")   // verde agua
        static let series = tint("series")       // azul
        static let trend = tint("trend")         // coral
        static let flame = tint("flame")         // naranja
        static let list = tint("list")           // verde
        static let addon = tint("addon")         // lila
        static let chart = tint("chart")         // frambuesa
        static let trophy = tint("trophy")       // oro
    }

    /// El control completo de la TV (`TouchPad`, `RemoteKey`).
    enum Remote {
        /// «Cómo lo ves» (IV-A): cuántas versiones enseña; la tarjeta de lo enfocado (CT-A): el ancho de su póster.
        static let versionsShown = 8, focusPoster: CGFloat = 76
        /// La tarjeta de lo enfocado: la sombra del póster, el desenfoque del arte de fondo y el ancho mínimo de su botón.
        static let focusBlur: CGFloat = 30, focusButton: CGFloat = 96
        /// «Cómo lo ves»: el póster de lo que suena, arriba.
        static let watchPoster: CGFloat = 60
        /// Al tocar: la tecla se hunde a esta escala y la flecha del pad que se mandó crece a esta.
        static let keyPress: CGFloat = 0.94, arrowFlash: CGFloat = 1.3
        /// Desde qué ancho de ventana el control va en un panel fijo a la derecha (iPad horizontal, Mac) en vez de una
        /// tarjeta: el iPad de pie (de 820 a 1024 pt) se queda con la tarjeta, que no aprieta el contenido.
        static let panelWindowWidth: CGFloat = 1000
        /// El ancho del panel: el de un iPhone, para el que está hecho el control.
        static let panelMin: CGFloat = 360, panelIdeal: CGFloat = 390, panelMax: CGFloat = 440
        /// De qué tamaño parte lo que se despliega en el control (los sustos): crece desde arriba a su tamaño.
        static let revealScale: CGFloat = 0.96
        /// Cuánto espera la hoja del control a que su contenido deje de cambiar antes de tomar su nuevo alto (en una sola
        /// animación, en lugar de seguir cada paso).
        static let heightSettle: Double = 0.12
        /// El renglón de la voz (`VoiceRow`): el círculo del micrófono y el alto del renglón abierto. Escuchando y
        /// respondiendo miden lo mismo, así el renglón cambia de alto una vez al abrir y otra al plegarse (no brinca).
        static let voiceMic: CGFloat = 54
        static let voiceOpenHeight: CGFloat = 196
        /// Cuánto se queda abierta la respuesta antes de plegarse sola, y cuánto se queda después como pista («✓ …»).
        static let replyStays: Double = 6, answerHintStays: Double = 10
        /// Varias coincidencias: el ancho de cada tarjeta del carrusel (lo que sobra deja asomar las de los lados) y su póster.
        static let choiceCardShare: CGFloat = 0.84, choicePoster: CGFloat = 84
        /// La línea de tiempo con sustos: alto de la barra, de la marca leve y de la fuerte; el punto donde vas.
        static let timelineBar: CGFloat = 6, scareMark: CGFloat = 12, scareMarkMajor: CGFloat = 20, scareMarkWidth: CGFloat = 3
        static let playhead: CGFloat = 14
        /// Cuántos segundos antes de un susto vibra (si pediste el aviso) y cada cuánto se revisa.
        static let scareLead: Double = 5, scareTick: Double = 0.5
        /// Tras «mantener», cuánto se ignora el toque de soltar.
        static let holdTapWindow: TimeInterval = 0.8
        /// Cuánto se mantiene una tecla para su segunda acción (mantener «Atrás»: al inicio).
        static let holdSeconds: Double = 0.6
        /// La barra del volumen de la TV; con un video (V4-A), de 0 a 200 con el 100 a dos tercios, y el número de ancho fijo.
        static let volumeBar: CGFloat = 6, volumeTop: CGFloat = 200, volumeNormal: CGFloat = 2.0 / 3.0, volumeMarkWidth: CGFloat = 2, volumeMarkHeight: CGFloat = 16, volumeNumberWidth: CGFloat = 44, volumeDash: CGFloat = 4
        /// Alto del pad táctil y de cada tecla.
        static let padHeight: CGFloat = 170, keyHeight: CGFloat = 60
        /// En un teléfono bajito (SE) el pad y las teclas se encogen: «Atrás» y «Escribir en la TV» caben sin deslizar.
        static let padHeightShort: CGFloat = 116, keyHeightShort: CGFloat = 46, shortScreen: CGFloat = 700
        /// El alto fijo del ícono de una tecla: los nombres quedan en el mismo renglón aunque los símbolos midan distinto.
        static let keyIcon: CGFloat = 24
        static var isShortScreen: Bool { WindowMetrics.size.height < shortScreen }
        /// Aire entre los grupos del control: más junto en pantallas cortas (revisión 2 del 11 nov: en el SE «Escribir en la TV»
        /// quedaba cortado abajo).
        static var groupGap: CGFloat { isShortScreen ? DS.Space.s2 : DS.Space.s4 }
        static var blockGap: CGFloat { isShortScreen ? DS.Space.s2 : DS.Space.s6 }
        /// Lo que la hoja flotante de iOS 26 se come abajo (su margen y esquinas): sin esto, la hoja completa medía justo lo
        /// del contenido y «Escribir en la TV» quedaba cortado contra la orilla.
        static let sheetAllowance: CGFloat = DS.Space.s6
        /// El alto de una tecla y del pad según el teléfono.
        static var keyHeightFitted: CGFloat { isShortScreen ? keyHeightShort : keyHeight }
        /// Lo que mide el pad con su fila de teclas: el lugar mínimo que guardan los botones del reproductor (y los de en
        /// vivo) para que el cambio al pad no cambie el alto de la hoja.
        static var padModeHeight: CGFloat { padHeightFitted + DS.Space.s4 + keyHeightFitted }
        /// El cambio entre los botones y el pad: lo que se va se encoge un poco y se desenfoca mientras lo otro crece.
        static let morphScale: CGFloat = 0.94, morphBlur: CGFloat = 6
        /// En un SE la hoja estirada puede llegar arriba del todo (opaca) para que quepa el control completo.
        static var maxShareFitted: CGFloat { isShortScreen ? 1 : maxShare }
        static var padHeightFitted: CGFloat { isShortScreen ? padHeightShort : max(padHeight, WindowMetrics.size.height * padShare) }
        /// Qué parte del alto de la pantalla toma el pad (en un iPhone grande crece).
        static let padShare: CGFloat = 0.2
        /// Lo más que crece la hoja estirada (la de toda hoja alta).
        static let maxShare = DS.Sheet.maxShare
        /// Cuánto hay que deslizar para una flecha (y cada cuánto se repite al seguir deslizando).
        static let swipeStep: CGFloat = 56
        /// Inercia del pad: desde qué velocidad al soltar (pt/s) sigue solo, cuántos pt/s vale cada flecha más, cuántas
        /// (mínimo y máximo), la pausa antes de la primera (s) y cuánto crece cada pausa. Menos sensible desde el 25 nov 2026
        /// (Fernando: «le das tantito y ¡fum!»): antes un deslizón normal ya seguía solo, con 3 a 15 flechas de más.
        static let glideSpeed: CGFloat = 1400, glideSpeedPerArrow: CGFloat = 700, glideMin = 1, glideMax = 6
        static let glideFirstGap: Double = 0.07, glideSlowdown: Double = 1.22
        /// Lo que se puede mover el dedo y seguir contando como toque (A).
        static let tapSlop: CGFloat = 10
        /// La luz bajo el dedo en el pad.
        static let touchGlow: CGFloat = 72
        /// Cuánto se espera a que dejes de escribir para mandar el texto a la TV.
        static let typeDebounce = UInt64(0.35 * 1e9)
        /// El panel del iPad con la tele en reposo: cuántos de «Seguir viendo» enseña arriba del control (CT2).
        static let panelContinueCount = 4
    }

    /// El mosaico de «Para ti» (equivalente a `foryou-mosaic` en la TV): columnas, cuánto crece la enfocada
    /// y las esperas de su ambiente y «cobra vida».
    enum Mosaic {
        static let columnsPortrait = DesignTokens.Mosaic.columnsPortrait, columnsLandscape = DesignTokens.Mosaic.columnsLandscape
        static let columnsCompact = DesignTokens.Mosaic.columnsCompact, compactWidth = CGFloat(DesignTokens.Mosaic.compactWidth)
        static let uniform = DesignTokens.Mosaic.uniform
        /// Ventana ancha (iPad, Mac): tantas columnas de este ancho como quepan, no pósters gigantes. De 170 a 210 (Fernando,
        /// 22 nov 2026: «en mosaico… menos hileras un poquito más anchas»).
        static let wideColumn: CGFloat = 210
        static let growRatio = CGFloat(DesignTokens.Mosaic.growRatio)
        static let driftTick = DesignTokens.Mosaic.driftTick
        static let driftPerSecond = CGFloat(DesignTokens.Mosaic.driftPerSecond)
        static let focusedRowRatio = DesignTokens.Mosaic.focusedRowRatio
        /// Cuánto hay que deslizar de lado para regresar a Explorar.
        static let swipeBack: CGFloat = 80
    }

    /// Biblioteca › Guardado en pestañas (GD2, Fernando, 13 nov 2026: «Pestañas, como la tele»; reemplaza el tablero G2-A).
    enum Saved {
        /// Tus listas en mosaico: dos columnas en el iPhone; en ventana ancha (iPad, Mac), las que quepan de `listTileMin`.
        static let listColumns = 2
        static let listTileMin: CGFloat = 180
        /// TL-A (Fernando, 23 nov 2026): en Explorar, todas tus listas a la vez en cuadrícula, con portadas en rectángulo 4:3
        /// (aprovechan el ancho sin que dos columnas llenen la pantalla).
        static let gridAspect: CGFloat = 4 / 3
        static func listColumns(forWidth width: CGFloat) -> Int {
            max(listColumns, Int((width - DS.Space.gutter * 2 + DS.Space.s2) / (listTileMin + DS.Space.s2)))
        }
        /// La portada de una lista, cuadrada (dos columnas sin que cada una ocupe media pantalla): cuatro pósters en 2 × 2, dos
        /// lado a lado o uno entero (nunca un hueco).
        static let coverPosters = 4, coverAspect: CGFloat = 1
    }

    /// El listón de la esquina (`DSCornerRibbon`): la caja que recorta la esquina, el largo de la banda, dónde cruza su
    /// centro (en cada eje, desde la esquina) y el interletrado del texto en mayúsculas; el de siempre y el compacto (los
    /// pósters de 50 pt del widget). Los dos con el mismo giro y el mismo brillo.
    enum Ribbon {
        struct Size { let corner: CGFloat, length: CGFloat, center: CGFloat }
        static let regular = Size(corner: 60, length: 104, center: 22)
        static let compact = Size(corner: 42, length: 72, center: 16)   // OI-5: «Nuevo» en 12 pt cabe en la banda
        static let angle: Double = -45, shine: Double = 0.28
    }
}
