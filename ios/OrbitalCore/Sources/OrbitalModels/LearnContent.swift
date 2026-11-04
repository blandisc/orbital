import Foundation

/// «Aprende Orbital», versión final (Fernando, 4 nov 2026: «que no sean tantas, pero que haya buen contenido»; revisión de un
/// director de contenido visual, `docs/producto/guia-aprende/historias-contenido.html`). Seis historias por lo que quieres
/// lograr, cada una con el mismo arco: gancho → cómo funciona → el gesto → el truco → un botón para probarlo. Cada tarjeta es
/// una escena: la pantalla de la app en miniatura, un dedo fantasma que hace el gesto y el resultado ocurriendo («se ve, no
/// se explica»). Los textos son la clave del catálogo (`Localizable.xcstrings`). Palabras de Real-Debrid: «nube» (RX4-A).
public struct LearnStory: Sendable, Identifiable, Equatable {
    /// Las escenas (cada una la dibuja `StorySceneView` en la app).
    public enum Scene: String, Sendable, Equatable {
        // H1 · Ver al instante
        case titlePlay, versionLight, storageStill, payPlans, twoPhones
        // H2 · En tu idioma
        case typedVersion, languageOrder, languageDrag, versionsSheet, cloudRequest
        // H3 · Encontrar qué ver
        case mosaicDrift, mosaicZoom, deckSwipe, decideShuffle, filterTiles
        // H4 · Ver a tu manera
        case playerBare, playerDoubleTap, playerPinch, playerLock, downloadRing, nextEpisode
        // H5 · No perder el hilo
        case handoff, becauseRow, lockScreenAlert, releaseCalendar, alertToggles, yearCount
        // H6 · Tu TV
        case remoteFocus, sendToTV, continueHere, voiceAsk
    }

    /// «El truco»: lo que pocos saben (la tarjeta más larga de cada historia). «Tu turno»: la historia se detiene y la escena
    /// acepta tu gesto de verdad; si en unos segundos no lo haces, el dedo fantasma lo hace por ti.
    public enum Mark: Sendable, Equatable { case none, trick, turn }

    public struct Card: Sendable, Equatable {
        public var scene: Scene
        public var title: String
        public var line: String
        /// Cuánto dura (el ritmo cambia dentro de cada historia: una rápida, una larga para el truco).
        public var seconds: Double
        public var mark: Mark = .none
    }

    /// Adónde lleva el botón de la última tarjeta.
    public enum Destination: String, Sendable, Equatable {
        case connectDebrid, renewDebrid, connectTrakt, advancedSearch, explore, decide, downloads, watching, calendar, tv, languages
    }

    /// Cuándo tiene sentido la historia.
    public enum Needs: Sendable, Equatable { case always, tv }

    public var id: String
    public var title: String
    public var symbol: String
    /// El color de la historia (su ícono y el tinte leve de su fondo): una clave de `DS.ListTint`.
    public var tint: String
    public var cards: [Card]
    public var action: (title: String, destination: Destination)?
    public var needs: Needs = .always

    public static func == (a: LearnStory, b: LearnStory) -> Bool { a.id == b.id && a.cards == b.cards }
}

public enum LearnContent {
    public static let instant = LearnStory(id: "instant", title: "Ver al instante", symbol: "cloud.fill", tint: "flame", cards: [
        .init(scene: .titlePlay, title: "Toca y ya", line: "Sin descargar, sin esperar.", seconds: 5),
        .init(scene: .versionLight, title: "La nube lo tiene", line: "Real-Debrid guarda el video; Orbital lo encuentra.", seconds: 4),
        .init(scene: .storageStill, title: "Tu iPhone, igual", line: "Se ve desde la nube, no ocupa espacio.", seconds: 3),
        .init(scene: .payPlans, title: "Desde unos 3 €", line: "Por 15 días, y no se renueva solo.", seconds: 5, mark: .trick),
        .init(scene: .twoPhones, title: "Una cuenta, una persona", line: "Si dos la usan a la vez, se corta.", seconds: 4),
    ], action: ("Conectar Real-Debrid", .connectDebrid))

    public static let language = LearnStory(id: "language", title: "En tu idioma", symbol: "character.bubble.fill", tint: "watching", cards: [
        .init(scene: .typedVersion, title: "Habla como tú", line: "«Ver» elige tu idioma y tu calidad.", seconds: 4),
        .init(scene: .languageOrder, title: "Tu orden manda", line: "Arranca con el primero que haya.", seconds: 4),
        .init(scene: .languageDrag, title: "Arrastra para cambiar", line: "Mantén presionado y súbelo.", seconds: 5, mark: .turn),
        .init(scene: .versionsSheet, title: "¿Otra? Toca «Versión»", line: "Calidad, idioma y si ya está lista.", seconds: 4),
        .init(scene: .cloudRequest, title: "Pídela a la nube", line: "Te avisamos cuando esté.", seconds: 6, mark: .trick),
    ], action: ("Ordenar tus idiomas", .languages))

    public static let discover = LearnStory(id: "discover", title: "Encontrar qué ver", symbol: "sparkles", tint: "spark", cards: [
        .init(scene: .mosaicDrift, title: "¿No sabes qué ver?", line: "Orbital te propone, tú eliges.", seconds: 4),
        .init(scene: .mosaicZoom, title: "Un toque acerca", line: "El segundo abre la ficha.", seconds: 5, mark: .turn),
        .init(scene: .deckSwipe, title: "Desliza el mazo", line: "No a un lado, sí al otro.", seconds: 3),
        .init(scene: .decideShuffle, title: "Decide por mí", line: "Tres carteles, cada uno con su porqué.", seconds: 5),
        .init(scene: .filterTiles, title: "Junta filtros", line: "Comedias de los 90, en Netflix, con más de 7.", seconds: 6, mark: .trick),
    ], action: ("Abrir Explorar", .explore))

    public static let watch = LearnStory(id: "watch", title: "Ver a tu manera", symbol: "hand.tap.fill", tint: "library", cards: [
        .init(scene: .playerBare, title: "Sin botones", line: "El reproductor responde a tus dedos.", seconds: 3),
        .init(scene: .playerDoubleTap, title: "Doble toque: 10 s", line: "Cada toque extra suma otros 10.", seconds: 5, mark: .turn),
        .init(scene: .playerPinch, title: "Pellizca y llena", line: "Ciérralos para verla completa.", seconds: 3),
        .init(scene: .playerLock, title: "El candado", line: "En «Más». Nada la toca.", seconds: 4),
        .init(scene: .downloadRing, title: "Para el avión", line: "Descarga y sigue sin internet.", seconds: 5),
        .init(scene: .nextEpisode, title: "El siguiente, solo", line: "Al terminar uno, baja el que sigue.", seconds: 4, mark: .trick),
    ], action: ("Abrir Descargas", .downloads))

    public static let thread = LearnStory(id: "thread", title: "No perder el hilo", symbol: "arrow.triangle.2.circlepath", tint: "calendar", cards: [
        .init(scene: .handoff, title: "Sigue en el minuto", line: "Empieza aquí, termina en otro aparato.", seconds: 5),
        .init(scene: .becauseRow, title: "Trakt lo recuerda", line: "Gratis: lo visto, tu lista, dónde ibas.", seconds: 4),
        .init(scene: .lockScreenAlert, title: "Sale hoy", line: "Sigue una serie y te avisamos.", seconds: 5),
        .init(scene: .releaseCalendar, title: "Tu mes de estrenos", line: "En Inicio, el calendario.", seconds: 3),
        .init(scene: .alertToggles, title: "Tú decides cuáles", line: "En Ajustes › Avisos.", seconds: 3),
        .init(scene: .yearCount, title: "Tu año, en números", line: "Lo que ves y tu Wrapped.", seconds: 6, mark: .trick),
    ], action: ("Conectar Trakt", .connectTrakt))

    public static let tv = LearnStory(id: "tv", title: "Tu TV", symbol: "tv.fill", tint: "series", cards: [
        .init(scene: .remoteFocus, title: "El control eres tú", line: "Maneja la TV y háblale.", seconds: 4),
        .init(scene: .sendToTV, title: "«Ver en la TV»", line: "Desde cualquier ficha, un toque.", seconds: 4),
        .init(scene: .continueHere, title: "Sigue aquí", line: "Pasa al iPhone en el mismo minuto.", seconds: 4),
        .init(scene: .voiceAsk, title: "Háblale", line: "«Pon la siguiente de The Bear».", seconds: 5, mark: .trick),
    ], action: ("Conectar tu TV", .tv), needs: .tv)

    /// Todas, en el orden de Ajustes › Aprende Orbital.
    public static let all: [LearnStory] = [instant, language, discover, watch, thread, tv]
}
