import SwiftUI
import UIKit

/// Los gestos del reproductor que van con los reconocedores de iOS (conviven con los de SwiftUI).
struct TwoFingerTap: UIGestureRecognizerRepresentable {
    let action: () -> Void
    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let tap = UITapGestureRecognizer()
        tap.numberOfTouchesRequired = 2
        tap.numberOfTapsRequired = 1
        return tap
    }
    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }
}

/// El pellizco del video con el reconocedor de iOS (Fernando, 8 nov: «no funciona el pellizco»): el `MagnifyGesture` de
/// SwiftUI nunca llegaba a terminar (en la bitácora no había ni un cambio de zoom), con el toque de dos dedos y el arrastre
/// encima. Este convive con ellos.
struct VideoPinch: UIGestureRecognizerRepresentable {
    let changed: (Double) -> Void
    let ended: (Double) -> Void
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPinchGestureRecognizer {
        let pinch = UIPinchGestureRecognizer()
        pinch.delegate = context.coordinator
        pinch.cancelsTouchesInView = false
        return pinch
    }
    func handleUIGestureRecognizerAction(_ recognizer: UIPinchGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .changed: changed(Double(recognizer.scale))
        case .ended: ended(Double(recognizer.scale))
        case .cancelled, .failed: ended(1)
        default: break
        }
    }
}
