import AppIntents
import Foundation
import OrbitalCore
import OrbitalModels

// Siri y Atajos: «Oye Siri, habla con Orbital» pregunta la orden y la atiende como el micrófono del control
// (`VoiceAssistant`): descargar en el iPhone lo hace el teléfono, lo demás tu Orbital como si fuera Alexa (`/api/voice`).
// Siri dice en voz alta lo que contestó. No abre la app.
//
// Siri no acepta texto libre dentro de la frase: «Oye Siri, pausa en Orbital» o «pon The Office en Orbital» no coincidían
// con nada y Siri contestaba «Orbital no puede hacer eso». Por eso lo de todos los días va como lista (`OrbitalCommand`) y
// los títulos de «Seguir viendo» como entidades (`OrbitalTitle`): las dos se dicen en la misma frase, sin que Siri pregunte.

/// Lo que se dice: la consola lo entiende con el mismo intérprete que Alexa; regresa lo que Siri dice en voz alta.
@MainActor
private func answer(_ said: String) async -> String {
    // La Mac no controla tu Orbital (decisión de Fernando, 29 oct 2026): Siri y Atajos no le mandan nada a la TV.
    guard ThisDevice.talksToOrbital else { return macNoTV }
    let env = AppEnvironment.shared
    let outcome = await VoiceAssistant(services: env.services, tvNow: env.tvNow).handle(said)
    // Seguir aquí necesita la pantalla: Siri no abre el reproductor.
    let text = outcome.continueHere ? "Abre Orbital y toca «Seguir aquí»." : outcome.speech
    return text.isEmpty ? String(localized: "Listo.") : Strings.message(text, language: env.services.appSettings.uiLanguage)
}

/// Lo que contesta Siri en la Mac, donde Orbital es solo para ver.
private var macNoTV: String { String(localized: "En la Mac, Orbital no controla la TV. Usa tu iPhone o tu iPad.") }

/// «Dile a Orbital que ponga The Office»: la orden en texto libre.
struct AskOrbitalIntent: AppIntent {
    static let title: LocalizedStringResource = "Habla con Orbital"
    static let description = IntentDescription("Manda una orden a tu Orbital, como a Alexa: «pon The Office», «pausa», «abre Zelda».")
    static let openAppWhenRun = false

    @Parameter(title: "Orden", requestValueDialog: IntentDialog("¿Qué le digo a Orbital?"))
    var command: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await answer(command)))
    }
}

/// Las órdenes de todos los días, en una sola frase: «Oye Siri, pausa en Orbital», «sube el volumen en Orbital».
enum OrbitalCommand: String, AppEnum {
    case pause, resume, nextEpisode, previousEpisode, skipIntro, restart, forward, back, volumeUp, volumeDown, mute, unmute,
         subtitlesOn, subtitlesOff, englishSubtitles, latinSpanish, castilianSpanish, timeLeft, stopVideo, continueWatching,
         liveTV, nextChannel, previousChannel, upcoming, recommend, whatsOpen, closeGame, home, capture

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Orden"
    /// Cada orden también como se dice después de «que» («Dile a Orbital que pause», «… que le suba»).
    static let caseDisplayRepresentations: [OrbitalCommand: DisplayRepresentation] = [
        .pause: DisplayRepresentation(title: "Pausa", synonyms: ["Pause", "Ponga pausa", "Pon pausa", "Pausa la tele", "Espera"]),
        .resume: DisplayRepresentation(title: "Reanuda", synonyms: ["Reanude", "Quite la pausa", "Siga", "Quita la pausa", "Dale play", "Continúa"]),
        .nextEpisode: DisplayRepresentation(title: "Siguiente episodio", synonyms: ["Ponga el siguiente episodio", "Ponga el siguiente capítulo", "Siguiente capítulo", "Pon el siguiente episodio"]),
        .previousEpisode: DisplayRepresentation(title: "Episodio anterior", synonyms: ["Ponga el episodio anterior", "Ponga el capítulo anterior", "Capítulo anterior"]),
        .skipIntro: DisplayRepresentation(title: "Salta la intro", synonyms: ["Salte la intro", "Se salte la intro", "Sáltate la intro", "Brinca la intro"]),
        .restart: DisplayRepresentation(title: "Desde el principio", synonyms: ["Empiece de nuevo", "Vuelva a empezar", "Empieza de nuevo", "Vuelve a empezar"]),
        .forward: DisplayRepresentation(title: "Adelanta", synonyms: ["Adelante", "Le adelante", "Adelántale", "Adelanta treinta segundos"]),
        .back: DisplayRepresentation(title: "Regresa", synonyms: ["Regrese", "Le regrese", "Regrésale", "Regresa treinta segundos"]),
        .volumeUp: DisplayRepresentation(title: "Sube el volumen", synonyms: ["Suba el volumen", "Le suba", "Súbele", "Más fuerte"]),
        .volumeDown: DisplayRepresentation(title: "Baja el volumen", synonyms: ["Baje el volumen", "Le baje", "Bájale", "Más bajo"]),
        .mute: DisplayRepresentation(title: "Silencia", synonyms: ["Silencie", "Quite el sonido", "Silencio", "Quita el sonido"]),
        .unmute: DisplayRepresentation(title: "Quita el silencio", synonyms: ["Quite el silencio", "Regrese el sonido", "Regresa el sonido"]),
        .subtitlesOn: DisplayRepresentation(title: "Pon subtítulos", synonyms: ["Ponga subtítulos", "Active los subtítulos", "Activa los subtítulos"]),
        .subtitlesOff: DisplayRepresentation(title: "Quita los subtítulos", synonyms: ["Quite los subtítulos", "Apague los subtítulos", "Apaga los subtítulos"]),
        .englishSubtitles: DisplayRepresentation(title: "Subtítulos en inglés", synonyms: ["Ponga subtítulos en inglés", "Pon subtítulos en inglés"]),
        // El doblaje de lo que se ve, solo esta vez («ponlo siempre en latino» lo guarda: eso se dice con «Pídele a Orbital…»).
        .latinSpanish: DisplayRepresentation(title: "En latino", synonyms: ["Pon el audio en latino", "Póngalo en latino", "Ponlo en latino"]),
        .castilianSpanish: DisplayRepresentation(title: "En castellano", synonyms: ["Pon el audio en castellano", "Póngalo en castellano", "Ponlo en castellano"]),
        .timeLeft: DisplayRepresentation(title: "Cuánto falta", synonyms: ["Cuánto le queda"]),
        .stopVideo: DisplayRepresentation(title: "Sal del video", synonyms: ["Salga del video", "Quite el video", "Quita el video", "Detén el video"]),
        .continueWatching: DisplayRepresentation(title: "Sigue viendo", synonyms: ["Siga viendo", "Ponga lo que estaba viendo", "Pon lo que estaba viendo"]),
        .liveTV: DisplayRepresentation(title: "Pon la tele", synonyms: ["Ponga la tele", "Pon la tele en vivo"]),
        .nextChannel: DisplayRepresentation(title: "Siguiente canal", synonyms: ["Cambie de canal", "Ponga el siguiente canal", "Cambia de canal"]),
        .previousChannel: DisplayRepresentation(title: "Canal anterior", synonyms: ["Ponga el canal anterior"]),
        .upcoming: DisplayRepresentation(title: "Qué sale hoy", synonyms: ["Qué estrenos hay"]),
        .recommend: DisplayRepresentation(title: "Qué me recomiendas", synonyms: ["Recomiéndame algo"]),
        .whatsOpen: DisplayRepresentation(title: "Qué está abierto", synonyms: ["Qué estoy viendo", "Qué estoy jugando"]),
        .closeGame: DisplayRepresentation(title: "Cierra el juego", synonyms: ["Cierre el juego", "Sal del juego"]),
        .home: DisplayRepresentation(title: "Ve a inicio", synonyms: ["Vaya a inicio", "Vaya al inicio", "Ve al inicio"]),
        .capture: DisplayRepresentation(title: "Toma una captura", synonyms: ["Tome una captura", "Capture la pantalla", "Captura la pantalla"]),
    ]

    /// Lo que se le dice a la consola (frases que su intérprete entiende; `tests/test_voice.py` las prueba).
    var said: String {
        switch self {
        case .pause: "pausa"
        case .resume: "reanuda"
        case .nextEpisode: "siguiente episodio"
        case .previousEpisode: "episodio anterior"
        case .skipIntro: "salta la intro"
        case .restart: "desde el principio"
        case .forward: "adelanta 30 segundos"
        case .back: "regresa 30 segundos"
        case .volumeUp: "sube el volumen"
        case .volumeDown: "baja el volumen"
        case .mute: "silencia"
        case .unmute: "quita el silencio"
        case .subtitlesOn: "pon subtítulos"
        case .subtitlesOff: "quita los subtítulos"
        case .englishSubtitles: "subtítulos en inglés"
        case .latinSpanish: "en latino"
        case .castilianSpanish: "en castellano"
        case .timeLeft: "cuánto falta"
        case .stopVideo: "sal del video"
        case .continueWatching: "sigue viendo"
        case .liveTV: "pon la tele"
        case .nextChannel: "siguiente canal"
        case .previousChannel: "canal anterior"
        case .upcoming: "qué sale hoy"
        case .recommend: "qué me recomiendas"
        case .whatsOpen: "qué está abierto"
        case .closeGame: "cierra el juego"
        case .home: "ve a inicio"
        case .capture: "toma una captura"
        }
    }
}

struct OrbitalCommandIntent: AppIntent {
    static let title: LocalizedStringResource = "Orden rápida"
    static let description = IntentDescription("Pausa, volumen, siguiente episodio y lo de todos los días, en una sola frase.")
    static let openAppWhenRun = false

    @Parameter(title: "Orden")
    var command: OrbitalCommand

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await answer(command.said)))
    }
}

/// Un título para decirlo en la misma frase: «Oye Siri, pon Los Simpson en Orbital». Cada nombre que se puede decir es su
/// propio título (`id` = el nombre dicho): Siri arma la frase con el nombre principal y no usa los sinónimos (con «The
/// Simpsons» y «Los Simpson» como sinónimo, «pon Los Simpson» no coincidía). A la consola se le pide el nombre original.
struct OrbitalTitle: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Título"
    static let defaultQuery = OrbitalTitleQuery()

    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
    /// Lo que se le pide a la consola: el nombre original de ese título (o lo dicho, si no se conoce).
    var asked: String { SiriTitles.original(for: id) ?? id }

    /// Los nombres que se pueden decir de un título: el original, el de español y el original sin artículo («Simpsons»).
    static func spokenNames(_ names: [String]) -> [String] {
        guard let original = names.first else { return [] }
        var base = original
        for article in ["The ", "A ", "An "] where base.hasPrefix(article) { base = String(base.dropFirst(article.count)) }
        var seen = Set<String>()
        return (names + [base]).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

struct OrbitalTitleQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [OrbitalTitle] { identifiers.map { OrbitalTitle(id: $0) } }
    func entities(matching string: String) async throws -> [OrbitalTitle] {
        let name = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? [] : [OrbitalTitle(id: name)]
    }
    func suggestedEntities() async throws -> [OrbitalTitle] { SiriTitles.load().flatMap { OrbitalTitle.spokenNames($0) }.map { OrbitalTitle(id: $0) } }
}

/// Los títulos que Siri reconoce: los de «Seguir viendo» y tu lista (más Los Simpson, siempre), guardados en el iPhone. Cada
/// uno es [nombre original, nombre en español]: se le pide a la consola el original y Siri acepta los dos.
enum SiriTitles {
    private static let key = "siri.titles.v2"
    private static let limit = 60
    /// Los Simpson tienen su propio lugar en la app (la ruleta): Siri los conoce aunque no estén en tu lista.
    private static let always: [[String]] = [["The Simpsons", "Los Simpson"]]

    static func load() -> [[String]] { (UserDefaults.standard.array(forKey: key) as? [[String]]) ?? always }

    /// El nombre original de un nombre dicho («Los Simpson» → «The Simpsons»).
    static func original(for spoken: String) -> String? {
        load().first { OrbitalTitle.spokenNames($0).contains { $0.caseInsensitiveCompare(spoken) == .orderedSame } }?.first
    }

    /// Si cambiaron, se guardan y Siri vuelve a leerlos (aprende a reconocer los nombres nuevos).
    static func save(_ titles: [[String]]) {
        var seen = Set<String>()
        let clean = (titles + always).compactMap { names -> [String]? in
            let n = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard let first = n.first, seen.insert(first.lowercased()).inserted else { return nil }
            return [first] + n.dropFirst().filter { $0.lowercased() != first.lowercased() }
        }
        let unique = Array(clean.prefix(limit))
        guard !unique.isEmpty, unique != (UserDefaults.standard.array(forKey: key) as? [[String]]) else { return }
        UserDefaults.standard.set(unique, forKey: key)
        OrbitalShortcuts.updateAppShortcutParameters()
    }
}

struct PlayTitleIntent: AppIntent {
    static let title: LocalizedStringResource = "Poner en la TV"
    static let description = IntentDescription("Pone en tu Orbital una película o una serie, donde ibas.")
    static let openAppWhenRun = false

    @Parameter(title: "Título", requestValueDialog: IntentDialog("¿Qué pongo en la TV?"))
    var show: OrbitalTitle

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await answer("pon \(show.asked)")))
    }
}

/// «Pausa la TV con Orbital» / «Sigue la TV con Orbital»: lo de todos los días, sin decir la orden. (Las frases ya las cubre
/// `OrbitalCommandIntent`; estas se quedan para los atajos que ya los usan.)
struct PauseTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Pausar la TV"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ThisDevice.talksToOrbital else { return .result(dialog: IntentDialog(stringLiteral: macNoTV)) }
        await AppEnvironment.shared.tvNow.control("pause")
        return .result(dialog: "En pausa.")
    }
}

struct ResumeTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Seguir en la TV"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard ThisDevice.talksToOrbital else { return .result(dialog: IntentDialog(stringLiteral: macNoTV)) }
        await AppEnvironment.shared.tvNow.control("play")
        return .result(dialog: "Sigue.")
    }
}

/// «Prende Orbital»: prende la tele, la pone en la entrada de la consola y muestra Orbital (como «Alexa, abre Orbital»).
struct TurnOnConsoleIntent: AppIntent {
    static let title: LocalizedStringResource = "Prender la consola"
    static let description = IntentDescription("Prende la tele en la entrada de tu Orbital y muestra la consola.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await answer("prende la consola")))
    }
}

/// Las frases que Siri reconoce sin configurar nada (aparecen solas en Atajos).
struct OrbitalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // En la Mac las frases siguen registradas (el constructor no acepta `if` salvo #available), pero `answer` contesta que
        // ahí Orbital no controla la TV.
        // «Dile a Orbital que …» sí llega a la app (Siri la reconoce por su nombre), pero solo si la frase está aquí: sin ella
        // contestaba «Orbital no permite hacer eso con Siri». Texto libre no cabe en la frase: «Habla con Orbital» lo pregunta
        // después («¿Qué le digo a Orbital?»); lo de todos los días y los títulos sí van en la frase.
        AppShortcut(intent: OrbitalCommandIntent(), phrases: [
            "\(\.$command) en \(.applicationName)", "\(\.$command) con \(.applicationName)", "\(\.$command) \(.applicationName)",
            "\(.applicationName) \(\.$command)",
            "Dile a \(.applicationName) que \(\.$command)", "Pídele a \(.applicationName) que \(\.$command)",
        ], shortTitle: "Orden rápida", systemImageName: "playpause.fill")
        AppShortcut(intent: PlayTitleIntent(), phrases: [
            "Pon \(\.$show) en \(.applicationName)", "Pon \(\.$show) con \(.applicationName)",
            "Quiero ver \(\.$show) en \(.applicationName)", "Reproduce \(\.$show) en \(.applicationName)",
            "Sigue viendo \(\.$show) en \(.applicationName)", "Poner en la TV con \(.applicationName)",
            // Como lo dice la gente: «Dile a Orbital que ponga Los Simpson» (no estaba y Siri contestaba «no permite hacer eso»).
            "Dile a \(.applicationName) que ponga \(\.$show)", "Pídele a \(.applicationName) que ponga \(\.$show)",
            "Dile a \(.applicationName) que pon \(\.$show)",
        ], shortTitle: "Poner en la TV", systemImageName: "tv")
        AppShortcut(intent: AskOrbitalIntent(), phrases: [
            "Habla con \(.applicationName)", "Orden para \(.applicationName)", "Usa \(.applicationName)", "\(.applicationName)",
        ], shortTitle: "Habla con Orbital", systemImageName: "waveform")
        AppShortcut(intent: TurnOnConsoleIntent(), phrases: [
            "Prende \(.applicationName)", "Enciende \(.applicationName)", "Prende la consola con \(.applicationName)",
        ], shortTitle: "Prender la consola", systemImageName: "power")
    }
}
