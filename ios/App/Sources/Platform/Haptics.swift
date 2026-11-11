import SwiftUI
import UIKit

/// La vibración de la app («sonido y vibración como idioma»). Solo el iPhone vibra: el iPad no tiene motor de vibración y en
/// la Mac no aplica. Ahí SwiftUI manda cada `sensoryFeedback` por la vibración «con lugar» (lápiz y trackpad) y esa ruta
/// tronaba la app al abrir el reproductor en el iPad (10 nov 2026, iPadOS 27: `LocationBasedFeedbackAdaptor`). Por eso
/// ninguna pantalla llama a `sensoryFeedback` directo: usa `dsFeedback`, que en el iPad y la Mac no hace nada.
/// `PlatformBoundaryTests.testHapticsGoThroughDSFeedback` lo cuida.
enum Haptics {
    /// ¿Este aparato vibra? Solo el iPhone (la Mac «Diseñada para iPad» se presenta como iPad).
    @MainActor static let isAvailable = UIDevice.current.userInterfaceIdiom == .phone && !ProcessInfo.processInfo.isiOSAppOnMac
}

private struct DSFeedback<Trigger: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: Trigger
    let condition: ((Trigger, Trigger) -> Bool)?

    func body(content: Content) -> some View {
        if Haptics.isAvailable {
            if let condition {
                content.sensoryFeedback(feedback, trigger: trigger, condition: condition)
            } else {
                content.sensoryFeedback(feedback, trigger: trigger)
            }
        } else {
            content
        }
    }
}

extension View {
    /// Receta: la vibración de siempre (`sensoryFeedback`), solo en el iPhone. Mismas formas que la de SwiftUI.
    func dsFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(DSFeedback(feedback: feedback, trigger: trigger, condition: nil))
    }

    /// Con condición: vibra solo cuando `condition(viejo, nuevo)` dice que sí.
    func dsFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T, condition: @escaping (_ oldValue: T, _ newValue: T) -> Bool) -> some View {
        modifier(DSFeedback(feedback: feedback, trigger: trigger, condition: condition))
    }
}
