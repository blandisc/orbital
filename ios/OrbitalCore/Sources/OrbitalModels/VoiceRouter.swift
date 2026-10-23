import Foundation
import OrbitalCore

/// A dónde va una orden de voz (del micrófono del control o de Siri). La consola entiende casi todo (`voice.py`, lo mismo que
/// Alexa); el iPhone atiende antes lo que solo él puede hacer (descargar en el teléfono, seguir viendo aquí), lo que es una
/// tecla del control («atrás», «arriba», «aceptar») y deja el texto limpio del ruido del dictado («Orbital, …», «por favor»,
/// puntos) y de lo básico en inglés, que la consola no entiende.
public enum VoiceRoute: Equatable, Sendable {
    /// A la consola, ya limpio.
    case console(String)
    /// Una tecla del mando.
    case key(OrbitalRemote.InputAction)
    /// Descargar en el iPhone: lo que se ve en la TV (nil) o ese título.
    case download(title: String?)
    /// Seguir viendo aquí lo que se ve en la TV.
    case continueHere
    /// Nada que mandar (silencio, solo «por favor»…).
    case nothing
}

public enum VoiceRouter {
    public static func route(_ said: String) -> VoiceRoute {
        let text = clean(said)
        let folded = fold(text)
        // Solo cortesía o el nombre (el dictado cortó la orden): nada que mandar.
        guard !text.isEmpty, !["por favor", "porfa", "please", "orbital", "oye orbital", "oye", "hey orbital"].contains(folded) else { return .nothing }
        if let key = keys[folded] { return .key(key) }
        if matches(folded, #"^(?:ponlo|ponla|pongalo|pongala|sigue|siguelo|siguela|seguir|continua|continuala|continualo)(?:\s+viendo(?:lo|la)?)?\s+(?:aqui|aca|en\s+(?:el|mi)\s+(?:iphone|telefono|celular))$"#)
            || matches(folded, #"^(?:verlo|verla|ver)\s+(?:aqui|en\s+(?:el|mi)\s+(?:iphone|telefono|celular))$"#) {
            return .continueHere
        }
        if matches(folded, #"^(?:descargalo|descargala|descargalos|bajalo|bajala)(?:\s+(?:al|(?:en|a)\s+(?:el|mi))\s+(?:iphone|telefono|celular))?$"#) {
            return .download(title: nil)
        }
        // «descarga Dune», «descarga la película de Dune», «manda Dune a mi iPhone», «baja Dune al teléfono». «baja» solo con el
        // teléfono dicho: «baja el volumen» es de la TV.
        if let title = capture(folded, #"^(?:descarga|descargame|descargar)\s+(?:la\s+pelicula\s+(?:de\s+)?|la\s+serie\s+)?(?<t>.+?)(?:\s+(?:al|(?:en|a)\s+(?:el|mi))\s+(?:iphone|telefono|celular))?$"#)
            ?? capture(folded, #"^(?:manda|mandame|envia|enviame|baja|bajame)\s+(?:la\s+pelicula\s+(?:de\s+)?|la\s+serie\s+)?(?<t>.+?)\s+(?:al|a\s+mi|a\s+el|en\s+el|en\s+mi)\s+(?:iphone|telefono|celular)$"#) {
            return .download(title: title)
        }
        return .console(english(text))
    }

    /// Sin el ruido del dictado: «Orbital, …», «oye Orbital», «por favor», signos al principio y al final.
    public static func clean(_ said: String) -> String {
        var text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!¡?¿…\"«»“”'"))
        let leading = #"^(?i)(?:(?:oye|hey|ok|okay|hola)\s+)?orbital\s*[,.:]?\s+|^(?i)(?:por\s*favor|porfa|porfis)\s*,?\s+"#
        let trailing = #"(?i)\s*,?\s+(?:por\s*favor|porfa|porfis|please)$"#
        for _ in 0..<2 {
            text = text.replacingOccurrences(of: leading, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: trailing, with: "", options: .regularExpression)
        }
        return text.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,;:!¡?¿…")))
    }

    /// Las teclas del control dichas solas («atrás», «arriba», «aceptar»). Con algo más («regresa 10 segundos») va a la consola.
    static let keys: [String: OrbitalRemote.InputAction] = [
        "atras": .back, "regresa": .back, "regresar": .back, "volver": .back, "vuelve": .back, "back": .back,
        "arriba": .up, "abajo": .down, "izquierda": .left, "derecha": .right, "up": .up, "down": .down, "left": .left, "right": .right,
        "aceptar": .select, "acepta": .select, "selecciona": .select, "elige": .select, "entra": .select, "ok": .select, "okay": .select, "select": .select,
        "menu": .menu, "opciones": .options,
    ]

    /// Lo básico en inglés, como lo entiende la consola (que solo habla español).
    static func english(_ text: String) -> String {
        let folded = fold(text)
        let fixed: [String: String] = [
            "pause": "pausa", "stop": "cierra el video", "resume": "sigue", "continue": "sigue", "play": "dale play",
            "next": "siguiente episodio", "next episode": "siguiente episodio", "previous episode": "episodio anterior",
            "skip intro": "salta la intro", "mute": "silencio", "unmute": "quita el silencio",
            "volume up": "sube el volumen", "volume down": "baja el volumen", "turn it up": "sube el volumen", "turn it down": "baja el volumen",
            "subtitles off": "quita los subtitulos", "turn off subtitles": "quita los subtitulos", "whats playing": "que estoy viendo",
            "what am i watching": "que estoy viendo", "how much is left": "cuanto falta", "what should i watch": "que me recomiendas",
            "whats new": "que sale hoy",
        ]
        if let spanish = fixed[folded.replacingOccurrences(of: "'", with: "")] { return spanish }
        let said = #"(?<t>english|spanish|latin spanish|latin american spanish|latino|castilian(?: spanish)?|spain spanish|castellano)"#
        if let title = capture(folded, #"^(?:play|watch|put on|i want to watch)\s+(?<t>.+)$"#) {
            // «Play The Simpsons in Latin Spanish» → «pon the simpsons en latino»
            if let language = capture(title, #"\s+in\s+"# + said + "$"), let name = languages[language],
               let range = title.range(of: #"\s+in\s+[a-z ]+$"#, options: .regularExpression) {
                return "pon \(title[..<range.lowerBound]) en \(name)"
            }
            return "pon " + title
        }
        if let title = capture(folded, #"^(?:search(?:\s+for)?|find|look for)\s+(?<t>.+)$"#) { return "busca " + title }
        if let title = capture(folded, #"^(?:open|launch)\s+(?<t>.+)$"#) { return "abre " + title }
        if let language = capture(folded, #"^(?:subtitles|turn on subtitles)(?:\s+in)?\s+"# + said + "$"), let name = languages[language] {
            return "subtitulos en " + name
        }
        // «In Latin Spanish», «audio in Castilian»: el doblaje (latino o castellano), como «en latino» en la consola.
        if let language = capture(folded, #"^(?:(?:switch\s+)?(?:the\s+)?audio\s+)?(?:in|to)\s+"# + said + "$"), let name = languages[language] {
            return "en " + name
        }
        return text
    }

    /// Los idiomas dichos en inglés (o el doblaje en español) como los dice la consola: «latino» y «castellano» piden el
    /// doblaje; «español», cualquiera de los dos.
    static let languages: [String: String] = [
        "english": "ingles", "spanish": "espanol", "latin spanish": "latino", "latin american spanish": "latino", "latino": "latino",
        "castilian": "castellano", "castilian spanish": "castellano", "spain spanish": "castellano", "castellano": "castellano",
    ]

    /// Minúsculas, sin acentos ni signos (para comparar; a la consola va el texto limpio, ella hace lo suyo).
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).lowercased()
        let kept = plain.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "'" ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(m.range(withName: "t"), in: text) else { return nil }
        let value = String(text[range]).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
}
