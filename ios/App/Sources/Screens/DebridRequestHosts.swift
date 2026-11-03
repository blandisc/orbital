import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons
import UserNotifications

/// La hoja de un pedido con lo que solo sabe iOS: si los avisos de la app están apagados. La misma en la ficha y en «Tus
/// pedidos» (P2-B). Sin `explain`, «¿Qué es esto?» se abre encima de la hoja.
struct DebridRequestSheetHost: View {
    let request: DebridRequest
    let name: String
    let since: String
    let status: DebridRequestStatus
    let otherVersion: (() -> Void)?
    var openTitle: (() -> Void)?
    let cancel: (() -> Void)?
    var explain: (() -> Void)?
    let close: () -> Void
    @State private var notificationsOff = false
    @State private var explaining = false

    var body: some View {
        DebridRequestSheet(name: name, status: status, since: since, notificationsOff: notificationsOff,
                           turnOnNotifications: { DebridRequestNotifier.openSystemSettings() }, otherVersion: otherVersion,
                           openTitle: openTitle, cancel: cancel, explain: explain ?? { explaining = true }, close: close)
            .task { notificationsOff = await DebridRequestNotifier.permission() == .denied }
            .sheet(isPresented: $explaining) { DebridExplainer(close: { explaining = false }).presentationDetents([.large]) }
    }
}

/// R10 y P4-A · antes de la pregunta de iOS, la primera vez que pides algo (en la ficha o en el reproductor): para qué son
/// los avisos. «Permitir avisos» hace la pregunta de iOS; «Ahora no», no. `done` recibe si quedaron apagados (`denied`):
/// con «Ahora no» siguen sin preguntar (`.notDetermined`). Su aire de hoja lo pone `DebridNotifyPrompt` (dsSheetContent).
struct DebridNotifyAsk: View {
    let done: @MainActor (UNAuthorizationStatus) async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        DebridNotifyPrompt(allow: {
            dismiss()   // la hoja se va antes de la pregunta de iOS
            Task {
                let granted = await DebridRequestNotifier.requestPermission()
                await done(granted ? .authorized : .denied)
            }
        }, notNow: { dismiss(); Task { await done(.notDetermined) } })
        .fittedSheet()
    }
}
