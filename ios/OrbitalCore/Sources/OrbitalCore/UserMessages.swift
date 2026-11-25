import Foundation

/// Los mensajes que ve la gente: sin códigos ni errores del sistema.
public enum UserMessages {
    /// Lo técnico no llega a la pantalla: códigos HTTP, errores del sistema (en el idioma del sistema, no de la app) y los
    /// mensajes en inglés se vuelven una frase normal. Se queda lo que ya decía en español antes de los dos puntos
    /// («No pude cambiar tu lista: HTTP 503» → «No pude cambiar tu lista. Revisa tu conexión.»).
    public static func humanize(_ text: String) -> String {
        let lower = text.lowercased()
        // Se llenó el iPhone a media descarga: el texto del sistema (en el idioma del iPhone) no decía qué hacer.
        if ["enough space", "suficiente espacio", "no space left", "out of space"].contains(where: lower.contains) {
            return "Se llenó el iPhone. Libera espacio y toca Reintentar."
        }
        let technical = [#"HTTP \d{3}"#, "Error Domain=", "NSURLError", "NSPOSIXError", "The Internet connection", "The request timed out",
                         "Could not connect to the server", "A server with the specified hostname", "The network connection was lost",
                         #"\(código -?\d+\)"#, "parece estar desactivada", "Se agotó el tiempo de espera", "No se ha podido conectar"]
        guard technical.contains(where: { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) else { return codeError(text) }
        // La causa (modo degradado): un 5xx es el servicio, no tu internet; un 401/403, que la sesión se cerró.
        let serverDown = text.range(of: #"HTTP 5\d\d"#, options: .regularExpression) != nil
        let signedOut = text.range(of: #"HTTP 40[13]"#, options: .regularExpression) != nil
        let exit = serverDown ? "El servicio no contesta ahora; intenta en un rato."
            : signedOut ? "Tu sesión se cerró: vuelve a conectar la cuenta en Ajustes."
            : "Revisa tu conexión e intenta de nuevo."
        // Lo que dice qué se intentaba (en español, antes de «:»), y la salida.
        if let colon = text.firstIndex(of: ":") {
            let lead = text[..<colon].trimmingCharacters(in: .whitespaces)
            if lead.count > 8, !technical.contains(where: { lead.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
                return "\(lead). \(exit)"
            }
        }
        if serverDown { return "El servicio no contesta ahora. Intenta en un rato." }
        if signedOut { return "Tu sesión se cerró. Vuelve a conectar la cuenta en Ajustes." }
        return "Sin conexión. Revisa tu internet e intenta de nuevo."
    }

    /// JT (25 nov 2026, igual que la TV): un error del código o del sistema (un tipo de Swift, «The operation couldn’t be
    /// completed», un dominio de Cocoa, AVFoundation en inglés) nunca llega crudo: queda lo que se intentaba y «Intenta de nuevo».
    static let codeMarks = [#"couldn[’']t be completed"#, "The operation", #"Domain="#, "DecodingError", "keyNotFound", "typeMismatch",
                            "valueNotFound", "dataCorrupted", #"Optional\("#, #"Swift\."#, #"\b[A-Z][A-Za-z]+Error\b"#, #"\b[a-z]+[A-Z][A-Za-z]*\("#,
                            "cannot be opened", "could not be", "unsupported URL", "Cannot Open", "Operation Stopped", "unknown error", #"error -?\d+"#]

    private static func codeError(_ text: String) -> String {
        guard codeMarks.contains(where: { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) else { return text }
        if let colon = text.firstIndex(of: ":") {
            let lead = text[..<colon].trimmingCharacters(in: .whitespaces)
            if lead.count > 8, !codeMarks.contains(where: { lead.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }) {
                return "\(lead). Intenta de nuevo."
            }
        }
        return "Algo falló de nuestro lado. Intenta de nuevo."
    }

}
