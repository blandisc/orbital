import SwiftUI
import OrbitalCore
import OrbitalModels

// Cómo se acomoda la barra de la raíz (aparte de RootView.swift por su presupuesto de 600 renglones).

/// La barra de pestañas arriba de entrada en el iPad (DK1); aparte, para que el cuerpo de la raíz compile a tiempo.
struct TabBarFirst: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
        if Demo.isOn, Demo.has("-demo-sidebar") { return content.defaultAdaptableTabBarPlacement(.sidebar).duoBars() }   // la barra lateral abierta (capturas); duoBars iguala el tipo de las dos ramas
        #endif
        return content.defaultAdaptableTabBarPlacement(.tabBar).duoBars()
    }
}

/// La ficha en la Mac (FI-B): entra por la derecha, cerca de 40 % del ancho, sobre la pantalla oscurecida que sigue ahí.
/// Tocar afuera, la ✕ o Esc la cierran; tocar otro póster la cambia; picar Inicio o Explorar la cierra y cambia de pestaña
/// en un solo clic. Vive en su propia capa (`MacTitleHost`), no encima de esta pantalla: así abrirla no vuelve a acomodar
/// lo de atrás. Aquí solo se le dice en qué ventana vive, qué entorno hereda y cuándo cerrarse.
struct SideTitle: ViewModifier {
    let host: MacTitleHost
    /// Ventana ancha en la Mac: si se angosta con la ficha abierta, se cierra (la ficha pasa a abrirse a pantalla completa).
    let enabled: Bool
    // Lo que la ficha hereda de la pantalla (lo que la app y la raíz le ponen a todo lo de adentro).
    @Environment(AppEnvironment.self) private var app
    @Environment(\.locale) private var locale
    @Environment(\.debridTVNotices) private var debridTVNotices
    @Environment(\.shelfWeeklyArt) private var shelfWeeklyArt
    @Environment(\.titleName) private var titleName
    @Environment(\.playerZoom) private var playerZoom
    @Environment(\.posterQuick) private var posterQuick
    @Environment(\.openRemote) private var openRemote
    @Environment(\.tallArt) private var tallArt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.macTabs) private var tabs

    func body(content: Content) -> some View {
        host.inherit = { [app, locale, debridTVNotices, shelfWeeklyArt, titleName, playerZoom, posterQuick, openRemote, tallArt] panel in
            AnyView(panel.environment(app).environment(\.locale, locale).environment(\.debridTVNotices, debridTVNotices)
                .environment(\.shelfWeeklyArt, shelfWeeklyArt).environment(\.titleName, titleName).environment(\.playerZoom, playerZoom)
                .environment(\.posterQuick, posterQuick).environment(\.openRemote, openRemote).environment(\.tallArt, tallArt)
                .tint(DS.primary))
        }
        host.reduceMotion = reduceMotion
        host.stripBottom = tabs?.stripBottom ?? 0
        return content
            // Con VoiceOver, lo de atrás se esconde mientras la ficha está abierta. Solo con VoiceOver: esconderlo rearma la
            // accesibilidad de todas las pestañas (~250 ms con un cliente de accesibilidad, medido el 24 nov 2026).
            .accessibilityHidden(voiceOver && host.isOpen)
            .background(WindowProbe { host.attach($0) })
            .onChange(of: tabs?.current) { host.hide() }   // otra pestaña: la ficha se cierra
            .onChange(of: enabled) { if !enabled { host.hide() } }
    }
}

/// Dice en qué ventana está la pantalla (para poner la ficha de la Mac en la suya).
private struct WindowProbe: UIViewRepresentable {
    let found: (UIWindow?) -> Void
    func makeUIView(context: Context) -> Probe { Probe(found: found) }
    func updateUIView(_ probe: Probe, context: Context) { probe.found = found }

    final class Probe: UIView {
        var found: (UIWindow?) -> Void
        init(found: @escaping (UIWindow?) -> Void) { self.found = found; super.init(frame: .zero); isUserInteractionEnabled = false }
        required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() { super.didMoveToWindow(); found(window) }
    }
}

extension PlayRequest: @retroactive Identifiable { public var id: String { "\(metaID)|\(videoID)" } }

extension RootView {
    /// Desde dónde sigue en la TV: «desde 12:34», o «desde el principio» si apenas empezaba.
    /// (Un `Text`, no un `String`: así sale en el idioma de la app y no en el del sistema.)
    static func handoffFrom(_ position: Double) -> Text {
        guard position >= DS.Toast.fromStartUnder else { return Text("desde el principio") }
        let time = Duration.seconds(position).formatted(.time(pattern: position >= 3600 ? .hourMinuteSecond : .minuteSecond))
        return Text("desde \(time)")
    }
}

/// Un enlace de fuera (un widget, un aviso, el Centro de control) se ve: lo que tapaba la app (una lección, el control, una
/// hoja de versiones) se cierra antes; la ficha se abría debajo y no pasaba nada a la vista (revisión del 28 nov 2026). La guía
/// de la primera vez y el reproductor se quedan (`keep`). Devuelve si cerró algo (lo de abajo espera a que se vaya).
@MainActor enum LinkCovers {
    static func clear(keep: Bool) -> Bool {
        guard !keep else { return false }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow?.rootViewController,
              root.presentedViewController != nil else { return false }
        root.dismiss(animated: true)
        return true
    }
}
