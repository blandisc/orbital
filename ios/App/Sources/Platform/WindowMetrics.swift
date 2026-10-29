import SwiftUI
import UIKit

/// El tamaño de la ventana de la app (con las áreas seguras incluidas): lo que las pantallas usan en vez del de la pantalla.
/// En el iPhone la ventana ocupa la pantalla entera y mide lo mismo; en el iPad (Split View, Stage Manager) y en la Mac la
/// ventana es más chica y cambia de tamaño. La raíz lo actualiza (`.tracksWindowSize()`); quien lo lee dentro de un `body`
/// se vuelve a pintar cuando cambia (Observation). También lo compila la extensión de widgets (por `Tokens.swift`).
@MainActor @Observable
final class WindowMetrics {
    static let shared = WindowMetrics()

    /// Arranca con el tamaño de la pantalla: en el iPhone es el de la ventana desde el primer cuadro (nada brinca al medir).
    private(set) var size: CGSize = WindowMetrics.initialSize

    /// El tamaño de la pantalla de la ventana de la app (`UIScreen.main` quedó en desuso en iOS 26). La extensión de widgets no
    /// tiene ventana ni `UIApplication`: arranca con el mínimo (sus tamaños los da la familia del widget, no estos tokens).
    private static var initialSize: CGSize {
        #if WIDGET_EXTENSION
        return minimum
        #else
        return AppWindows.scene?.screen.bounds.size ?? minimum
        #endif
    }

    /// Para los tokens (`DS`), que no están atados al hilo principal: solo se leen al pintar, que siempre es en él.
    nonisolated static var size: CGSize { MainActor.assumeIsolated { shared.size } }

    /// Lo más chico que puede quedar la ventana en la Mac y en el iPad (Stage Manager, ventanas de iPadOS 26): el iPhone SE,
    /// el tamaño más chico en el que la app está probada. Así ningún acomodo se rompe al achicar la ventana.
    static let minimum = CGSize(width: 375, height: 667)

    func update(_ new: CGSize) {
        guard new.width > 0, new.height > 0, new != size else { return }
        size = new
    }
}

extension View {
    /// Pone al día `WindowMetrics` con el tamaño completo de la ventana: lo que mide la raíz más sus márgenes seguros (barra
    /// de estado, notch, barra de inicio, teclado). Con `ignoresSafeArea` en un fondo la medida seguía sin la barra de estado
    /// y el control completo quedaba ~50 pt más bajo en los iPhone con notch. Una vez, en la raíz.
    func tracksWindowSize() -> some View {
        onGeometryChange(for: CGSize.self) { proxy in
            let inset = proxy.safeAreaInsets
            return CGSize(width: proxy.size.width + inset.leading + inset.trailing, height: proxy.size.height + inset.top + inset.bottom)
        } action: { WindowMetrics.shared.update($0) }
    }
}
