import SwiftUI
import OrbitalCore

/// Los tokens de calificar (estrellas, la pastilla del recordatorio y las marcas de cada servicio), aparte de Tokens+Screens para
/// que ninguno pase de su tope.
extension DS {
    /// Calificar como en Trakt (`RatingStars`, `RatingReminder`): las estrellas en ámbar (el color del porqué de las portadas,
    /// como las de Trakt), su tamaño en la ficha y en línea dentro del recordatorio, y el póster chico de la pastilla.
    enum Rating {
        static let filled = DS.warning, empty = DS.textMuted   // las vacías se leen también sobre el vidrio y el arte
        static let star: CGFloat = 26, starInline: CGFloat = 17, gap = DS.Space.s1
        /// Las que se tocan en la pastilla «¿Qué tal…?» y en «Por calificar»: más grandes que las de un renglón y con más aire
        /// entre ellas, para atinarle a la media (Fernando, 13 nov 2026: «es bien difícil atinarle»). `starInline` queda para
        /// las que solo se leen.
        static let starTouch: CGFloat = 24, gapTouch = DS.Space.s2
        /// Lo que el lugar táctil sale a los lados de las estrellas: arrastrar un poco más allá de la última sigue contando.
        static let hitSide = DS.Space.s3
        /// La burbuja que dice cuánto llevas mientras arrastras («3½»), arriba del dedo para que no la tape.
        static let bubbleLift: CGFloat = 34
        /// Lo que se mueve el dedo antes de que cuente como arrastre (menos que eso es un toque).
        static let dragStart: CGFloat = 8
        /// La onda al calificar: cada estrella empieza esto después de la anterior, crece a esta escala y su toque es así de suave.
        static let waveStep: Double = 0.06, wavePop: CGFloat = 1.3, waveIntensity: Double = 0.6
        /// Las estrellas de un capítulo visto (bajo su texto, en la lista de la serie) y el alto que le suman al renglón.
        static let starEpisode: CGFloat = 15, episodeRow: CGFloat = 22
        /// Cuánto se queda el recordatorio a la vista antes de irse solo (vuelve la próxima vez que abras la app).
        static let reminderHold: Duration = .seconds(8)
        /// El velo claro del vidrio de la pastilla, para que se lea igual que la barra de pestañas (vidrio nativo de iOS).
        static let glassTint = DS.paper.opacity(0.12)   // ds-exception: velo del vidrio, medido contra la barra de pestañas
        static let poster: CGFloat = 30, posterAspect: CGFloat = 1.5
    }

    enum RatingBrand {
        static let trakt = Color(red: 0.93, green: 0.11, blue: 0.14)
        /// Los logos, chicos y un poco apagados: son un dato bajo el nombre, no un titular.
        static let markHeight: CGFloat = 14, markOpacity: Double = 0.85, wordmarkScale: CGFloat = 0.68
    }
}
