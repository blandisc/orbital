import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una serie descargada: con varias temporadas, una fila por temporada; con una sola, directo sus episodios.
struct DownloadSeriesView: View {
    @Environment(\.titleName) var titleName
    var observer: ModelObserver<DownloadsModel>
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let metaID: String

    var body: some View {
        let group = observer.model.readySeries.first { $0.metaID == metaID }
        Group {
            if let group, group.seasons.count > 1 {
                List {
                    Section {
                        ForEach(group.seasons) { season in
                            NavigationLink(value: DownloadSeasonRoute(metaID: metaID, season: season.number)) {
                                LabeledContent {
                                    Text(verbatim: ByteSize.text(season.bytes, locale: env.uiLocale))
                                } label: {
                                    Text("Temporada \(season.number)").recipe(.cardTitle)
                                    Text(verbatim: String(format: Strings.tr(season.items.count == 1 ? "%lld episodio" : "%lld episodios", language: env.services.appSettings.uiLanguage), season.items.count)).recipe(.footnote)
                                }
                            }
                            .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { observer.model.deleteWithUndo(season.items) }.tint(DS.danger) }
                        }
                    }
                    .downloadCard()
                }
                .readableListWidth()   // iPad y Mac: al centro, no estirada a todo lo ancho
            } else if let season = group?.seasons.first {
                DownloadSeasonView(observer: observer, metaID: metaID, season: season.number, popsWhenEmpty: false)
            }
        }
        // Borraste lo último de la serie: de vuelta a Descargas, no una página en blanco (revisión del 27 nov 2026).
        .onChange(of: group == nil) { _, gone in if gone { dismiss() } }
        .listRowSpacing(DS.Space.s2)
        .scrollContentBackground(.hidden).background(Backdrop())
        .dsInlineTitle(Text(verbatim: group.map { titleName($0.title, id: $0.metaID, kind: $0.kind) } ?? ""))
    }
}

/// Los episodios descargados de una temporada: tocar uno lo reproduce; deslizar lo borra.
struct DownloadSeasonView: View {
    @Environment(\.titleName) var titleName
    var observer: ModelObserver<DownloadsModel>
    @Environment(AppEnvironment.self) private var env
    @State private var subtitlesFor: DownloadItem?
    let metaID: String
    let season: Int
    /// Dentro de la serie (una sola temporada) la que regresa es la serie, no esta.
    var popsWhenEmpty = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = observer.model
        let group = model.readySeries.first { $0.metaID == metaID }
        let items = group?.seasons.first { $0.number == season }?.items ?? []
        List {
            Section {
                ForEach(items) { item in
                    Button { Task { env.play(await model.playRequest(item)) } } label: {
                        HStack(spacing: DS.Space.s2) {
                            VStack(alignment: .leading, spacing: DS.Space.s1) {
                                Text(verbatim: item.subtitle.isEmpty ? titleName(item.title, id: item.metaID, kind: item.kind) : item.subtitle).recipe(.cardTitle).lineLimit(2)
                                DataLine(parts: [item.quality, ByteSize.text(item.writtenBytes, locale: env.uiLocale)].compactMap { $0 })
                            }
                            Spacer(minLength: DS.Space.s2)
                            Image(systemName: "play.circle.fill").font(DS.TextRecipe.section.font).foregroundStyle(DS.text).accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions { Button("Borrar", systemImage: "trash", role: .destructive) { model.deleteWithUndo([item]) }.tint(DS.danger) }
                    .contextMenu {
                        Button("Buscar subtítulos", systemImage: "captions.bubble") { subtitlesFor = item }
                        ShareLink(item: DownloadedFile(item: item, model: model), preview: SharePreview(Text(verbatim: item.subtitle.isEmpty ? titleName(item.title, id: item.metaID, kind: item.kind) : item.subtitle))) {
                            Label("Compartir el archivo", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } header: { if season > 0 { Text("Temporada \(season)") } }
            .downloadCard()
        }
        .readableListWidth()   // iPad y Mac: al centro, no estirada a todo lo ancho
        .listRowSpacing(DS.Space.s2)
        .scrollContentBackground(.hidden).background(Backdrop())
        .dsInlineTitle(Text(verbatim: group.map { titleName($0.title, id: $0.metaID, kind: $0.kind) } ?? ""))
        // Borraste el último episodio de la temporada: de vuelta, no solo el encabezado «Temporada N» (revisión del 27 nov 2026).
        .onChange(of: items.isEmpty) { _, empty in if empty, popsWhenEmpty { dismiss() } }
        .appSheet(item: $subtitlesFor) { item in DownloadSubtitlesSheet(item: item, model: model).fittedSheet().presentationDragIndicator(.visible) }
    }
}
