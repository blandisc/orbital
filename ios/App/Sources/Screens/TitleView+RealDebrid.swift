import SwiftUI
import OrbitalCore
import OrbitalModels
import OrbitalAddons
import UserNotifications

/// Las hojas de Real-Debrid de la ficha: un pedido (R13), «¿Qué es esto?» (O2) y la línea antes de pedir permiso de avisos
/// (R10).
enum TitleDebridSheet: String, Identifiable {
    /// `notifyAppear` y `appear` (IOS-8): la explicación antes de «Avisarme cuando aparezca» y la hoja ya activado.
    case request, explain, notify, notifyAppear, appear
    var id: String { rawValue }
}

/// «Pedir a la nube» en la ficha (R2-A, RX4-A), cuánto lleva (R3, RX2-A) y los estados del pedido (R13).
extension TitleView {
    private var language: String { env.services.appSettings.uiLanguage }
    private func tr(_ key: String) -> String { Strings.tr(key, language: language) }

    /// El botón principal cuando entra Real-Debrid; nil si no aplica (y va el «Ver» de siempre).
    /// - Ya pedido (y la recomendada no arranca al instante): «Bajando en la nube · 42 %», «En cola»… y tocarlo abre el pedido.
    /// - Existe pero Real-Debrid no lo tiene: «Pedir a la nube» toma el lugar de «Ver» (R2-A, igual que la TV), con una
    ///   línea que no promete y, si otro idioma sí arranca, «Verlo en inglés al instante».
    func debridContinueAction(_ model: TitleModel) -> ContinueAction? {
        let requests = env.services.debridRequests
        let _ = requests.track()   // el avance de un pedido vuelve a pintar el botón
        // Qué botón va lo decide el modelo (`TitleModel.primary`, lo mismo que leen los escenarios comunes con la TV).
        let now = Date()
        switch model.primary(now: now) {
        case .request?, .requested?, .otherVersion?: break
        case .onTV?:
            // FQ5-A: lo tiene tu TV con otra cuenta; se manda el título y el episodio (nunca el enlace) y aparte se puede pedir aquí.
            let here: (title: Text, symbol: String, action: () -> Void)? = model.debridOffer.map { _ in (Text("Pedir a la nube aquí"), "arrow.down.circle", { requestFromDebrid(model) }) }
            return ContinueAction(title: Text("Ver en la TV"), symbol: "tv", version: Text("Lo tiene tu TV con otra cuenta"),
                                  play: { Task { await env.playOnTV(kind: model.kind, metaID: model.metaID, videoID: model.kind == "series" ? model.continueVideoID : nil,
                                                                    title: model.title.isEmpty ? model.originalTitle : model.title) } },
                                  aside: here, tint: artAccent)
        default: return nil
        }
        if let request = model.debridRequest, request.state != .ready, request.state != .tooMany {
            let alternative = model.debridOffer.flatMap(instantAside)
            // IOS-7: el mismo «¿Cancelar el pedido?» con «Seguir esperando» que la hoja y la lista (antes cancelaba sin preguntar).
            let cancel: (title: Text, symbol: String, action: () -> Void) = (Text("Cancelar pedido"), "xmark.circle", { cancelling = request })
            // IOS-17: en una serie, qué episodio («T1 E2 · Te aviso cuando esté listo»).
            let episode = DebridRequestNotifier.episodeName(request, language: language)
            let detail = DebridRequestWords.detail(request, now: now, notifies: DebridRequestNotifier.canNotify, tr)   // IOS-8
            // IOS-9: atorado o rechazado, el botón dice la acción («Probar otra versión») y el estado va abajo, en ámbar.
            if DebridRequestWords.suggestsOtherVersion(request, now: now), let video = model.continueVideoID {
                return ContinueAction(title: Text("Probar otra versión"), symbol: "list.bullet.rectangle",
                                      version: Text(verbatim: [episode, DebridRequestWords.title(request, tr)].compactMap { $0 }.joined(separator: " · ")),
                                      play: { openVersions(video) }, aside: alternative ?? cancel, warn: true, tint: artAccent)
            }
            return ContinueAction(title: Text(verbatim: DebridRequestWords.title(request, tr)), symbol: DebridRequestWords.symbol(request.state),
                                  progress: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                  version: Text(verbatim: [episode, detail].compactMap { $0 }.joined(separator: " · ")),
                                  play: { debridSheet = .request }, aside: alternative ?? cancel, tint: artAccent)
        }
        guard let offer = model.debridOffer else { return nil }
        // IOS-19: si la TV ya lo pide con otra cuenta, se dice; pedirlo aparte (con la tuya) sigue a un toque.
        let others = model.otherAccountRequest.map { _ in tr("La TV lo está pidiendo con otra cuenta") }
            // «Muchas descargas activas · Cancela otra descarga para hacer lugar»: lo que contestó la última vez.
            ?? model.debridRequest.flatMap { $0.state == .tooMany ? DebridRequestWords.title($0, tr) + " · " + DebridRequestWords.detail($0, now: now, notifies: false, tr) : nil }
        return ContinueAction(title: Text("Pedir a la nube"), symbol: "arrow.down.circle",
                              version: Text(verbatim: others ?? UnavailableCause.notInDebrid(language: offer.language ?? "").title(tr)),
                              play: { requestFromDebrid(model) }, aside: instantAside(offer), tint: artAccent)
    }

    /// Debajo del botón mientras Real-Debrid lo baja: dónde (en su nube, no en el iPhone), cómo y «¿Qué es esto?».
    @ViewBuilder func debridWhere(_ model: TitleModel) -> some View {
        if let request = model.debridRequest, DebridRequestWords.group(request.state) == .pending {
            DebridWhereLine(notifies: DebridRequestNotifier.canNotify, tv: env.services.orbital.isConfigured) { debridSheet = .explain }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// «Verlo en inglés al instante»: la otra versión que sí arranca.
    private func instantAside(_ offer: DebridOffer) -> (title: Text, symbol: String, action: () -> Void)? {
        guard let code = offer.instantLanguage, let source = offer.instantSource else { return nil }
        let name = Streams.versionLanguageName(code, in: language).lowercased()
        return (Text("Verlo en \(name) al instante"), "play.fill", { start(observerModel, videoID: nil, source: source) })
    }

    /// RX2-A · en la hoja del pedido: «Ver Inglés · 1080p, ya arranca», la misma versión de «Verlo en inglés al instante».
    private func instantInstead(_ offer: DebridOffer) -> (title: Text, action: () -> Void)? {
        guard let code = offer.instantLanguage, let source = offer.instantSource else { return nil }
        let quality = AllSources.quality(source)
        let name = [Streams.versionLanguageName(code, in: language), quality == "Otras" ? nil : quality].compactMap { $0 }.joined(separator: " · ")
        return (Text("Ver \(LanguageFlags.flagged(name, code)), ya arranca"), { debridSheet = nil; start(observerModel, videoID: nil, source: source) })
    }

    /// «Pedir a la nube»: la primera vez, antes de la pregunta de iOS, una línea de para qué son los avisos (R10).
    func requestFromDebrid(_ model: TitleModel) {
        Task {
            if await DebridRequestNotifier.permission() == .notDetermined { debridSheet = .notify; return }
            await sendRequest(model)
        }
    }

    /// Lo pide y dice en segundos qué contestó Real-Debrid (sin prometer que lo logrará, R2).
    /// Con `source`, esa versión de «Versión» › «Hay que pedirlas · tardan» (T8-A), del video `videoID`.
    func sendRequest(_ model: TitleModel, source: Source? = nil, videoID: String? = nil, inYourLanguage: Bool = false) async {
        guard let outcome = await model.requestFromDebrid(source: source, videoID: videoID, inYourLanguage: inYourLanguage,
                                                          onCellular: env.connectivity.isCellular) else { return }
        switch outcome {
        case .requested(let request):
            switch request.state {
            case .refused: tell(.debridRefused, model)
            case .tooMany:
                env.notify(DebridRequestWords.title(request, tr), detail: DebridRequestWords.detail(request, now: Date(), notifies: false, tr), tone: .warn,
                           actionTitle: tr("Abrir")) { UIApplication.shared.open(DebridRequestSheetHost.downloadsURL) }   // IOS-9: con su arreglo
            default:
                let permission = await DebridRequestNotifier.permission()
                if permission == .denied {
                    env.notify(DebridRequestWords.title(request, tr), detail: tr("Avisos apagados · actívalos"), tone: .warn,
                               actionTitle: tr("Ajustes")) { DebridRequestNotifier.openSystemSettings() }
                } else {
                    // IOS-8: con «Ahora no» no se promete avisar.
                    let notifies = DebridRequestNotifier.allows(permission)
                    env.notify(DebridRequestWords.title(request, tr), detail: notifies ? UnavailableCause.downloading(percent: request.percent).detail(tr)
                                                                                       : tr("Ábrelo aquí para ver cuánto lleva"), tone: .success)
                }
            }
        case .failed(let cause?, _): tell(cause, model)
        case .failed(nil, let error): env.notify(error.words(tr), tone: .warn)
        case .nobodyHasIt: tell(.nobodyHasIt, model)
        }
        await model.loadBestSource(onCellular: env.connectivity.isCellular)
    }

    /// FQ1-A · «Pedir a la nube en latino» al lado de «Ver» (que arranca ya en otro idioma de tu orden). nil si no aplica.
    func wantedAside(_ model: TitleModel) -> (title: Text, symbol: String, action: () -> Void)? {
        guard model.wantedOffer != nil, model.primary() == .watch, let code = model.wantedOffer?.language else { return nil }
        let name = Streams.versionLanguageName(code, in: language).lowercased()
        return (Text("Pedir a la nube en \(name)"), "arrow.down.circle", { Task { await sendRequest(model, inYourLanguage: true) } })
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
            DebridExplainer().presentationDragIndicator(.visible)
        case .notify:
            // La misma explicación que en el reproductor (P4-A): una sola pieza.
            DebridNotifyAsk { _ in debridSheet = nil; await sendRequest(model) }
        case .notifyAppear:   // IOS-8: la misma explicación antes de «Avisarme cuando aparezca»
            DebridNotifyAsk { status in debridSheet = nil; startWatching(model, permission: status) }
        case .appear: appearSheet(model)
        case .request:
            if let request = model.debridRequest {
                let name = [request.title, DebridRequestNotifier.episodeName(request, language: language)].compactMap { $0 }.joined(separator: " · ")
                DebridRequestSheetHost(request: request, name: name, since: DebridRequestWords.since(request, now: Date(), tr),
                                       status: DebridRequestStatus(symbol: DebridRequestWords.symbol(request.state), title: DebridRequestWords.title(request, tr),
                                                                   detail: DebridRequestWords.paceLine(request, now: Date(), notifies: DebridRequestNotifier.canNotify, tr),
                                                                   fraction: request.state == .downloading ? Double(request.percent) / 100 : nil,
                                                                   warn: DebridRequestWords.isTrouble(request, now: Date()), ok: request.state == .ready),
                                       instead: model.debridOffer.flatMap(instantInstead),
                                       otherVersion: DebridRequestWords.suggestsOtherVersion(request, now: Date())
                                           ? model.continueVideoID.map { video in { debridSheet = nil; openVersions(video) } } : nil,
                                       openTitle: nil, cancel: { Task { await cancelRequest(request) } },
                                       explain: { debridSheet = .explain }, close: { debridSheet = nil })
                .fittedSheet()
            }
        }
    }
}
