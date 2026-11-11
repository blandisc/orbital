import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons

/// RX1-A (Fernando, 3 nov: «RX1A me gusta»): lo que pides a la nube vive en Descargas, donde lo buscas, en su propia parte:
/// «Lo que pediste» (esto) arriba de «En este iPhone · sin internet». Antes era Ajustes › Cuentas › Real-Debrid ›
/// «Tus pedidos», que ahora solo trae aquí. Los dos grupos de siempre (P1-A): «Bajando» (con cuántas van de tu límite) y «Ya
/// terminaron»; un grupo vacío no sale y, sin ningún pedido, el vacío con su única salida («¿Qué es esto?»). Cada pedido con
/// su estado en palabras y su avance; tocarlo abre su hoja (P2-B, la misma de la ficha) con «Probar otra versión» si ayuda,
/// «Abrir la ficha» y «Cancelar pedido» (lo terminado: «Ver ahora» y «Quitar de tu Real-Debrid», IOS-7). La libreta es la de
/// este aparato (R12) con la forma común de la TV (acuerdo S2); lo de otra cuenta de Real-Debrid se enseña («Lo pidió la TV ·
/// …») en el grupo de su estado y su hoja solo abre la ficha. Solo donde hay Real-Debrid (`shows`): Plus y App Store sin él
/// no tienen nube.
struct DownloadsCloudPart: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var sheets: CloudSheets

    /// Hay nube: tienes clave de Real-Debrid o algún pedido en la libreta.
    @MainActor static func shows(_ services: Services) -> Bool {
        services.debrid.hasToken || !services.debridRequests.requests.isEmpty
    }

    var body: some View {
        let model = env.services.debridRequests
        let _ = model.track()
        let now = Date()
        let groups = DebridRequestWords.grouped(model.requests)
        if groups.isEmpty {
            Section {
                chapter
                DSEmptyState(symbol: DS.Symbol.cloud, title: Text("Nada en la nube"),
                             message: DeviceWords.text("Cuando pidas algo a la nube, aquí ves cuánto lleva. No ocupa espacio en este iPhone.",
                                                       mac: "Cuando pidas algo a la nube, aquí ves cuánto lleva. No ocupa espacio en esta Mac.")) {
                    Button("¿Qué es esto?") { sheets.explaining = true }.accessibilityIdentifier("cloud-empty-explain")
                }
                .listRowBackground(Color.clear)
            }
            .downloadCard()
        } else {
            ForEach(Array(groups.enumerated()), id: \.element.group) { index, part in
                Section {
                    if index == 0 { chapter }
                    DSSectionHead(title: header(part.group, model)).listHeadRow()
                    ForEach(part.requests) { request in row(request, model, now: now) }
                } footer: {
                    if index == groups.count - 1 { footer }
                }
                .downloadCard()
            }
        }
    }

    /// «Lo que pediste» (T9, 10 nov, como la TV; antes «Real-Debrid · bajando para ti»). Una sección va sola, sin porqué: de
    /// dónde viene lo dice «¿Qué es esto?» al pie (en la TV, el sello de Real-Debrid de su fila). No «En la nube», que se confundiría con Mi media (tu OneDrive, Plex…); la palabra «nube»
    /// queda en los textos del pedido («Pedir a la nube», «Bajando en la nube · 42 %»).
    private var chapter: some View {
        DSSectionHead(title: Text("Lo que pediste"), level: .section, symbol: DS.Symbol.cloud).listHeadRow()
            .accessibilityIdentifier("downloads-cloud")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Toca un pedido para ver qué puedes hacer. Los que terminan se quedan una semana.").recipe(.footnote)
            Button("¿Qué es esto?") { sheets.explaining = true }
                .font(DS.TextRecipe.label.font).buttonStyle(.borderless).tint(DS.accent)
                .frame(minHeight: DS.Size.touchTarget)
                .accessibilityIdentifier("debrid-requests-explain")
        }
    }

    /// Un pedido: tocarlo abre su hoja; deslizarlo o dejar el dedo, lo de siempre.
    private func row(_ request: DebridRequest, _ model: DebridRequestsModel, now: Date) -> some View {
        // De otra cuenta de Real-Debrid (la TV con la suya): se enseña, pero no se cancela desde aquí.
        let other = model.isOtherAccount(request)
        let finished = DebridRequestWords.group(request.state) == .finished
        let tr = CloudWords(env).tr
        return Button { sheets.opened = .init(id: request.hash) } label: {
            DebridRequestStatus(symbol: DebridRequestWords.symbol(request.state), title: CloudWords(env).name(request),
                                detail: [DebridRequestWords.title(request, tr), DebridRequestWords.detail(request, now: now, notifies: DebridRequestNotifier.canNotify && model.isFromHere(request), tr)].joined(separator: " · ")
                                    + "\n" + DebridRequestWords.since(request, now: now, otherAccount: other, tr),
                                fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                warn: DebridRequestWords.isTrouble(request, now: now), ok: request.state == .ready)
                .padding(.vertical, DS.Space.s1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Sin `role: .destructive`: pregunta antes, y con él iOS quitaba la fila y la regresaba (igual que en Complementos).
        .swipeActions { if !other { Button(finished ? "Quitar" : "Cancelar") { sheets.cancelling = request }.tint(DS.danger) } }
        .contextMenu {
            Button("Abrir la ficha", systemImage: "info.circle") { CloudWords(env).open(request) }
            if !other {
                Button(finished ? "Quitar de tu Real-Debrid" : "Cancelar pedido", systemImage: finished ? DebridRequestWords.Icon.remove : DebridRequestWords.Icon.cancel, role: .destructive) { sheets.cancelling = request }
            }
        }
        .accessibilityIdentifier("debrid-request-\(request.hash.prefix(8))")
    }

    /// «Bajando · 3 de 25» (cuántas van de tu límite, si Real-Debrid lo dijo) y «Ya terminaron».
    private func header(_ group: DebridRequestWords.Group, _ model: DebridRequestsModel) -> Text {
        guard group == .pending else { return Text("Ya terminaron") }
        guard let count = model.activeCount, count.limit > 0 else { return Text("Bajando") }
        return Text("Bajando · \(count.active) de \(count.limit)")
    }
}

/// Las hojas de la parte de la nube (van en la lista entera, no en cada sección): el pedido abierto, el que se cancela y
/// «¿Qué es esto?».
struct CloudSheets {
    struct Opened: Identifiable { let id: String }
    /// La hoja abierta (P2-B), por la huella del pedido: lo que enseña se pone al día mientras baja.
    var opened: Opened?
    var cancelling: DebridRequest?
    var explaining = false
}

/// Pone las hojas de la nube en Descargas y la pone al día al abrir (y al jalar la lista).
struct CloudSheetsHost: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Binding var sheets: CloudSheets
    let active: Bool

    func body(content: Content) -> some View {
        let model = env.services.debridRequests
        content
            .refreshable { if active { await model.refresh() } }
            .task(id: active) {
                guard active else { return }
                _ = await DebridRequestNotifier.permission(); await model.refresh(); await model.loadActiveCount()
                #if DEBUG
                // `-demo-rd-sheet mine|other|ready`: la hoja del primer pedido tuyo que tiene problema (o del de otra cuenta, o del
                // listo: «Ver ahora» y «Quitar de tu Real-Debrid», IOS-7), para verla.
                let wanted = Demo.value(after: "-demo-rd-sheet"), other = wanted == "other", ready = wanted == "ready"
                if Demo.isOn, wanted != nil,
                   let first = model.requests.first(where: { ready ? $0.state == .ready && !model.isOtherAccount($0)
                       : other ? model.isOtherAccount($0) : !model.isOtherAccount($0) && DebridRequestWords.suggestsOtherVersion($0, now: Date()) }) {
                    sheets.opened = .init(id: first.hash)
                }
                #endif
            }
            .sheet(isPresented: $sheets.explaining) { DebridExplainer() }
            .sheet(item: $sheets.opened) { which in
                if let request = model.requests.first(where: { $0.hash == which.id }) { sheet(request, model) }
            }
            // IOS-7: la misma pregunta que la hoja; lo terminado se quita («¿Quitarlo de tu Real-Debrid?»), no se cancela.
            .debridCancelConfirmation(isPresented: Binding(get: { sheets.cancelling != nil }, set: { if !$0 { sheets.cancelling = nil } }),
                                      name: sheets.cancelling.map(CloudWords(env).name) ?? "",
                                      finished: sheets.cancelling.map { DebridRequestWords.group($0.state) == .finished } ?? false) {
                if let request = sheets.cancelling { CloudWords(env).cancel(request) }
            }
    }

    /// P2-B · la hoja del pedido, la misma de la ficha (RX2-A: cuánto falta). De otra cuenta: solo «Abrir la ficha».
    private func sheet(_ request: DebridRequest, _ model: DebridRequestsModel) -> some View {
        let now = Date()
        let other = model.isOtherAccount(request)
        let video = request.videoIDs.first
        let words = CloudWords(env)
        let notifies = DebridRequestNotifier.canNotify && model.isFromHere(request)
        return DebridRequestSheetHost(
            request: request, name: words.name(request), since: DebridRequestWords.since(request, now: now, otherAccount: other, words.tr),
            status: DebridRequestStatus(symbol: DebridRequestWords.symbol(request.state), title: DebridRequestWords.title(request, words.tr),
                                        detail: DebridRequestWords.paceLine(request, now: now, notifies: notifies, words.tr),
                                        fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                        warn: DebridRequestWords.isTrouble(request, now: now), ok: request.state == .ready),
            watchNow: request.state == .ready ? { sheets.opened = nil; words.watch(request) } : nil,
            otherVersion: !other && DebridRequestWords.suggestsOtherVersion(request, now: now) ? video.map { v in { sheets.opened = nil; words.open(request, versionsFor: v) } } : nil,
            openTitle: { sheets.opened = nil; words.open(request) },
            otherAccount: other,
            cancel: other ? nil : { sheets.opened = nil; words.cancel(request) },
            close: { sheets.opened = nil })
        .fittedSheet()
    }
}

/// Lo que la parte de la nube dice y hace con un pedido (en la lista y en su hoja).
@MainActor struct CloudWords {
    let env: AppEnvironment
    init(_ env: AppEnvironment) { self.env = env }

    private var language: String { env.services.appSettings.uiLanguage }
    func tr(_ key: String) -> String { Strings.tr(key, language: language) }

    /// «The Office · T1 E2».
    func name(_ request: DebridRequest) -> String {
        [request.title, DebridRequestNotifier.episodeName(request, language: language)].compactMap { $0 }.joined(separator: " · ")
    }

    func cancel(_ request: DebridRequest) {
        let env = env, message = tr("No pude hablar con Real-Debrid")
        Task { if await !env.services.debridRequests.cancel(request) { env.notify(message, tone: .warn) } }
    }

    /// «Ver ahora» (IOS-7, como la TV): lo listo se ve, sin pasar por la ficha.
    func watch(_ request: DebridRequest) {
        let env = env, title = request.title, episode = DebridRequestNotifier.episodeName(request, language: language) ?? ""
        Task {
            await env.play(kind: request.kind, metaID: request.metaID, videoID: request.videoIDs.first ?? request.metaID, title: title,
                           originalTitle: title, episodeLabel: episode, poster: nil)
        }
    }

    /// La ficha del pedido; con `versionsFor`, ya con «Versión» abierta en ese video.
    func open(_ request: DebridRequest, versionsFor video: String? = nil) {
        env.pendingTitle = TitleRoute(kind: request.kind, metaID: request.metaID, title: request.title, poster: nil, versionsFor: video)
    }
}
