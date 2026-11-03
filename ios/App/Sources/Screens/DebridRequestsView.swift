import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// Ajustes › Cuentas › Real-Debrid › Tus pedidos (D3, R13): lo que Real-Debrid está bajando para ti en dos grupos (P1-A):
/// «Bajando» (con cuántas descargas van de tu límite) y «Ya terminaron» (listo o rechazado); un grupo vacío no sale. Cada
/// pedido con su estado en palabras y su avance; tocarlo abre su hoja (P2-B, la misma de la ficha) con «Probar otra versión»
/// si ayuda, «Abrir la ficha» y «Cancelar pedido». Un pedido que lleva 24 h sin avanzar lo dice. La libreta es la de este
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
        .task { await model.refresh(); await model.loadActiveCount() }
        .task {
            #if DEBUG
            // `-demo-rd-sheet mine|other`: la hoja del primer pedido tuyo que tiene problema (o del de otra cuenta), para verla.
            let wanted = Demo.value(after: "-demo-rd-sheet"), other = wanted == "other"
            if Demo.isOn, wanted != nil { await model.refresh() }   // para saber cuál es de otra cuenta
            if Demo.isOn, wanted != nil,
               let first = model.requests.first(where: { other ? model.isOtherAccount($0) : !model.isOtherAccount($0) && DebridRequestWords.suggestsOtherVersion($0, now: Date()) }) {
                opened = Opened(id: first.hash)
            }
            #endif
        }
        .sheet(isPresented: $explaining) { DebridExplainer(close: { explaining = false }).presentationDetents([.large]) }
        .sheet(item: $opened) { which in
            if let request = model.requests.first(where: { $0.hash == which.id }) { sheet(request, model) }
        }
        .confirmationDialog(Text("¿Cancelar el pedido?"), isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
                            titleVisibility: .visible, presenting: cancelling) { request in
            Button("Cancelar pedido", role: .destructive) { cancel(request, model) }
            // Sin esto iOS pone «Cancelar» junto a «Cancelar pedido»: dos «cancelar» que dicen cosas opuestas.
            Button("Seguir esperando", role: .cancel) {}
        } message: { request in Text(verbatim: name(request)) }
    }

    /// Un pedido: tocarlo abre su hoja; deslizarlo o dejar el dedo, lo de siempre.
    private func row(_ request: DebridRequest, _ model: DebridRequestsModel, now: Date) -> some View {
        // De otra cuenta de Real-Debrid (la TV con la suya): se enseña, pero no se cancela desde aquí.
        let other = model.isOtherAccount(request)
        return Button { opened = Opened(id: request.hash) } label: {
            DebridRequestStatus(symbol: DebridRequestWords.symbol(request.state), title: name(request),
                                detail: [DebridRequestWords.short(request, tr), DebridRequestWords.detail(request, now: now, tr)].joined(separator: " · ")
                                    + "\n" + DebridRequestWords.since(request, now: now, otherAccount: other, tr),
                                fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                warn: DebridRequestWords.isTrouble(request, now: now))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions { if !other { Button("Cancelar", role: .destructive) { cancelling = request } } }
        .contextMenu {
            Button("Abrir la ficha", systemImage: "info.circle") { open(request) }
            if !other { Button("Cancelar pedido", systemImage: "xmark.circle", role: .destructive) { cancelling = request } }
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
                                        detail: DebridRequestWords.detail(request, now: now, tr),
                                        fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                        warn: DebridRequestWords.isTrouble(request, now: now)),
            otherVersion: !other && DebridRequestWords.suggestsOtherVersion(request, now: now) ? video.map { v in { opened = nil; open(request, versionsFor: v) } } : nil,
            openTitle: { opened = nil; open(request) },
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

    /// La ficha del pedido; con `versionsFor`, ya con «Versión» abierta en ese video.
    private func open(_ request: DebridRequest, versionsFor video: String? = nil) {
        env.pendingTitle = TitleRoute(kind: request.kind, metaID: request.metaID, title: request.title, poster: nil, versionsFor: video)
    }
}
