import Foundation

/// «Aprende Orbital» (G3, Fernando, 3 nov 2026): las historias, como datos. Cada una tiene de 3 a 5 tarjetas con una de las
/// cinco plantillas (portada, tres pasos, gesto, antes y ahora, botón final) y una idea por tarjeta. Los textos son la clave
/// del catálogo (`Localizable.xcstrings`), como los de la pantalla. Palabras de Real-Debrid: «nube» (RX4-A).
public struct LearnStory: Sendable, Identifiable, Equatable {
    public enum Template: Sendable, Equatable {
        /// El planeta chico y una frase.
        case cover
        /// Los tres pasos de la nube (`DebridFlowStrip`).
        case threeSteps
        /// Una mano fantasma repite el gesto dos veces sobre el símbolo.
        case gesture(symbol: String, motion: Motion)
        /// Un deslizador que se mueve solo entre dos estados.
        case beforeAfter(before: String, after: String)
        /// El símbolo grande en su color.
        case symbol(String)
    }

    public enum Motion: Sendable, Equatable { case tap, doubleTap, swipeUp, swipeSide, pinch, hold }

    public struct Card: Sendable, Equatable {
        public var template: Template
        public var title: String
        public var body: String
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
    /// El color de su ícono: una clave de `DS.ListTint` («flame», «chart»…).
    public var tint: String
    public var cards: [Card]
    public var action: (title: String, destination: Destination)?
    public var needs: Needs = .always

    public static func == (a: LearnStory, b: LearnStory) -> Bool { a.id == b.id && a.cards == b.cards }
}

public enum LearnContent {
    public static let debrid = LearnStory(id: "debrid", title: "Real-Debrid", symbol: "cloud.fill", tint: "flame", cards: [
        .init(template: .cover, title: "Ver aquí mismo, sin esperar", body: "Real-Debrid es un servicio de pago que guarda los videos en su nube."),
        .init(template: .threeSteps, title: "Así funciona", body: "Orbital la encuentra, Real-Debrid la consigue en su nube y la ves al instante."),
        .init(template: .symbol("iphone"), title: "No ocupa espacio", body: "El video llega desde la nube mientras lo ves. Tu iPhone no guarda nada."),
        .init(template: .symbol("person.fill"), title: "Una cuenta por persona", body: "Si dos la usan a la vez, Real-Debrid la corta. Cada quien con la suya."),
    ], action: ("Conectar Real-Debrid", .connectDebrid))

    public static let pay = LearnStory(id: "pay", title: "Cómo pagar", symbol: "creditcard.fill", tint: "watching", cards: [
        .init(template: .cover, title: "Cómo pagar y renovar", body: "Se paga en la página de Real-Debrid, por adelantado y por días."),
        .init(template: .symbol("calendar"), title: "Desde unos 3 € cada 15 días", body: "Eliges cuántos días quieres. El precio lo confirma su página."),
        .init(template: .symbol("bell.badge.fill"), title: "No se renueva solo", body: "Orbital te avisa antes de que se acabe, y cuando vence te dice cómo renovar."),
    ], action: ("Abrir Real-Debrid", .renewDebrid))

    public static let trakt = LearnStory(id: "trakt", title: "Trakt", symbol: "checkmark.seal.fill", tint: "chart", cards: [
        .init(template: .cover, title: "Lo que ves, en todos tus aparatos", body: "Trakt guarda dónde te quedaste, lo que ya viste y tu lista. Es gratis."),
        .init(template: .symbol("arrow.triangle.2.circlepath"), title: "Sigue donde ibas", body: "Empieza en el iPhone y sigue en otro aparato, justo en el minuto."),
        .init(template: .symbol("sparkles"), title: "Mejores recomendaciones", body: "Con tu historial, «Porque viste» y Para ti aciertan más."),
    ], action: ("Conectar Trakt", .connectTrakt))

    public static let advanced = LearnStory(id: "advanced", title: "Búsqueda avanzada", symbol: "slider.horizontal.3", tint: "spark", cards: [
        .init(template: .cover, title: "Junta filtros", body: "Comedias de los 90, en Netflix, con más de 7. Todo a la vez."),
        .init(template: .gesture(symbol: "slider.horizontal.3", motion: .tap), title: "Arriba de todo en Buscar", body: "Los cuadros de filtros: toca uno para empezar y suma los que quieras."),
        .init(template: .beforeAfter(before: "Todo", after: "Lo tuyo"), title: "Cada filtro achica la lista", body: "Género, año, calificación, plataforma e idioma. Quita uno y vuelve a crecer."),
    ], action: ("Probar la búsqueda avanzada", .advancedSearch))

    public static let explore = LearnStory(id: "explore", title: "Explorar y Decide", symbol: "sparkles", tint: "bookmark", cards: [
        .init(template: .cover, title: "Para cuando no sabes qué ver", body: "Explorar te enseña lo que va contigo, en un mosaico que se mueve."),
        .init(template: .gesture(symbol: "square.grid.2x2.fill", motion: .tap), title: "Toca para acercar", body: "Un toque agranda un póster; el segundo abre su ficha."),
        .init(template: .gesture(symbol: "rectangle.stack.fill", motion: .swipeSide), title: "¿Qué vemos hoy?", body: "Elige un ánimo y desliza el mazo: a un lado lo que no, al otro lo que sí."),
        .init(template: .symbol("shuffle"), title: "Decide por mí", body: "Tres carteles con su porqué. ¿Ninguno? «Barajar» y salen otros."),
    ], action: ("Abrir Explorar", .explore))

    public static let versions = LearnStory(id: "versions", title: "Versiones", symbol: "play.rectangle.fill", tint: "series", cards: [
        .init(template: .cover, title: "«Ver» elige por ti", body: "Busca la mejor versión en tu idioma y con la calidad que pediste, y arranca."),
        .init(template: .gesture(symbol: "list.bullet", motion: .tap), title: "¿Otra? Toca «Versión»", body: "Ves todas: calidad, idioma y si ya está en la nube."),
        .init(template: .beforeAfter(before: "Por pedir", after: "Al instante"), title: "Pedir a la nube", body: "Si dice «Por pedir», tócala: la nube la baja y te avisamos cuando esté."),
    ])

    public static let noVersions = LearnStory(id: "no-versions", title: "Sin versiones", symbol: "exclamationmark.bubble.fill", tint: "trend", cards: [
        .init(template: .cover, title: "Cuando no hay versiones", body: "Pasa con estrenos muy nuevos o títulos raros. No es tu internet."),
        .init(template: .symbol("clock.arrow.circlepath"), title: "Prueba mañana", body: "Las versiones aparecen solas con los días. Guárdala en tu lista para no perderla."),
        .init(template: .symbol("tv"), title: "O mírala en tu plataforma", body: "En la ficha, «Dónde verla» dice en cuál de tus plataformas está."),
    ])

    public static let player = LearnStory(id: "player", title: "El reproductor", symbol: "hand.tap.fill", tint: "library", cards: [
        .init(template: .cover, title: "Todo con los dedos", body: "Sin buscar botones: el reproductor responde a gestos."),
        .init(template: .gesture(symbol: "goforward.10", motion: .doubleTap), title: "Doble toque a los lados", body: "Adelanta o regresa 10 segundos. Cada toque más del mismo lado suma otros 10."),
        .init(template: .gesture(symbol: "arrow.up.left.and.arrow.down.right", motion: .pinch), title: "Pellizca para llenar", body: "Abre los dedos para llenar la pantalla; ciérralos para verla completa."),
        .init(template: .gesture(symbol: "lock.fill", motion: .hold), title: "El candado", body: "En «Más», bloquea la pantalla para que nada la toque mientras ves."),
    ])

    public static let downloads = LearnStory(id: "downloads", title: "Descargas", symbol: "arrow.down.circle.fill", tint: "calendar", cards: [
        .init(template: .cover, title: "Para ver sin internet", body: "«Descargar» guarda el video en tu iPhone, para el avión o la carretera."),
        .init(template: .beforeAfter(before: "En la nube", after: "En el iPhone"), title: "La nube no es lo mismo", body: "Lo que pides a la nube está en Real-Debrid; lo descargado vive en tu iPhone."),
        .init(template: .symbol("forward.end.fill"), title: "El siguiente, solo", body: "Al terminar un episodio, Orbital puede bajar el siguiente por ti."),
    ], action: ("Abrir Descargas", .downloads))

    public static let alerts = LearnStory(id: "alerts", title: "Estrenos", symbol: "calendar", tint: "calendar", cards: [
        .init(template: .cover, title: "Avisos y estrenos", body: "Sigue una serie y te avisamos cuando salga su episodio."),
        .init(template: .symbol("calendar"), title: "El calendario", body: "En Inicio, el calendario junta los estrenos del mes de lo que sigues."),
        .init(template: .symbol("bell.fill"), title: "Tú eliges de cuáles", body: "En Ajustes › Avisos decides de qué series te llegan."),
    ], action: ("Ver el calendario", .calendar))

    public static let watching = LearnStory(id: "watching", title: "Lo que ves", symbol: "chart.bar.fill", tint: "watching", cards: [
        .init(template: .cover, title: "Tu año en películas y series", body: "Horas, rachas, géneros y lo que más viste."),
        .init(template: .gesture(symbol: "play.square.stack.fill", motion: .tap), title: "Tu Wrapped", body: "Como estas historias: tu semana, tu mes o tu año, para compartir."),
    ], action: ("Abrir Lo que ves", .watching))

    public static let tv = LearnStory(id: "tv", title: "Tu TV", symbol: "tv.fill", tint: "series", cards: [
        .init(template: .cover, title: "Tu iPhone, el control de la TV", body: "Con Orbital en la TV, el iPhone la maneja y le habla."),
        .init(template: .gesture(symbol: "tv", motion: .tap), title: "«Ver en la TV»", body: "Desde cualquier ficha, mándala a la TV con un toque."),
        .init(template: .gesture(symbol: "iphone", motion: .swipeUp), title: "Sigue aquí", body: "Lo que suena en la TV pasa al iPhone en el mismo minuto."),
    ], action: ("Conectar tu TV", .tv), needs: .tv)

    /// Tus idiomas (Fernando, 4 nov 2026, con la sesión de Real-Debrid): los textos son los de Ajustes › Tus idiomas y la TV.
    public static let languages = LearnStory(id: "languages", title: "Tus idiomas", symbol: "character.bubble.fill", tint: "chart", cards: [
        .init(template: .cover, title: "Tus idiomas", body: "En este orden busca versiones y elige con cuál arranca. Si no hay en el primero, prueba el siguiente."),
        .init(template: .beforeAfter(before: "Latino", after: "Idioma original"), title: "Con este arranca si lo hay",
              body: "Por omisión: latino, el idioma original, inglés y castellano. Arrastra para cambiar el orden."),
        .init(template: .symbol("globe"), title: "Idioma original", body: "El de cada película o serie (japonés en un anime). Puedes subirlo o bajarlo como los demás."),
    ], action: ("Cambiar tus idiomas", .languages))

    /// Todas, en el orden de Ajustes › Aprende Orbital.
    public static let all: [LearnStory] = [debrid, pay, trakt, languages, advanced, explore, alerts, versions, noVersions, player, downloads, watching, tv]
}
