import SwiftUI
import OrbitalModels

/// Las cinco lecciones de Aprende (AF4-B, Fernando, 19 nov 2026: «vamos con tus recomendaciones»). Cada una contesta un
/// atasco de verdad («le doy Ver y no pasa nada», «me salió en inglés», «paso 20 minutos buscando», «¿en qué capítulo
/// iba?», «¿cómo lo paso a la tele?») con pantallas de una escena, un titular y dos líneas; la última es «Pruébalo», de
/// práctica. Los textos son claves del catálogo (`Localizable.xcstrings`) escritas con «Real-Debrid»: se dicen con tu nube.
struct Lesson: Identifiable {
    struct Step {
        let scene: LessonSceneID
        let title: String
        let line: String
        var practice = false
    }

    let id: String
    let title: String
    let blurb: String
    let symbol: String
    /// El color de su ícono en Aprende (una clave de `DS.ListTint`).
    let tint: String
    let steps: [Step]
    /// El botón de la última pantalla («Conectar mi nube») y adónde lleva; sin él, solo «Listo».
    let done: (title: String, destination: LearnStory.Destination)?
}

/// Las escenas de las lecciones (cada una la dibuja `LessonScene`).
enum LessonSceneID: String {
    case cloudPlay, cloudWhat, cloudAsk, cloudPrice, cloudOne, cloudTry
    case langPick, langOrder, langOther, langPanel, langTry
    case todayWhy, todayDecide, todaySwipe, todayFilter, todayTry
    case yoursTrakt, yoursHandoff, yoursMark, yoursAlert, yoursTry
    case tvSend, tvRemote, tvVoice, tvGame, tvTry
}

enum LessonCatalog {
    static let all: [Lesson] = [cloud, language, today, yours, tv]

    static func lesson(_ id: String) -> Lesson? { all.first { $0.id == id } }

    static let cloud = Lesson(
        id: "nube", title: "Tu nube", blurb: "Qué es, qué es «Por pedir» y cuánto cuesta", symbol: "cloud", tint: "library",
        steps: [
            .init(scene: .cloudPlay, title: "Toca «Ver» y empieza",
                  line: "Orbital busca el video en tu nube y lo pone en segundos. No se descarga nada a tu iPhone."),
            .init(scene: .cloudWhat, title: "Tu nube guarda copias",
                  line: "Real-Debrid es un servicio de pago que guarda películas y series en internet. Orbital no las tiene: las busca ahí por ti."),   // edición: la lección solo sale con instantStreams; se dice con tu nube (Text(_:cloud:))
            .init(scene: .cloudAsk, title: "Si dice «Por pedir»",
                  line: "Tu nube todavía no la tiene. Tócala y Real-Debrid la baja por ti en unos minutos; te avisamos cuando esté."),   // edición: la lección solo sale con instantStreams; se dice con tu nube (Text(_:cloud:))
            .init(scene: .cloudPrice, title: "Se paga aparte, sin sorpresas",
                  line: "Se paga en la página de Real-Debrid y no se renueva sola. Unos días antes de que se acabe, te avisamos."),   // edición: la lección solo sale con instantStreams; se dice con tu nube (Text(_:cloud:))
            .init(scene: .cloudOne, title: "Una cuenta, una persona",
                  line: "Si alguien más la usa al mismo tiempo, el video se corta. Si la compartes, te la pueden cerrar."),
            .init(scene: .cloudTry, title: "Pídele una a tu nube",
                  line: "Toca «Por pedir» en la fila de Castellano. Es de práctica: nada se pide de verdad.", practice: true),
        ],
        done: ("Conectar mi nube", .connectDebrid))

    static let language = Lesson(
        id: "idioma", title: "En tu idioma", blurb: "Tu orden de idiomas, otra versión, audio y subtítulos", symbol: "captions.bubble",
        tint: "spark",
        steps: [
            .init(scene: .langPick, title: "«Ver» elige por ti",
                  line: "Busca primero en tu idioma favorito y en la mejor calidad. Si no está, prueba con el siguiente de tu lista."),
            .init(scene: .langOrder, title: "Tú decides el orden",
                  line: "En Ajustes › Tus idiomas, mantén presionado uno y súbelo. El de arriba es el que «Ver» busca primero."),
            .init(scene: .langOther, title: "¿Quieres otra versión?",
                  line: "Toca la bandera junto a «Ver»: eliges otro idioma o calidad sin buscar la película otra vez."),
            .init(scene: .langPanel, title: "Audio y subtítulos, sin salir",
                  line: "Mientras ves, toca la pantalla y luego el globo: cambias el audio o pones subtítulos al momento."),
            .init(scene: .langTry, title: "Ponle subtítulos",
                  line: "Toca «Español» en Subtítulos. Es de práctica.", practice: true),
        ],
        done: ("Ordenar mis idiomas", .languages))

    static let today = Lesson(
        id: "hoy", title: "¿Qué veo hoy?", blurb: "Decide por mí, una por una y los filtros", symbol: "sparkles", tint: "flame",
        steps: [
            .init(scene: .todayWhy, title: "Te proponemos, tú eliges",
                  line: "Orbital aprende de lo que viste y de tu lista. Cada sugerencia dice por qué te la propone."),
            .init(scene: .todayDecide, title: "Decide por mí",
                  line: "Tres que caben en tu noche: por lo que te gusta, por lo que dura y por dónde la tienes."),
            .init(scene: .todaySwipe, title: "Una por una",
                  line: "Si quieres ir rápido: desliza a la derecha para guardarla, a la izquierda para pasar y hacia arriba si es para hoy."),
            .init(scene: .todayFilter, title: "Junta filtros",
                  line: "En Buscar: comedias, de los 90, en Netflix. Cada filtro achica la lista."),
            .init(scene: .todayTry, title: "Deja que decida",
                  line: "Toca «Decide por mí» y luego una de las tres. Es de práctica.", practice: true),
        ],
        done: ("Abrir Explorar", .explore))

    static let yours = Lesson(
        id: "tuyo", title: "Lo tuyo, al día", blurb: "Trakt, lo que viste, tus estrenos y en otro aparato", symbol: "checklist",
        tint: "trend",
        steps: [
            .init(scene: .yoursTrakt, title: "Trakt lo recuerda",
                  line: "Es gratis y guarda lo que viste, tu lista y dónde ibas. Orbital lo usa para todo lo demás."),
            .init(scene: .yoursHandoff, title: "Sigue en el mismo minuto",
                  line: "Empieza en el iPhone y termina en el iPad o en la Mac, justo donde ibas."),
            .init(scene: .yoursMark, title: "Marca y califica",
                  line: "Lo que veas fuera de Orbital, márcalo visto. Tu calificación mejora lo que te proponemos."),
            .init(scene: .yoursAlert, title: "Sale hoy",
                  line: "Sigue una serie y te avisamos el día del estreno. Todo lo que sale está en el calendario de Inicio."),
            .init(scene: .yoursTry, title: "Marca un episodio",
                  line: "Toca el círculo del episodio 3 y luego sigue la serie. Es de práctica.", practice: true),
        ],
        done: ("Conectar Trakt", .connectTrakt))

    static let tv = Lesson(
        id: "tv", title: "Tu TV", blurb: "Mándalo a la tele, el control y la voz", symbol: "tv", tint: "series",
        steps: [
            .init(scene: .tvSend, title: "«Ver en la TV»",
                  line: "Desde cualquier película o serie, un toque: empieza en la sala justo donde ibas."),
            .init(scene: .tvRemote, title: "Tu iPhone es el control",
                  line: "Muévete por los menús, pausa y sube el volumen sin buscar el mando."),
            .init(scene: .tvVoice, title: "Háblale",
                  line: "«Oye Siri, siguiente episodio en Orbital». Las frases están en Ajustes › Voz y Siri."),
            .init(scene: .tvGame, title: "Mientras juegas",
                  line: "Si abres un juego en la consola, el iPhone te enseña su guía, tus notas y un temporizador."),   // edición: la lección de la TV solo sale con la consola
            .init(scene: .tvTry, title: "Mándala a la TV",
                  line: "Toca «Ver en la TV» y luego muévete con las flechas. Es una TV de práctica.", practice: true),
        ],
        done: ("Conectar mi TV", .tv))
}
