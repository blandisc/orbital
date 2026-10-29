import SwiftUI
import AVFoundation

@main
struct OrbitalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var env = AppEnvironment.shared

    init() {
        // Video con sonido aunque el teléfono esté en silencio (como cualquier reproductor).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(\.locale, env.uiLocale)
                .onAppear { env.applyAppearance() }   // Ajustes › Apariencia (por omisión, la del iPhone), en la ventana
                .tint(DS.primary)
                .tracksWindowSize()   // el tamaño de la ventana para las pantallas (`WindowMetrics`)
                .onAppear { AppWindows.applyMinimumSize() }   // la ventana no se achica más que un iPhone SE (Mac, iPad)
                .onOpenURL { url in Task { await env.handle(url: url) } }
        }
        .commands { AppCommands() }   // la barra de menús del iPad con teclado y de la Mac
    }
}
