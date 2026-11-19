import SwiftUI

/// Las lecciones de Aprende (AF1-B · AF3-B, 19 nov 2026; prototipo en docs/producto/aprende-a-fondo-2026-11-19/prototipo/):
/// el lienzo de sus escenas, las piezas dibujadas y el ritmo. Medidas del lienzo de 402 × 330 (se escala al ancho).
extension DS {
    enum Lesson {
        /// El lienzo de las escenas (el ancho de un iPhone 17 Pro): todo lo de adentro se mide en estos puntos.
        static let canvas = CGSize(width: 402, height: 330)
        /// Lo más ancha que crece la escena (iPad, Mac): una columna, como la guía.
        static var sceneMax: CGFloat { Mac.sized(460) }
        /// El reloj de la escena se detiene un poco después de su último movimiento (no repinta una escena quieta).
        static let settleAfter = 0.6
        /// El póster: su esquina en proporción del ancho (como `DS.Radius.logoShare`; nunca menos de `DS.Radius.xs`).
        static let posterShare: CGFloat = 0.06
        /// El dedo fantasma: una yema translúcida con su borde; al tocar se hunde y suelta un anillo turquesa.
        static let finger: CGFloat = 44, fingerFill = 0.32, fingerRim = 0.6, fingerOpacity = 0.9, fingerPress: CGFloat = 0.18
        static let ring: CGFloat = 12, ringOpacity = 0.35
        /// Los aparatos dibujados: el marco, la esquina del iPhone en proporción de su ancho y la TV con su cuello y su base.
        static let bezel: CGFloat = 5, phoneCorner: CGFloat = 0.2, padCorner: CGFloat = 0.09
        static var deviceRim: Color { DS.ink500 }
        static let tvCorner: CGFloat = 8, tvNeck: CGFloat = 12, tvBase: CGFloat = 64, tvBaseHeight: CGFloat = 4
        /// Las piezas de la app en miniatura: el chip flotante, el aviso de arriba y los renglones de una tarjeta.
        static let chipFill = 0.92
        static let noteIcon: CGFloat = 34, noteHeight: CGFloat = 60
        static let row: CGFloat = 52
        /// «¿Qué veo hoy?»: el alto de un filtro.
        static let filterChip: CGFloat = 38
        /// «En tu idioma»: un idioma de tu lista, el círculo con su lugar, y el panel de audio y subtítulos con sus opciones.
        static let languageRow: CGFloat = 50, placeDot: CGFloat = 22, panel: CGFloat = 170, panelRow: CGFloat = 32, panelHeader: CGFloat = 14
        /// Los idiomas de respaldo (2.º y 3.º): un poco atrás del primero, sin verse «no disponibles».
        static let backup = 0.8
        static let tight: CGFloat = 2
        static let progress: CGFloat = 3, trackOpacity = 0.25
        /// La barra de un video se separa de sus orillas en esta fracción del video.
        static let barShare: CGFloat = 0.05
        static let dash: [CGFloat] = [4, 6]
        /// «Pruébalo»: el anillo que late sobre lo que hay que tocar (hasta que lo tocas).
        static let tryRing: CGFloat = 2, tryPulse = 1.4
        /// El latido del anillo: va y viene sin parar (nada con «Reducir movimiento»).
        static func pulse(_ reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: tryPulse / 2).repeatForever(autoreverses: true)
        }
        /// La página de una lección: el aire entre la escena y el texto, y cómo entra cada paso.
        static let textRise: CGFloat = 14
        /// Cuánto se corre de lado la pantalla que entra (hacia donde avanzas).
        static let pageShift: CGFloat = 12
        /// El texto llega cuando la escena ya arrancó: el renglón turquesa a los 0.12 s y cada línea 0.04 s después (todo a la vista antes de medio segundo).
        static let textAt = 0.12, textStep = 0.04
        /// La fila de una lección en Aprende: su ícono.
        static let rowIcon: CGFloat = 36
    }
}
