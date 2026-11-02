import AppIntents
import SwiftUI
import UIKit
import WidgetKit
import OrbitalCore

// «Mosaico de una lista»: el muro inclinado de Explorar con los pósters de la lista que tú eliges (mantener presionado el widget
// › Editar). Mediano y grande. Tocar un póster abre su ficha. Las listas las deja la app cuando Explorar arma sus estantes.

// MARK: Datos

struct ListMosaicEntry: TimelineEntry {
    var date: Date
    var list: WidgetLists.List?
}

struct ListMosaicProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListMosaicEntry { ListMosaicEntry(date: Date(), list: WidgetStore.loadLists()?.list(nil)) }
    func snapshot(for configuration: ChooseListIntent, in context: Context) async -> ListMosaicEntry {
        ListMosaicEntry(date: Date(), list: WidgetStore.loadLists()?.list(configuration.list?.id))
    }
    func timeline(for configuration: ChooseListIntent, in context: Context) async -> Timeline<ListMosaicEntry> {
        // La app pide recarga cuando cambian las listas; si no, cada 6 horas.
        Timeline(entries: [await snapshot(for: configuration, in: context)], policy: .after(Date().addingTimeInterval(DS.Widget.fallbackRefresh)))
    }
}

// MARK: Widget

struct ListMosaicWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetStore.listsKind, intent: ChooseListIntent.self, provider: ListMosaicProvider()) { entry in
            ListMosaicView(entry: entry)
        }
        .configurationDisplayName("Mosaico de una lista")
        .description("Los pósters de la lista que elijas, como el muro de Explorar.")
        .supportedFamilies([.systemMedium, .systemLarge])
        .contentMarginsDisabled()   // el muro llega a las orillas
    }
}

struct ListMosaicView: View {
    var entry: ListMosaicEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let list = entry.list, !list.posters.isEmpty {
                ZStack(alignment: .bottomLeading) {
                    wall(list)
                    LinearGradient(stops: [.init(color: .clear, location: DS.Widget.listVeilStart), .init(color: DS.scrimStrong, location: 1)],   // ds-exception: el widget es otro programa y no trae ArtVeil
                                   startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: list.title).font(DS.font(family == .systemLarge ? .lg : .md, weight: .bold)).lineLimit(1)
                        Text("\(list.posters.count) títulos").font(DS.font(.xs, weight: .medium)).foregroundStyle(DS.onArtSecondary)
                    }
                    .foregroundStyle(DS.paper)
                    .shadow(color: DS.scrimStrong, radius: DS.Widget.textShadowRadius)
                    .padding(DS.Space.s4)
                }
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Mosaico de una lista").font(DS.font(.sm, weight: .semibold)).foregroundStyle(DS.text)
                    Text("Abre Explorar una vez y aquí salen tus listas.").font(DS.font(.xs)).foregroundStyle(DS.textMuted)
                }
                .padding(DS.Space.s4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .environment(\.colorScheme, .dark)
        .widgetURL(URL(string: "\(WidgetLink.scheme)://"))
        .containerBackground(for: .widget) { DS.bg.environment(\.colorScheme, .dark) }
    }

    /// El muro: columnas de pósters, una sí y una no más abajo, todo inclinado como la portada de Explorar. Cada póster abre
    /// su ficha.
    private func wall(_ list: WidgetLists.List) -> some View {
        let columns = family == .systemLarge ? DS.Widget.listColumnsLarge : DS.Widget.listColumnsMedium
        let perColumn = family == .systemLarge ? DS.Widget.listRowsLarge : DS.Widget.listRowsMedium
        return GeometryReader { proxy in
            let width = (proxy.size.width * DS.Widget.listWallOverscan - DS.Space.s2 * CGFloat(columns - 1)) / CGFloat(columns)
            let height = width / DS.Poster.aspect
            HStack(alignment: .top, spacing: DS.Space.s2) {
                ForEach(0..<columns, id: \.self) { c in
                    VStack(spacing: DS.Space.s2) {
                        ForEach(0..<perColumn, id: \.self) { r in
                            let poster = list.posters[(c * perColumn + r) % list.posters.count]
                            Link(destination: poster.link ?? URL(fileURLWithPath: "/")) { tile(poster).frame(width: width, height: height) }
                        }
                    }
                    .offset(y: c % 2 == 1 ? -height * DS.Widget.listStagger : 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .rotationEffect(.degrees(DS.ParaTiB.coverTilt))
        }
    }

    private func tile(_ poster: WidgetLists.Poster) -> some View {
        ZStack {
            DS.surface
            if let file = poster.imageFile, let url = WidgetStore.listImageURL(file), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
            } else {
                Text(verbatim: poster.title).font(DS.font(.xs, weight: .semibold)).foregroundStyle(DS.textMuted)
                    .multilineTextAlignment(.center).padding(DS.Space.s1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}
