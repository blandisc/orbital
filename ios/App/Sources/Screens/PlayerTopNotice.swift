import SwiftUI
import OrbitalCore

/// El aviso de texto de arriba del reproductor: uno solo a la vez. Antes cada aviso (la versión, la guía del pellizco, el de
/// subtítulos, el de la imagen y el del zoom) se pintaba por su lado en el mismo lugar y al pellizcar chocaban dos (Fernando,
/// 23 nov 2026). Regla en `docs/ios-interfaz.md` § «Un aviso arriba a la vez»; `DesignRulesTests+TopNotice` la cuida.
enum PlayerTopNotice {
    case notice(PlayerScreen.PlayerNotice), pinch, zoom(VideoZoom), subtitle(String), framed
}

extension PlayerScreen {
    /// Cuál se ve. Primero lo que haces con los dedos (la guía del pellizco, mientras dura), luego el aviso con botones, luego el
    /// resultado de lo que acabas de hacer (el zoom) y al final lo que solo informa. Con el candado, ninguno (lo dice la cápsula).
    /// Los que no caben no se pierden: cada uno tiene su propio reloj y sale si sigue vigente cuando se libera el lugar.
    var topNotice: PlayerTopNotice? {
        guard !padlock.lockNoticeVisible else { return nil }
        if framing.pinching { return .pinch }
        if let notice = notices.notice { return .notice(notice) }
        if let shown = framing.zoomToast { return .zoom(shown) }
        if let text = notices.subtitleToast { return .subtitle(text) }
        if framing.framedToast { return .framed }
        return nil
    }

    /// La píldora de arriba, la misma para todos los avisos breves (sin tocar su forma: `DSToastPill`).
    func topPill(_ text: LocalizedStringKey, detail: Text? = nil) -> some View {
        VStack { DSToastPill(text: text, detail: detail); Spacer() }
            .padding(.top, DS.Space.s16)
            .transition(.opacity).allowsHitTesting(false).accessibilityHidden(true)
    }
}
