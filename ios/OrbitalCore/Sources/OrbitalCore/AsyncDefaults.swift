import Foundation

/// Lo que usan por omisión los cierres asíncronos que se inyectan (esperas): una función con nombre en vez de un cierre
/// escrito en el argumento. Con el compilador de la CI de GitHub, un cierre asíncrono por omisión se compilaba mal y el
/// proceso se cerraba («freed pointer was not the last allocation», «Bad pointer dereference», 31 oct 2026).
public enum AsyncDefaults {
    /// Espera de verdad (cancelable: si cancelan la tarea, regresa antes).
    @Sendable public static func sleep(_ seconds: TimeInterval) async {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
    }
}
