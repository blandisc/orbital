import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// Ajustes › Cuentas › Real-Debrid › Tus pedidos (D3, R13): lo que Real-Debrid está bajando para ti, tus pedidos primero,
/// cada uno con su estado en palabras, su avance y «Cancelar»; y cuántas descargas van de tu límite. Un pedido que lleva
/// 24 h sin avanzar lo dice. La libreta es la de este aparato (R12); la de la TV se junta en S2/S4.
struct DebridRequestsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var explaining = false
    @State private var cancelling: DebridRequest?

    private var language: String { env.services.appSettings.uiLanguage }
    private func tr(_ key: String) -> String { Strings.tr(key, language: language) }

    var body: some View {
        let model = env.services.debridRequests
        let _ = model.track()
        let now = Date()
        Form {
            if model.requests.isEmpty {
                Section {
                    DSEmptyState(symbol: "arrow.down.circle", title: Text("Sin pedidos"),
                                 message: Text("Cuando pidas algo que Real-Debrid todavía no tiene, aquí ves cuánto lleva."))
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(model.requests) { request in
                        DebridRequestStatus(symbol: DebridRequestWords.symbol(request.state), title: name(request),
                                            detail: [DebridRequestWords.short(request, tr), DebridRequestWords.detail(request, now: now, tr)].joined(separator: " · ")
                                                + "\n" + DebridRequestWords.since(request, now: now, tr),
                                            fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                            warn: DebridRequestWords.isTrouble(request, now: now))
                            .swipeActions { Button("Cancelar", role: .destructive) { cancelling = request } }
                            .contextMenu {
                                Button("Abrir la ficha", systemImage: "info.circle") { open(request) }
                                Button("Cancelar pedido", systemImage: "xmark.circle", role: .destructive) { cancelling = request }
                            }
                            .accessibilityIdentifier("debrid-request-\(request.hash.prefix(8))")
                    }
                } header: { header(model) } footer: {
                    Text("Desliza un pedido para cancelarlo. Los que terminan se quedan una semana.")
                }
                .listRowBackground(DS.surface)
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
        .sheet(isPresented: $explaining) { DebridExplainer(close: { explaining = false }).presentationDetents([.large]) }
        .confirmationDialog(Text("¿Cancelar el pedido?"), isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
                            titleVisibility: .visible, presenting: cancelling) { request in
            Button("Cancelar pedido", role: .destructive) {
                Task { if await !model.cancel(request) { env.notify(tr("No pude hablar con Real-Debrid"), tone: .warn) } }
            }
        } message: { request in Text(verbatim: name(request)) }
    }

    /// «Bajando para ti · 3 de 25»: cuántas van de tu límite (si Real-Debrid lo dijo).
    private func header(_ model: DebridRequestsModel) -> Text {
        guard let count = model.activeCount, count.limit > 0 else { return Text("Bajando para ti") }
        return Text("Bajando para ti · \(count.active) de \(count.limit)")
    }

    /// «The Office · T1 E2».
    private func name(_ request: DebridRequest) -> String {
        [request.title, DebridRequestNotifier.episodeName(request, language: language)].compactMap { $0 }.joined(separator: " · ")
    }

    private func open(_ request: DebridRequest) {
        if let link = WidgetLink.title(kind: request.kind, id: request.metaID) as URL? { Task { await env.handle(url: link) } }
    }
}
