import SwiftUI
import AVFoundation

@main
struct OrbitalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var env = AppEnvironment.shared

    init() {
        // El idioma de Orbital como idioma preferido de la app (cuenta desde el siguiente arranque): así `Locale.current` ya es
        // español y los textos salen de la tabla en memoria. Con un idioma distinto al del sistema, SwiftUI releía y volvía a
        // analizar `Localizable.strings` del disco por cada texto, en el hilo principal: 16 % de cambiar de pestaña en la Mac
        // (Fernando, 22 nov 2026: «le pico en Explorar y se tarda 3 segundos»).
        let language = AppEnvironment.shared.language
        if (UserDefaults.standard.stringArray(forKey: "AppleLanguages") ?? []).first != language {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
        DiskSpace.warm()   // el espacio libre, medido por detrás: la ficha y Descargas nunca esperan al disco
        // Video con sonido aunque el teléfono esté en silencio (como cualquier reproductor).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        #if AETHER_ENGINE
        EnginePrewarm.install()   // «Ver» arranca con el principio del video que se bajó desde la ficha
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(\.locale, env.uiLocale)
                .environment(\.debridTVNotices, env.services.debridRequests.notifiesTVRequests)   // R14-B: «¿Qué es esto?» lo dice
                .environment(\.titleName, TitleDoor(names: env.services.titleNames))   // un solo nombre por título
                .onAppear { env.applyAppearance() }   // Ajustes › Apariencia (por omisión, la del iPhone), en la ventana
                .tint(DS.primary)
                .toggleStyle(.orbital)   // todo interruptor, prendido en turquesa (`DSSwitchStyle`)
                .tracksWindowSize()   // el tamaño de la ventana para las pantallas (`WindowMetrics`)
                .onAppear { AppWindows.applyMinimumSize() }   // la ventana no se achica más que un iPhone SE (Mac, iPad)
                .onOpenURL { url in Task { await env.handle(url: url) } }
        }
        .commands { AppCommands() }   // la barra de menús del iPad con teclado y de la Mac
    }
}
