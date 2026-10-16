import SwiftUI
import OrbitalCore
import OrbitalModels

/// Descargas: lo que se está bajando (con su avance), lo listo para ver sin conexión agrupado por título y la descarga
/// inteligente. El espacio va en el subtítulo de la barra; el fondo toma el color de lo que se está bajando.
struct DownloadsView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var observer: ModelObserver<DownloadsModel>
    @StateObject private var tint = ArtTint()

    init() {
        _observer = StateObject(wrappedValue: ModelObserver(DownloadsModel(AppEnvironment.shared.services, freeSpace: { DiskSpace.freeBytes() })))
    }

    var body: some View {
        let model = observer.model
        let settings = env.services.appSettings
        List {
            if !model.active.isEmpty {
                Section("Descargando") { ForEach(model.active) { row($0, model) } }
                    .listRowBackground(DS.surface)
            }
            if !model.readyGroups.isEmpty {
                Section("Listas para ver") { ForEach(model.readyGroups) { group($0, model) } }
                    .listRowBackground(DS.surface)
            }
            if !model.items.isEmpty {
                Section {
                    Toggle("Bajar el siguiente episodio al terminar uno", isOn: setting(\.autoNextDownload))
                    Toggle("Borrar al terminar de verlo", isOn: setting(\.deleteWhenWatched))
                } header: { Text("Descarga inteligente") } footer: {
                    if settings.wifiOnlyDownloads { Label("Solo con Wi‑Fi", systemImage: "wifi").recipe(.footnote) }
                }
                .listRowBackground(DS.surface)
            }
        }
        .overlay {
            // Sin nada en cola ni listo: el vacío nativo, con qué hacer.
            if model.items.isEmpty {
                ContentUnavailableView {
                    Label("Nada descargado", systemImage: "arrow.down.circle")
                } description: {
                    Text("En una ficha, toca Descargar y lo ves aquí sin conexión.")
                }
            }
        }
        .tint(DS.accent)   // interruptores y botones de la lista: el acento (lo interactivo)
        .scrollContentBackground(.hidden).background(Backdrop(tint: tint.colors))
        .navigationTitle("Descargas").toolbarTitleDisplayMode(.inlineLarge)   // el título grande en el renglón de los botones: no se pierde un renglón arriba
        .navigationSubtitle(Text("Ocupan \(bytes(model.usedBytes)) · libres \(bytes(model.freeBytes))"))
        .titleDestinations()
        .task { await model.run() }
        .task(id: model.active.first?.metaID) {
            // El arte de metahub solo existe para ids de IMDb; con otro id, fondo liso.
            await tint.load(model.active.first.flatMap { $0.metaID.hasPrefix("tt") ? String(format: ForYou.metahubBackground, $0.metaID) : nil })
        }
    }

    /// Un ajuste de Descargas como interruptor (se guarda al momento, igual que en Ajustes).
    private func setting(_ key: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { env.services.appSettings[keyPath: key] }, set: { value in env.services.settings.update { $0[keyPath: key] = value }; observer.objectWillChange.send() })
    }

    /// Lo que se está bajando: póster, nombre, datos en SF Mono, el avance y pausar o seguir.
    private func row(_ item: DownloadItem, _ model: DownloadsModel) -> some View {
        HStack(spacing: DS.Space.s3) {
            PosterView(url: item.poster, title: item.title).frame(width: DS.Size.thumbSmall)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(item.title).recipe(.cardTitle).lineLimit(1)
                DataLine(parts: [item.subtitle, status(item)].compactMap { $0 }, color: item.state == .failed ? DS.danger : nil)
                if let progress = item.progress { DSProgress(fraction: progress) }
            }
            Spacer(minLength: DS.Space.s2)
            switch item.state {
            case .downloading, .queued: DSIconButton(symbol: "pause.fill", label: "Pausar") { Task { await model.pause(item.id) } }
            case .paused, .failed: DSIconButton(symbol: "play.fill", label: "Reanudar") { Task { await model.resume(item.id) } }
            case .done: EmptyView()
            }
        }
        .swipeActions { Button("Borrar", role: .destructive) { Task { await model.remove(item.id) } } }
    }

    private func status(_ item: DownloadItem) -> String? {
        let language = env.services.appSettings.uiLanguage
        switch item.state {
        case .queued: return Strings.tr("En cola", language: language)
        case .downloading: return "\(bytes(item.writtenBytes)) / \(item.expectedBytes.map(bytes) ?? "—")"
        case .paused: return Strings.tr("En pausa", language: language)
        case .failed: return item.lastError ?? Strings.tr("No se pudo descargar", language: language)
        case .done: return nil
        }
    }

    /// Un título listo para ver: una película se reproduce al tocarla; una serie despliega sus episodios.
    @ViewBuilder private func group(_ group: DownloadGroup, _ model: DownloadsModel) -> some View {
        if group.items.count == 1, let item = group.items.first {
            readyRow(title: group.title, poster: group.poster, data: [item.subtitle, bytes(item.writtenBytes)], item: item, model: model)
        } else {
            DisclosureGroup {
                ForEach(group.items) { item in
                    readyRow(title: item.subtitle.isEmpty ? group.title : item.subtitle, poster: nil, data: [bytes(item.writtenBytes)], item: item, model: model)
                }
            } label: {
                HStack(spacing: DS.Space.s3) {
                    PosterView(url: group.poster, title: group.title).frame(width: DS.Size.thumbSmall)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(group.title).recipe(.cardTitle).lineLimit(1)
                        DataLine(parts: [episodesText(group.items.count), bytes(group.bytes)])
                    }
                }
            }
        }
    }

    private func readyRow(title: String, poster: String?, data: [String], item: DownloadItem, model: DownloadsModel) -> some View {
        Button { Task { env.play(await model.playRequest(item)) } } label: {
            HStack(spacing: DS.Space.s3) {
                if let poster { PosterView(url: poster, title: title).frame(width: DS.Size.thumbSmall) }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(title).recipe(.cardTitle).lineLimit(1)
                    DataLine(parts: data)
                }
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "play.circle.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.text).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions { Button("Borrar", role: .destructive) { Task { await model.remove(item.id) } } }
    }

    private func episodesText(_ count: Int) -> String {
        String(format: Strings.tr("%lld episodios", language: env.services.appSettings.uiLanguage), count)
    }

    /// «1,2 GB» en el idioma de la app (no en el del sistema).
    private func bytes(_ n: Int64) -> String { n.formatted(.byteCount(style: .file).locale(env.uiLocale)) }
}
