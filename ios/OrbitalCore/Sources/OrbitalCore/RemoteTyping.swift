import Foundation

/// «Escribir en la TV»: la tele agrega cada letra que recibe al campo con foco (y «\u{8}» borra una). Mandar el texto completo
/// en cada cambio lo repetía («hola» → «holahola mundo»): se manda solo la diferencia con lo ya enviado.
public enum RemoteTyping {
    /// Borrados («\u{8}») hasta lo que tienen en común y luego lo nuevo.
    public static func delta(from sent: String, to text: String) -> String {
        let common = zip(sent, text).prefix { $0 == $1 }.count
        return String(repeating: "\u{8}", count: sent.count - common) + String(text.dropFirst(common))
    }
}
