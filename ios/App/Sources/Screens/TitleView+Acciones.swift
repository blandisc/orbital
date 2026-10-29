import SwiftUI
import OrbitalCore
import OrbitalModels

/// Lo que hace la ficha al tocar: ver, guardar, descargar, en la TV y los avisos que dejan.
extension TitleView {
    // MARK: acciones
    /// «Ver»: si ya se sabe que no hay fuentes (o no hay red), lo dice aquí en vez de abrir un reproductor que va a fallar.
    func play(_ model: TitleModel) {
        switch model.sourceCheck {
        case .none: env.notify("Real-Debrid aún no lo tiene", detail: "Los estrenos suelen llegar unas horas después")
        case .offline: env.notify("Sin internet", detail: "No pude buscar dónde verlo", tone: .warn, actionTitle: "Reintentar") { play(model) }
        default: start(model, videoID: nil)
        }
    }

    func start(_ model: TitleModel, videoID: String?, source: Source? = nil, fromStart: Bool = false) {
        guard var request = model.playRequest(videoID: videoID) else { return }
        request.sourceIndex = source?.index
        request.fromStart = fromStart
        if env.services.appSettings.preferInfuse { Task { await env.playExternal(request, source: source) } } else { env.play(request) }
    }

    func handle(source: Source, videoID: String, purpose: Purpose, model: TitleModel) {
        switch purpose {
        case .watch: start(model, videoID: videoID, source: source)
        case .download:
            // Ya hay una copia (o se está bajando): una sola por película o episodio, así que se pregunta si cambiarla.
            Task {
                if let existing = await model.existingDownload(videoID) { replacing = Replacement(source: source, videoID: videoID, existing: existing); return }
                await report(model.download([videoID], source: source), model, videoID: videoID)   // la fuente que elegiste
            }
        }
    }

    /// «4K · Dolby Vision» y «12.3 GB · Torrentio» (o «Bajando 40 % · Torrentio») para la hoja «Ya la tienes».
    func describe(_ item: DownloadItem) -> (label: String, detail: Text) {
        let size = item.expectedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        let tail = item.addon.isEmpty ? "" : " · \(item.addon)"
        if item.state != .done, let expected = item.expectedBytes, expected > 0 {
            let percent = "\(Int(Double(item.writtenBytes) / Double(expected) * 100)) %"
            return (item.quality ?? item.addon, Text("\(Text("Bajando \(percent)"))\(Text(verbatim: tail))"))
        }
        return (item.quality ?? item.addon, Text(verbatim: size + tail))
    }

    func describe(_ source: Source) -> (label: String, detail: Text) {
        let label = ([source.resolution] + source.hdr).filter { !$0.isEmpty }.joined(separator: " · ")
        let size = source.size > 0 ? ByteCountFormatter.string(fromByteCount: Int64(source.size), countStyle: .file) : nil
        return (label.isEmpty ? source.addon : label, Text(verbatim: [size, source.addon.isEmpty ? nil : source.addon].compactMap { $0 }.joined(separator: " · ")))
    }

    func report(_ outcome: TitleModel.DownloadOutcome, _ model: TitleModel, videoID: String? = nil) async {
        switch outcome {
        // Una sola: lo dice el botón o el renglón (su avance), sin aviso encima. Varias: un aviso breve.
        case .queued(let n): if n > 1 { env.notify(format: "Descargando %lld episodios", n, tone: .success, action: .downloads) }
        // «Ya está descargada · Ver»: la copia del iPhone, sin red.
        default: env.report(outcome, downloaded: videoID.map { (model.metaID, $0) })
        }
        await model.refreshState()
    }
}
