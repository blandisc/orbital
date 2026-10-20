import Foundation

/// Los mensajes que ve la gente: sin códigos ni errores del sistema.
public enum UserMessages {
    /// Lo técnico no llega a la pantalla: códigos HTTP, errores del sistema (en el idioma del sistema, no de la app) y los
    /// mensajes en inglés de Stremio se vuelven una frase normal. Se queda lo que ya decía en español antes de los dos puntos
    /// («No pude cambiar tu lista de Stremio: HTTP 503» → «No pude cambiar tu lista de Stremio. Revisa tu conexión.»).
    public static func humanize(_ text: String) -> String {
        let known: [String: String] = [
            "user not found": "Ese correo no tiene cuenta de Stremio.",
            "wrong passphrase": "La contraseña no coincide.",
            "session does not exist": "Tu sesión de Stremio se cerró: vuelve a entrar.",
        ]
        let lower = text.lowercased()
        for (english, spanish) in known where lower.contains(english) { return spanish }
        let technical = [#"HTTP \d{3}"#, "Error Domain=", "NSURLError", "NSPOSIXError", "The Internet connection", "The request timed out",
                         "Could not connect to the server", "A server with the specified hostname", "The network connection was lost",
                         #"\(código -?\d+\)"#, "parece estar desactivada", "Se agotó el tiempo de espera", "No se ha podido conectar"]
        guard technical.contains(where: { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) else { return text }
        // Lo que dice qué se intentaba (en español, antes de «:»), y la salida de siempre.
        if let colon = text.firstIndex(of: ":") {
            let lead = text[..<colon].trimmingCharacters(in: .whitespaces)
            if lead.count > 8, !technical.contains(where: { lead.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
                return "\(lead). Revisa tu conexión e intenta de nuevo."
            }
        }
        return "Sin conexión. Revisa tu internet e intenta de nuevo."
    }

}
