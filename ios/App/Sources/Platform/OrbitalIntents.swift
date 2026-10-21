import AppIntents
import OrbitalCore
import OrbitalModels

// Siri y Atajos: «Oye Siri, habla con Orbital» pregunta la orden y la atiende como el micrófono del control
// (`VoiceAssistant`): descargar en el iPhone lo hace el teléfono, lo demás tu Orbital como si fuera Alexa (`/api/voice`).
// Siri dice en voz alta lo que contestó. No abre la app.

/// «Dile a Orbital que ponga The Office»: la orden en texto libre.
struct AskOrbitalIntent: AppIntent {
    static let title: LocalizedStringResource = "Habla con Orbital"
    static let description = IntentDescription("Manda una orden a tu Orbital, como a Alexa: «pon The Office», «pausa», «abre Zelda».")
    static let openAppWhenRun = false

    @Parameter(title: "Orden", requestValueDialog: IntentDialog("¿Qué le digo a Orbital?"))
    var command: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let env = AppEnvironment.shared
        let outcome = await VoiceAssistant(services: env.services, tvNow: env.tvNow).handle(command)
        let language = env.services.appSettings.uiLanguage
        // Seguir aquí necesita la pantalla: Siri no abre el reproductor.
        let said = outcome.continueHere ? "Abre Orbital y toca «Seguir aquí»." : outcome.speech
        let speech = said.isEmpty ? String(localized: "Listo.") : Strings.message(said, language: language)
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

/// «Prende Orbital»: prende la tele, la pone en la entrada de la consola y muestra Orbital (como «Alexa, abre Orbital»).
struct TurnOnConsoleIntent: AppIntent {
    static let title: LocalizedStringResource = "Prender la consola"
    static let description = IntentDescription("Prende la tele en la entrada de tu Orbital y muestra la consola.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let env = AppEnvironment.shared
        let outcome = await VoiceAssistant(services: env.services, tvNow: env.tvNow).handle("prende la consola")
        let speech = outcome.speech.isEmpty ? String(localized: "Listo.")
            : Strings.message(outcome.speech, language: env.services.appSettings.uiLanguage)
        return .result(dialog: IntentDialog(stringLiteral: speech))
    }
}

/// Las frases que Siri reconoce sin configurar nada (aparecen solas en Atajos).
struct OrbitalShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Sin «Dile a…»: Siri lo toma como mandar un mensaje a un contacto. Y la orden no va en la frase (los atajos de
        // una app no aceptan texto libre ahí): Siri la pregunta después («¿Qué le digo a Orbital?»).
        AppShortcut(intent: AskOrbitalIntent(), phrases: [
            "Habla con \(.applicationName)", "Orden para \(.applicationName)", "Usa \(.applicationName)", "\(.applicationName)",
        ], shortTitle: "Habla con Orbital", systemImageName: "waveform")
        AppShortcut(intent: TurnOnConsoleIntent(), phrases: [
            "Prende \(.applicationName)", "Enciende \(.applicationName)", "Prende la consola con \(.applicationName)",
        ], shortTitle: "Prender la consola", systemImageName: "power")
        AppShortcut(intent: PauseTVIntent(), phrases: [
            "Pausa la TV con \(.applicationName)", "Pausa \(.applicationName)",
        ], shortTitle: "Pausar la TV", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeTVIntent(), phrases: [
            "Sigue la TV con \(.applicationName)", "Reanuda \(.applicationName)",
        ], shortTitle: "Seguir en la TV", systemImageName: "play.fill")
    }
}
