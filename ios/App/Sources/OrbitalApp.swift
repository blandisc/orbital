import SwiftUI
import AVFoundation

@main
struct OrbitalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var env = AppEnvironment.shared

    init() {
        // Video con sonido aunque el teléfono esté en silencio (como cualquier reproductor).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environment(\.locale, env.uiLocale)
                .preferredColorScheme(.dark)
                .tint(DS.primary)
                .onAppear { AppDelegate.downloads = env.transport }
                .onOpenURL { url in Task { await env.handle(url: url) } }
        }
    }
}
