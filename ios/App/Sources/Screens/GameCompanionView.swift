import SwiftUI
import UserNotifications
import OrbitalCore
import OrbitalModels

/// Modo acompañante (una hoja, como el control: se abre desde el accesorio mientras juegas en la consola): la tarjeta del
/// juego y, debajo, un carrusel con la consola,
/// la guía, tus notas, el temporizador y, en juegos de emulador, sus controles. Avisa en el iPhone cuando la batería de la
/// consola baja, cuando se cumple el temporizador y 10 minutos antes de que un juego en pausa se cierre solo.
struct GameCompanionView: View {
    @ObservedObject var tvNow: ModelObserver<TVNowModel>
    let game: OrbitalRemote.Game
    @EnvironmentObject private var env: AppEnvironment
    @State private var notes = ""
    @State private var timerEnds: Date?

    var body: some View {
        let m = tvNow.model
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            GameNowCard(game: game, busy: m.busy,
                        onResume: { Task { await m.game("resume") } },
                        onHome: { Task { await m.game("home") } },
                        onClose: { Task { await m.game("close") } })
                .padding(.horizontal, DS.Space.gutter)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DS.Space.s3) {
                    ConsoleStatePanel(state: m.console,
                                      setPower: { mode in Task { await m.setConsole(powerMode: mode) } },
                                      closeApp: { app in Task { await m.setConsole(closeApp: app) } })
                    GuidePanel(game: game)
                    NotesPanel(text: $notes)
                    TimerPanel(endsAt: timerEnds, start: startTimer, cancel: cancelTimer)
                    if ControlsPanel.supports(game.system) { ControlsPanel(system: game.system) }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
        .task(id: game.id) {
            notes = env.services.kv.data(notesKey).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            timerEnds = env.services.kv.data(timerKey).flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
            await m.refreshConsole()
        }
        .onChange(of: notes) { _, text in env.services.kv.set(notesKey, data: text.data(using: .utf8)) }
    }

    private var notesKey: String { "game-notes.\(game.id)" }
    private var timerKey: String { "game-timer.\(game.id)" }

    // MARK: avisos
    private func startTimer(_ minutes: Int) {
        let ends = Date().addingTimeInterval(Double(minutes) * 60)
        timerEnds = ends
        env.services.kv.set(timerKey, data: try? JSONEncoder().encode(ends))
        notify(id: timerKey, title: Strings.tr("Se cumplió tu tiempo", language: language),
               body: String(format: Strings.tr("Llevas %@ en %@.", language: language), Strings.duration(minutes), game.title), at: ends)
    }

    private func cancelTimer() {
        timerEnds = nil
        env.services.kv.set(timerKey, data: nil)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timerKey])
    }

    private var language: String { env.services.appSettings.uiLanguage }

    private func notify(id: String, title: String, body: String, at: Date?) {
        CompanionAlerts.notify(id: id, title: title, body: body, at: at)
    }
}

/// Los avisos del modo acompañante, con la hoja abierta o no (los vigila la app entera, no la hoja): batería baja de la
/// consola y diez minutos antes de que un juego en pausa se cierre solo.
@MainActor
enum CompanionAlerts {
    /// A la batería baja de la consola, una vez por juego: vibración y aviso.
    static func warnBattery(_ env: AppEnvironment, game: OrbitalRemote.Game, percent: Int?, plugged: Bool) {
        guard let percent, !plugged, percent <= DS.Companion.lowBattery else { return }
        let key = "game-battery-warned.\(game.id).\(Int(game.started?.timeIntervalSince1970 ?? 0))"
        guard env.services.kv.data(key) == nil else { return }
        env.services.kv.set(key, data: Data([1]))
        let language = env.services.appSettings.uiLanguage
        env.notify(format: "A la consola le queda %lld %% de batería.", percent, tone: .warn)
        notify(id: key, title: Strings.tr("Batería baja en la consola", language: language),
               body: String(format: Strings.tr("Le queda %lld %%: conéctala antes de que se apague.", language: language), percent), at: nil)
    }

    /// Diez minutos antes de que un juego en pausa se cierre solo (sin pausa, nada pendiente).
    static func scheduleCloseWarning(_ env: AppEnvironment, game: OrbitalRemote.Game?) {
        let center = UNUserNotificationCenter.current()
        guard let game else { return }
        let id = "game-closing.\(game.id)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let at = game.closesAt else { return }
        let language = env.services.appSettings.uiLanguage
        notify(id: id, title: Strings.tr("El juego se va a cerrar", language: language),
               body: String(format: Strings.tr("%@ lleva rato en pausa: se cierra solo en 10 minutos.", language: language), game.title),
               at: at.addingTimeInterval(-DS.Companion.closeWarning))
    }

    static func notify(id: String, title: String, body: String, at: Date?) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            let seconds = max(1, (at ?? Date()).timeIntervalSinceNow)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
        }
    }
}
