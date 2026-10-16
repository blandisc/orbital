import SwiftUI
import OrbitalCore
import OrbitalModels

/// Descargas: la cola, el espacio y lo que ya se puede ver sin conexión.
struct DownloadsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var observer: ModelObserver<DownloadsModel>

    init() {
        _observer = StateObject(wrappedValue: ModelObserver(DownloadsModel(AppEnvironment.shared.services, freeSpace: { DiskSpace.freeBytes() })))
    }

    var body: some View {
        let model = observer.model
        List {
            Section { storage(model) }
            .listRowBackground(DS.fill)
            if !model.active.isEmpty {
                Section("Descargando") { ForEach(model.active) { row($0, model) } }
                .listRowBackground(DS.fill)
            }
            Section("Listas para ver sin conexión") {
                if model.ready.isEmpty { Text("Cuando descargues algo, aparece aquí.").foregroundStyle(DS.textMuted).font(DS.font(.sm)) }
                ForEach(model.ready) { item in
                    Button { Task { env.play(await model.playRequest(item)) } } label: { readyRow(item) }
                        .swipeActions { Button("Borrar", role: .destructive) { Task { await model.remove(item.id) } } }
                }
            }
            .listRowBackground(DS.fill)
        }
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Descargas").navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: TitleRoute.self) { TitleView(route: $0) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if env.services.appSettings.wifiOnlyDownloads { DSChip(text: "Solo con Wi‑Fi") } } }
        .task { await model.run() }
    }

    private func storage(_ model: DownloadsModel) -> some View {
        let used = Double(model.usedBytes), free = Double(model.freeBytes)
        return VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack {
                (model.usedBytes > 0 ? Text("Ocupan \(bytes(model.usedBytes))") : Text("Nada descargado")).font(DS.font(.md)).foregroundStyle(DS.text)
                Spacer()
                Text("Libres \(bytes(model.freeBytes))").font(DS.font(.sm)).foregroundStyle(DS.textMuted)
            }
            DSProgress(fraction: used + free > 0 ? used / (used + free) : 0)
        }
    }

    private func row(_ item: DownloadItem, _ model: DownloadsModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: item.poster, title: item.title).frame(width: DS.Size.thumbSmall)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(item.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1) }
                if let progress = item.progress { DSProgress(fraction: progress) }
                status(item)
            }
            Spacer()
            switch item.state {
            case .downloading, .queued: DSIconButton(symbol: "pause.fill", label: "Pausar") { Task { await model.pause(item.id) } }
            case .paused, .failed: DSIconButton(symbol: "play.fill", label: "Reanudar") { Task { await model.resume(item.id) } }
            case .done: EmptyView()
            }
        }
        .swipeActions { Button("Borrar", role: .destructive) { Task { await model.remove(item.id) } } }
    }

    @ViewBuilder private func status(_ item: DownloadItem) -> some View {
        switch item.state {
        case .queued: Text("En cola").font(DS.font(.xs)).foregroundStyle(DS.textMuted)
        case .downloading: Text("\(bytes(item.writtenBytes)) de \(item.expectedBytes.map(bytes) ?? "—")").font(DS.font(.xs)).foregroundStyle(DS.textMuted)
        case .paused: Text("En pausa").font(DS.font(.xs)).foregroundStyle(DS.textMuted)
        case .failed: Text(item.lastError ?? "No se pudo descargar").font(DS.font(.xs)).foregroundStyle(DS.danger).lineLimit(2)
        case .done: EmptyView()
        }
    }

    private func readyRow(_ item: DownloadItem) -> some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: item.poster, title: item.title).frame(width: DS.Size.thumbSmall)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(item.title).font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text).lineLimit(1)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(DS.font(.xs)).foregroundStyle(DS.textMuted).lineLimit(1) }
                Text(bytes(item.writtenBytes)).font(DS.font(.xs)).foregroundStyle(DS.textMuted)
            }
            Spacer()
            Image(systemName: "play.fill").foregroundStyle(DS.textMuted)
        }
    }

    /// «1,2 GB» en el idioma de la app (no en el del sistema).
    private func bytes(_ n: Int64) -> String { n.formatted(.byteCount(style: .file).locale(env.uiLocale)) }
}
