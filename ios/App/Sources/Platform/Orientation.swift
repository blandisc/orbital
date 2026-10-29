import UIKit

/// El giro de la interfaz. En el iPhone la app es vertical y el reproductor gira (lo pide él con `requestGeometryUpdate`). En
/// el iPad y en la Mac la ventana puede tener cualquier forma (Split View, Stage Manager, una ventana de Mac): el sistema
/// decide y aquí no se fuerza nada. Lo usan `AppDelegate` y el reproductor (`PlayerScreen+CicloDeVida.swift`).
@MainActor
enum Orientation {
    /// ¿La app manda en el giro? Solo en el iPhone (en la Mac «Diseñada para iPad» el idioma es `.pad`).
    static let isControlled = UIDevice.current.userInterfaceIdiom == .phone

    /// Lo que se permite ahora (en el iPhone: vertical fuera del reproductor). En iPad y Mac, todas.
    static var mask: UIInterfaceOrientationMask = .portrait
    static var supported: UIInterfaceOrientationMask { isControlled ? mask : .all }

    /// La orientación del teléfono al abrir el reproductor (con el candado de rotación, la última que iOS conoce).
    static var opening: UIInterfaceOrientationMask {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        switch UIDevice.current.orientation {
        case .portrait: return .portrait
        case .landscapeLeft: return .landscapeRight      // el teléfono a la izquierda deja la interfaz a la derecha
        case .landscapeRight: return .landscapeLeft
        default: return .landscape
        }
    }

    static func beginDeviceNotifications() { UIDevice.current.beginGeneratingDeviceOrientationNotifications() }
    static func endDeviceNotifications() { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
    static let deviceDidRotate = UIDevice.orientationDidChangeNotification

    /// Sigue al teléfono (solo llega si el candado de rotación del sistema está quitado). Una sola petición, a la
    /// orientación exacta: la preferencia de `requestGeometryUpdate` se queda pegada, así que no basta el giro solo de UIKit.
    static func followDevice() {
        guard isControlled else { return }
        let target: UIInterfaceOrientationMask
        switch UIDevice.current.orientation {
        case .portrait: target = .portrait
        case .landscapeLeft: target = .landscapeRight    // el teléfono a la izquierda deja la interfaz a la derecha
        case .landscapeRight: target = .landscapeLeft
        default: return                                  // boca arriba, boca abajo o de cabeza: se queda como está
        }
        mask = .allButUpsideDown
        guard let scene = refreshSupported() else { return }
        generation += 1                                  // cancela los reintentos de la apertura
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
    }

    /// Cada petición nueva invalida los reintentos pendientes de la anterior (no vuelven a forzar el horizontal).
    static var generation = 0

    /// Desde iOS 16 hay que avisar a la vista raíz de que cambiaron las orientaciones permitidas antes de pedir el giro;
    /// si no, la petición se ignora y el video se queda en vertical.
    static func rotate(allowed: UIInterfaceOrientationMask, to target: UIInterfaceOrientationMask) {
        mask = allowed
        guard isControlled, let scene = refreshSupported() else { return }
        generation += 1
        requestGeometry(scene, target, attemptsLeft: 10, generation: generation)
    }

    /// Permite girar otra vez (al quitar el bloqueo del reproductor).
    static func allowAll() {
        mask = .allButUpsideDown
        if isControlled { refreshSupported() }
    }

    /// Avisa a la raíz y a todo lo que presenta encima (el reproductor es una pantalla completa presentada) de que
    /// cambiaron las orientaciones permitidas.
    @discardableResult
    static func refreshSupported() -> UIWindowScene? {
        guard let scene = AppWindows.scene else { return nil }
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller { current.setNeedsUpdateOfSupportedInterfaceOrientations(); controller = current.presentedViewController }
        }
        return scene
    }

    /// «Bloquear» también congela el giro: solo se permite la orientación de este momento hasta desbloquear.
    static func freeze() {
        guard isControlled, let scene = AppWindows.scene else { return }
        mask = switch scene.effectiveGeometry.interfaceOrientation {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: .portrait
        }
        refreshSupported()
    }

    /// Mientras la pantalla completa se está presentando, iOS rechaza el giro («Supported: portrait»): se reintenta
    /// en cuanto termina la animación (unas décimas). Cada intento va en otra vuelta, cuando iOS ya leyó las orientaciones nuevas.
    static func requestGeometry(_ scene: UIWindowScene, _ target: UIInterfaceOrientationMask, attemptsLeft: Int, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard generation == Self.generation else { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in
                guard attemptsLeft > 1 else { return }
                DispatchQueue.main.async { requestGeometry(scene, target, attemptsLeft: attemptsLeft - 1, generation: generation) }
            }
        }
    }
}

/// La ventana de la app (la primera escena): sus márgenes seguros y sus ventanas (el modo claro u oscuro se pone en todas).
@MainActor
enum AppWindows {
    static var scene: UIWindowScene? { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first }
    static var all: [UIWindow] { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows) }

    /// Pone en la escena el tamaño mínimo de ventana (`WindowMetrics.minimum`): en la Mac y en el iPad. En el iPhone no hace
    /// nada (la ventana es la pantalla).
    static func applyMinimumSize() {
        scene?.sizeRestrictions?.minimumSize = WindowMetrics.minimum
    }

    /// Los márgenes seguros de la ventana principal (el video en horizontal ignora el área segura y no los trae su `GeometryReader`).
    static var safeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
    }
}

/// El brillo de la pantalla para el gesto del reproductor. Solo donde la app puede cambiarlo (iPhone y iPad; en la Mac no).
@MainActor
enum ScreenBrightness {
    static let isAdjustable = !ProcessInfo.processInfo.isiOSAppOnMac
    /// La pantalla de la ventana de la app (`UIScreen.main` quedó en desuso en iOS 26).
    private static var screen: UIScreen? { AppWindows.scene?.screen }
    static var value: Double {
        get { Double(screen?.brightness ?? 1) }
        set { if isAdjustable { screen?.brightness = CGFloat(newValue) } }
    }
}
