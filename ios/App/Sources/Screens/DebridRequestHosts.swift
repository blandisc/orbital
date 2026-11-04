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
    var watchNow: (() -> Void)?
    let otherVersion: (() -> Void)?
    var openTitle: (() -> Void)?
    var otherAccount = false
    let cancel: (() -> Void)?
    var explain: (() -> Void)?
    let close: () -> Void
    @State private var notificationsOff = false
    @State private var explaining = false
    /// Tus descargas en Real-Debrid (IOS-9: el arreglo de «Muchas descargas activas»).
    static let downloadsURL = URL(string: "https://real-debrid.com/torrents")!

    var body: some View {
        DebridRequestSheet(name: name, status: status, since: since, notificationsOff: notificationsOff,
                           turnOnNotifications: { DebridRequestNotifier.openSystemSettings() }, watchNow: watchNow, otherVersion: otherVersion,
                           openTitle: openTitle, finished: DebridRequestWords.group(request.state) == .finished, otherAccount: otherAccount,
                           manageDownloads: request.state == .tooMany && !otherAccount ? Self.downloadsURL : nil,
                           cancel: cancel, explain: explain ?? { explaining = true }, close: close,
                           notifies: DebridRequestNotifier.canNotify, tv: AppEnvironment.shared.services.orbital.isConfigured)
            .task { notificationsOff = await DebridRequestNotifier.permission() == .denied }
            .sheet(isPresented: $explaining) { DebridExplainer(close: { explaining = false }) }
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
        }, notNow: { dismiss(); Task { await done(.notDetermined) } }, tv: AppEnvironment.shared.services.orbital.isConfigured)
        .fittedSheet()
    }
}
