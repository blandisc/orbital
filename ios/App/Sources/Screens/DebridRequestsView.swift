import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// Ajustes › Cuentas › Real-Debrid › Tus pedidos (D3, R13): lo que Real-Debrid está bajando para ti en dos grupos (P1-A):
/// «Bajando» (con cuántas descargas van de tu límite) y «Ya terminaron» (listo o rechazado); un grupo vacío no sale. Cada
/// pedido con su estado en palabras y su avance; tocarlo abre su hoja (P2-B, la misma de la ficha) con «Probar otra versión»
/// si ayuda, «Abrir la ficha» y «Cancelar pedido» (lo terminado: «Ver ahora» y «Quitar de tu Real-Debrid», IOS-7). Un pedido que lleva 24 h sin avanzar lo dice. La libreta es la de este
/// aparato (R12) con la forma común de la TV (acuerdo S2); lo de otra cuenta de Real-Debrid se enseña («Lo pidió la TV · …»)
/// en el grupo de su estado y su hoja solo abre la ficha.
struct DebridRequestsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var explaining = false
    @State private var cancelling: DebridRequest?
    /// La hoja abierta (P2-B), por la huella del pedido: lo que enseña se pone al día mientras baja.
    @State private var opened: Opened?

    struct Opened: Identifiable { let id: String }

    private var language: String { env.services.appSettings.uiLanguage }
    private func tr(_ key: String) -> String { Strings.tr(key, language: language) }

    var body: some View {
        let model = env.services.debridRequests
        let _ = model.track()
        let now = Date()
        let groups = DebridRequestWords.grouped(model.requests)
        Form {
            if groups.isEmpty {
                Section {
                    DSEmptyState(symbol: "arrow.down.circle", title: Text("Sin pedidos"),
                                 message: Text("Cuando pidas algo que Real-Debrid todavía no tiene, aquí ves cuánto lleva."))
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(groups, id: \.group) { part in
                    Section {
                        ForEach(part.requests) { request in row(request, model, now: now) }
                    } header: { header(part.group, model) } footer: {
                        if part.group == groups.last?.group { Text("Toca un pedido para ver qué puedes hacer. Los que terminan se quedan una semana.") }
                    }
                    .listRowBackground(DS.surface)
                }
            }
            Section {
                Button { explaining = true } label: {
                    SettingsRow(title: "¿Qué es esto?", symbol: "questionmark.circle", tint: DS.ListTint.spark, linked: false)
                }
                .accessibilityIdentifier("debrid-requests-explain")
            } footer: { Text("Con la app cerrada, el aviso de que ya está puede tardar: iOS decide cuándo revisar.") }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Tus pedidos").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .refreshable { await model.refresh() }
        .task { _ = await DebridRequestNotifier.permission(); await model.refresh(); await model.loadActiveCount() }
        .task {
            #if DEBUG
            // `-demo-rd-sheet mine|other|ready`: la hoja del primer pedido tuyo que tiene problema (o del de otra cuenta, o del
            // listo: «Ver ahora» y «Quitar de tu Real-Debrid», IOS-7), para verla.
            let wanted = Demo.value(after: "-demo-rd-sheet"), other = wanted == "other", ready = wanted == "ready"
            if Demo.isOn, wanted != nil { await model.refresh() }   // para saber cuál es de otra cuenta
            if Demo.isOn, wanted != nil,
               let first = model.requests.first(where: { ready ? $0.state == .ready && !model.isOtherAccount($0)
                   : other ? model.isOtherAccount($0) : !model.isOtherAccount($0) && DebridRequestWords.suggestsOtherVersion($0, now: Date()) }) {
                opened = Opened(id: first.hash)
            }
            #endif
        }
        .sheet(isPresented: $explaining) { DebridExplainer(close: { explaining = false }) }
        .sheet(item: $opened) { which in
            if let request = model.requests.first(where: { $0.hash == which.id }) { sheet(request, model) }
        }
        // IOS-7: la misma pregunta que la hoja; lo terminado se quita («¿Quitarlo de tu Real-Debrid?»), no se cancela.
        .debridCancelConfirmation(isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
                                  name: cancelling.map(name) ?? "", finished: cancelling.map { DebridRequestWords.group($0.state) == .finished } ?? false) {
            if let request = cancelling { cancel(request, model) }
        }
    }

    /// Un pedido: tocarlo abre su hoja; deslizarlo o dejar el dedo, lo de siempre.
    private func row(_ request: DebridRequest, _ model: DebridRequestsModel, now: Date) -> some View {
        // De otra cuenta de Real-Debrid (la TV con la suya): se enseña, pero no se cancela desde aquí.
        let other = model.isOtherAccount(request)
        let finished = DebridRequestWords.group(request.state) == .finished
        return Button { opened = Opened(id: request.hash) } label: {
            DebridRequestStatus(symbol: DebridRequestWords.symbol(request.state), title: name(request),
                                detail: [DebridRequestWords.short(request, tr), DebridRequestWords.detail(request, now: now, notifies: DebridRequestNotifier.canNotify && model.isFromHere(request), tr)].joined(separator: " · ")
                                    + "\n" + DebridRequestWords.since(request, now: now, otherAccount: other, tr),
                                fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                warn: DebridRequestWords.isTrouble(request, now: now), ok: request.state == .ready)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions { if !other { Button(finished ? "Quitar" : "Cancelar", role: .destructive) { cancelling = request } } }
        .contextMenu {
            Button("Abrir la ficha", systemImage: "info.circle") { open(request) }
            if !other {
                Button(finished ? "Quitar de tu Real-Debrid" : "Cancelar pedido", systemImage: finished ? "trash" : "xmark.circle", role: .destructive) { cancelling = request }
            }
        }
        .accessibilityIdentifier("debrid-request-\(request.hash.prefix(8))")
    }

    /// P2-B · la hoja del pedido, la misma de la ficha. De otra cuenta: solo «Abrir la ficha».
    private func sheet(_ request: DebridRequest, _ model: DebridRequestsModel) -> some View {
        let now = Date()
        let other = model.isOtherAccount(request)
        let video = request.videoIDs.first
        return DebridRequestSheetHost(
            request: request, name: name(request), since: DebridRequestWords.since(request, now: now, otherAccount: other, tr),
            status: DebridRequestStatus(symbol: DebridRequestWords.symbol(request.state), title: DebridRequestWords.title(request, tr),
                                        detail: DebridRequestWords.detail(request, now: now, notifies: DebridRequestNotifier.canNotify && model.isFromHere(request), tr),
                                        fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                        warn: DebridRequestWords.isTrouble(request, now: now), ok: request.state == .ready),
            watchNow: request.state == .ready ? { opened = nil; watch(request) } : nil,
            otherVersion: !other && DebridRequestWords.suggestsOtherVersion(request, now: now) ? video.map { v in { opened = nil; open(request, versionsFor: v) } } : nil,
            openTitle: { opened = nil; open(request) },
            otherAccount: other,
            cancel: other ? nil : { opened = nil; cancel(request, model) },
            close: { opened = nil })
        .fittedSheet()
    }

    /// «Bajando · 3 de 25» (cuántas van de tu límite, si Real-Debrid lo dijo) y «Ya terminaron».
    private func header(_ group: DebridRequestWords.Group, _ model: DebridRequestsModel) -> Text {
        guard group == .pending else { return Text("Ya terminaron") }
        guard let count = model.activeCount, count.limit > 0 else { return Text("Bajando") }
        return Text("Bajando · \(count.active) de \(count.limit)")
    }

    /// «The Office · T1 E2».
    private func name(_ request: DebridRequest) -> String {
        [request.title, DebridRequestNotifier.episodeName(request, language: language)].compactMap { $0 }.joined(separator: " · ")
    }

    private func cancel(_ request: DebridRequest, _ model: DebridRequestsModel) {
        Task { if await !model.cancel(request) { env.notify(tr("No pude hablar con Real-Debrid"), tone: .warn) } }
    }

    /// «Ver ahora» (IOS-7, como la TV): lo listo se ve, sin pasar por la ficha.
    private func watch(_ request: DebridRequest) {
        let title = request.title
        Task {
            await env.play(kind: request.kind, metaID: request.metaID, videoID: request.videoIDs.first ?? request.metaID, title: title,
                           originalTitle: title, episodeLabel: DebridRequestNotifier.episodeName(request, language: language) ?? "", poster: nil)
        }
    }

    /// La ficha del pedido; con `versionsFor`, ya con «Versión» abierta en ese video.
    private func open(_ request: DebridRequest, versionsFor video: String? = nil) {
        env.pendingTitle = TitleRoute(kind: request.kind, metaID: request.metaID, title: request.title, poster: nil, versionsFor: video)
    }
}
