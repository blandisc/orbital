import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons
import UserNotifications

/// Las hojas de Real-Debrid de la ficha: un pedido (R13), «¿Qué es esto?» (O2) y la línea antes de pedir permiso de avisos
/// (R10).
enum TitleDebridSheet: String, Identifiable {
    case request, explain, notify
    var id: String { rawValue }
}

/// «Pedirlo y avisarme» en la ficha (R2-A), cuánto lleva (R3) y los estados del pedido (R13).
extension TitleView {
    private var language: String { env.services.appSettings.uiLanguage }
    private func tr(_ key: String) -> String { Strings.tr(key, language: language) }

    /// El botón principal cuando entra Real-Debrid; nil si no aplica (y va el «Ver» de siempre).
    /// - Ya pedido (y la recomendada no arranca al instante): «Bajando en Real-Debrid · 42 %», «En cola»… y tocarlo abre el pedido.
    /// - Existe pero Real-Debrid no lo tiene: «Pedirlo y avisarme» toma el lugar de «Ver» (R2-A, igual que la TV), con una
    ///   línea que no promete y, si otro idioma sí arranca, «Verlo en inglés al instante».
    func debridContinueAction(_ model: TitleModel) -> ContinueAction? {
        let requests = env.services.debridRequests
        let _ = requests.track()   // el avance de un pedido vuelve a pintar el botón
        guard model.continueAirs == nil, model.recommendedSource?.instant != true else { return nil }
        let now = Date()
        if let request = model.debridRequest, request.state != .ready {
            let alternative = model.debridOffer.flatMap(instantAside)
            let cancel: (title: Text, symbol: String, action: () -> Void) = (Text("Cancelar pedido"), "xmark.circle", { Task { await cancelRequest(request) } })
            return ContinueAction(title: Text(verbatim: DebridRequestWords.title(request, tr)), symbol: DebridRequestWords.symbol(request.state),
                                  progress: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                  version: Text(verbatim: DebridRequestWords.detail(request, now: now, tr)),
                                  play: { debridSheet = .request }, aside: alternative ?? cancel, tint: artAccent)
        }
        guard let offer = model.debridOffer, model.sourceCheck != .offline else { return nil }
        return ContinueAction(title: Text("Pedirlo y avisarme"), symbol: "arrow.down.circle",
                              version: Text(verbatim: UnavailableCause.notInDebrid(language: offer.language ?? "").title(tr)),
                              play: { requestFromDebrid(model) }, aside: instantAside(offer), tint: artAccent)
    }

    /// «Verlo en inglés al instante»: la otra versión que sí arranca.
    private func instantAside(_ offer: DebridOffer) -> (title: Text, symbol: String, action: () -> Void)? {
        guard let code = offer.instantLanguage, let source = offer.instantSource else { return nil }
        let name = Streams.versionLanguageName(code, in: language).lowercased()
        return (Text("Verlo en \(name) al instante"), "play.fill", { start(observerModel, videoID: nil, source: source) })
    }

    /// «Pedirlo y avisarme»: la primera vez, antes de la pregunta de iOS, una línea de para qué son los avisos (R10).
    func requestFromDebrid(_ model: TitleModel) {
        Task {
            if await DebridRequestNotifier.permission() == .notDetermined { debridSheet = .notify; return }
            await sendRequest(model)
        }
    }

    /// Lo pide y dice en segundos qué contestó Real-Debrid (sin prometer que lo logrará, R2).
    func sendRequest(_ model: TitleModel) async {
        guard let outcome = await model.requestFromDebrid(onCellular: env.connectivity.isCellular) else { return }
        switch outcome {
        case .requested(let request):
            switch request.state {
            case .refused: tell(.debridRefused, model)
            case .tooMany:
                env.notify(DebridRequestWords.title(request, tr), detail: DebridRequestWords.detail(request, now: Date(), tr), tone: .warn)
            default:
                let off = await DebridRequestNotifier.permission() == .denied
                if off {
                    env.notify(DebridRequestWords.title(request, tr), detail: tr("Avisos apagados · actívalos"), tone: .warn,
                               actionTitle: tr("Ajustes")) { DebridRequestNotifier.openSystemSettings() }
                } else {
                    env.notify(DebridRequestWords.title(request, tr), detail: UnavailableCause.downloading(percent: request.percent).detail(tr), tone: .success)
                }
            }
        case .failed(let cause?, _): tell(cause, model)
        case .failed(nil, let error): env.notify(error.words(tr), tone: .warn)
        case .nobodyHasIt: tell(.nobodyHasIt, model)
        }
        await model.loadBestSource(onCellular: env.connectivity.isCellular)
    }

    /// «Cancelar pedido».
    func cancelRequest(_ request: DebridRequest) async {
        debridSheet = nil
        if await env.services.debridRequests.cancel(request) {
            env.notify(tr("Pedido cancelado"), detail: request.title, tone: .info)
            await observerModel.loadBestSource(onCellular: env.connectivity.isCellular)
        } else {
            env.notify(tr("No pude hablar con Real-Debrid"), tone: .warn)
        }
    }

    /// La hoja que toca.
    @ViewBuilder func debridSheetContent(_ kind: TitleDebridSheet, _ model: TitleModel) -> some View {
        switch kind {
        case .explain:
            DebridExplainer(close: { debridSheet = nil }).presentationDetents([.large]).presentationDragIndicator(.visible)
        case .notify:
            // La misma explicación que en el reproductor (P4-A): una sola pieza.
            DebridNotifyAsk { _ in debridSheet = nil; await sendRequest(model) }
        case .request:
            if let request = model.debridRequest {
                let name = [request.title, DebridRequestNotifier.episodeName(request, language: language)].compactMap { $0 }.joined(separator: " · ")
                DebridRequestSheetHost(request: request, name: name, since: DebridRequestWords.since(request, now: Date(), tr),
                                       status: DebridRequestStatus(symbol: DebridRequestWords.symbol(request.state), title: DebridRequestWords.title(request, tr),
                                                                   detail: DebridRequestWords.detail(request, now: Date(), tr),
                                                                   fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                                                   warn: DebridRequestWords.isTrouble(request, now: Date())),
                                       otherVersion: DebridRequestWords.suggestsOtherVersion(request, now: Date())
                                           ? model.continueVideoID.map { video in { debridSheet = nil; openVersions(video) } } : nil,
                                       openTitle: nil, cancel: { Task { await cancelRequest(request) } },
                                       explain: { debridSheet = .explain }, close: { debridSheet = nil })
                .fittedSheet()
            }
        }
    }
}
