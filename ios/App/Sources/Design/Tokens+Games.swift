import SwiftUI

/// Las medidas de los juegos en el iPhone (Ultra; `docs/producto/emulacion-iphone/plan-pantallas.html`): portadas, mosaicos de
/// consola, la ficha y los botones en pantalla. Todo lo demás sale de los tokens de siempre.
extension DS {
    enum Games {
        /// La caja de un juego (3:4, como las cajas físicas) y la tarjeta ancha de «Recientes».
        static let boxAspect: CGFloat = 3.0 / 4.0
        static let wideAspect: CGFloat = 16.0 / 10.0
        /// El ancho de una caja en las tiras (Favoritos) y de la tarjeta ancha (Recientes).
        static let boxWidth: CGFloat = 104
        static let wideWidth: CGFloat = 248
        /// La rejilla de una consola: lo mínimo por caja; caben más en el Duo abierto.
        static let gridMin: CGFloat = 104
        /// Los mosaicos de «Tus consolas»: lo mínimo de ancho y su alto.
        static let consoleMin: CGFloat = 150
        static let consoleHeight: CGFloat = 112
        /// Las portadas encimadas de cada consola: el ancho de cada una y cuánto se encima a la anterior.
        static let doorCover: CGFloat = 30, doorOverlap: CGFloat = 10
        /// La portada de la ficha: su alto, parte del ancho de la columna, con tope para el Duo abierto.
        static let heroShare: CGFloat = 0.62
        static let heroMax: CGFloat = 420
        /// Lo apagado de un juego que todavía no corre (E6-A).
        static let unavailable = DS.Opacity.dimmed
        /// El punto de cómo va tu partida.
        static let statusDot: CGFloat = 8

        /// Los botones en pantalla (sin mando, E2-A): el tamaño de cada uno, la cruceta, la palanca y qué tan transparentes.
        static let padButton: CGFloat = 52
        static let padDpad: CGFloat = 124
        static let padStick: CGFloat = 92
        static let padShoulder = CGSize(width: 76, height: 34)
        static let padSeeThrough = 0.45
        /// La pausa: su ancho máximo y la parte de la mitad de abajo que ocupa en el Duo medio abierto.
        static let pauseWidth: CGFloat = 380
        /// El juego de una portátil parado: su proporción (GBA 3:2) y la de cada pantalla del DS (4:3).
        static let gbaAspect: CGFloat = 3.0 / 2.0
        static let dsAspect: CGFloat = 4.0 / 3.0
        static let tvAspect: CGFloat = 16.0 / 9.0
        /// Parado, lo más que ocupa el juego del alto (las dos pantallas del DS); lo demás es para los botones.
        static let uprightGameShare: CGFloat = 0.6
        /// Cuánto se queda el aviso al salir de un juego (P23) y el de «Se ve mejor con el Duo abierto» (E5-A).
        static let exitNoteFor: Duration = .seconds(4), outerNoticeFor: Duration = .seconds(3)
        /// Sin motores todavía: lo que tarda en «traer tu partida» y cada paso de la bajada de muestra.
        static let demoLaunch: Duration = .milliseconds(1500), demoDownloadStep: Duration = .milliseconds(150)
    }
}
