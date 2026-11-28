import SwiftUI

/// La bisagra del iPhone Duo (iOS 27.1): si está medio abierto, los juegos van arriba y los botones abajo (E1-A). En los
/// demás aparatos nunca está medio abierto. En Debug, `-demo-duo-half` lo finge para las capturas sin el aparato.
extension View {
    func tracksDuoHalfOpen(_ halfOpen: Binding<Bool>) -> some View { modifier(DuoHalfOpen(halfOpen: halfOpen)) }
}

private struct DuoHalfOpen: ViewModifier {
    @Binding var halfOpen: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            content
                .onHingeChange { _, new in halfOpen = new.hinge?.status == .partiallyOpen || demo }
                .onAppear { if demo { halfOpen = true } }
        } else {
            content.onAppear { if demo { halfOpen = true } }
        }
        #else
        content.onAppear { if demo { halfOpen = true } }   // el Xcode de la CI (26.3) no conoce la API: ahí no hay Duo
        #endif
    }

    private var demo: Bool {
        #if DEBUG
        Demo.has("-demo-duo-half")
        #else
        false
        #endif
    }
}

extension WindowMetrics {
    /// La pantalla de afuera del Duo, de pie o acostada (466 × 678): más ancha que un iPhone y más baja. Ahí los juegos se
    /// pueden jugar, con el aviso de que se ven mejor abierto (E5-A). Ningún otro iPhone mide así.
    nonisolated static var duoOuter: Bool {
        #if os(iOS) && !WIDGET_EXTENSION
        let s = size, short = min(s.width, s.height), long = max(s.width, s.height)
        return !ProcessInfo.onMac && short >= 440 && long <= 700
        #else
        return false
        #endif
    }
}
