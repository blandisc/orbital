import AppIntents
import OrbitalCore

// Siri y Atajos: «Oye Siri, dile a Orbital…» manda la orden a tu Orbital como si fuera Alexa (`/api/voice`: misma lógica,
// mismas frases) y Siri dice en voz alta lo que contestó. No abre la app.

/// «Dile a Orbital que ponga The Office»: la orden en texto libre.
struct AskOrbitalIntent: AppIntent {
    static let title: LocalizedStringResource = "Dile a Orbital"
    static let description = IntentDescription("Manda una orden a tu Orbital, como a Alexa: «pon The Office», «pausa», «abre Zelda».")
    static let openAppWhenRun = false

    @Parameter(title: "Orden", requestValueDialog: IntentDialog("¿Qué le digo a Orbital?"))
    var command: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await AppEnvironment.shared.tvNow.say(command)
        let speech = reply.speech.isEmpty ? String(localized: "Listo.") : reply.speech
        return .result(dialog: IntentDialog(stringLiteral: speech))
    }
}

/// «Pausa la TV con Orbital» / «Sigue la TV con Orbital»: lo de todos los días, sin decir la orden.
struct PauseTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Pausar la TV"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppEnvironment.shared.tvNow.control("pause")
        return .result(dialog: "En pausa.")
    }
}

struct ResumeTVIntent: AppIntent {
    static let title: LocalizedStringResource = "Seguir en la TV"
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppEnvironment.shared.tvNow.control("play")
        return .result(dialog: "Sigue.")
    }
}

/// Las frases que Siri reconoce sin configurar nada (aparecen solas en Atajos).
struct OrbitalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskOrbitalIntent(), phrases: [
            "Dile a \(.applicationName)", "Pídele a \(.applicationName)", "Orden para \(.applicationName)",
        ], shortTitle: "Dile a Orbital", systemImageName: "waveform")
        AppShortcut(intent: PauseTVIntent(), phrases: [
            "Pausa la TV con \(.applicationName)", "Pausa \(.applicationName)",
        ], shortTitle: "Pausar la TV", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeTVIntent(), phrases: [
            "Sigue la TV con \(.applicationName)", "Reanuda \(.applicationName)",
        ], shortTitle: "Seguir en la TV", systemImageName: "play.fill")
    }
}
