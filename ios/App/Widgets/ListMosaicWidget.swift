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
    /// Cuántas filas ha subido el muro (una cada `listStepMinutes`).
    var step = 0
    /// El orden elegido con «Revolver».
    var seed = WidgetStore.mosaicSeed
}

struct ListMosaicProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ListMosaicEntry { ListMosaicEntry(date: Date(), list: WidgetStore.loadLists()?.list(nil)) }
    func snapshot(for configuration: ChooseListIntent, in context: Context) async -> ListMosaicEntry {
        ListMosaicEntry(date: Date(), list: WidgetStore.loadLists()?.list(configuration.list?.id))
    }
    func timeline(for configuration: ChooseListIntent, in context: Context) async -> Timeline<ListMosaicEntry> {
        // El muro sube una fila cada 20 minutos (Fernando, 2 nov 2026): los cuadros ya quedan listos y iOS anima el paso de uno
        // al otro, sin gastar batería ni internet. La app pide recarga cuando cambian las listas; si no, al acabarse los cuadros.
        let now = Date(), list = WidgetStore.loadLists()?.list(configuration.list?.id)
        let entries = (0..<DS.Widget.listSteps).map { step in
            ListMosaicEntry(date: now.addingTimeInterval(Double(step) * DS.Widget.listStepMinutes * 60), list: list, step: step)
        }
        return Timeline(entries: entries, policy: .atEnd)
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
    @Environment(\.displayScale) private var displayScale

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
                // «Revolver»: otro orden al momento, sin abrir la app (un ícono, no una cápsula de texto).
                .overlay(alignment: .bottomTrailing) {
                    Button(intent: ShuffleMosaicIntent()) {
                        Image(systemName: "shuffle").font(DS.font(.sm, weight: .semibold)).foregroundStyle(DS.paper)
                            .frame(width: DS.Widget.button, height: DS.Widget.button)
                            .background(Circle().fill(DS.scrimStrong))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Revolver"))
                    .padding(DS.Space.s3)
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
            // WidgetKit no dibuja ninguna imagen si entre todas suman más pixeles que el widget: con 30 pósters a 330 px el
            // grande pasaba de 4 millones en un hueco de ~1,2 y salían solo los nombres sobre gris (Fernando, 3 nov 2026). Cada
            // póster se lee ya reducido a su parte del área del widget (≈2,3× en vez de 3×; el muro va inclinado y no se nota).
            let budget = proxy.size.width * proxy.size.height * displayScale * displayScale / CGFloat(columns * perColumn)
            let tileScale = min(displayScale, (budget / (width * height)).squareRoot())
            HStack(alignment: .top, spacing: DS.Space.s2) {
                ForEach(0..<columns, id: \.self) { c in
                    VStack(spacing: DS.Space.s2) {
                        ForEach(0..<perColumn, id: \.self) { r in
                            // Cada cuadro sube el muro una fila (`step`) y «Revolver» lo empieza en otro lugar (`seed`).
                            let start = entry.seed * DS.Widget.listShuffleJump + entry.step
                            let poster = list.posters[(start + c * perColumn + r) % list.posters.count]
                            Link(destination: poster.link ?? URL(fileURLWithPath: "/")) { tile(poster, size: CGSize(width: width, height: height), scale: tileScale).frame(width: width, height: height) }
                        }
                    }
                    .offset(y: c % 2 == 1 ? -height * DS.Widget.listStagger : 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .rotationEffect(.degrees(DS.ParaTiB.coverTilt))
            // Entre un cuadro y el siguiente, el muro sube (iOS lo anima).
            .id("\(entry.seed)-\(entry.step)")
            .transition(.push(from: .bottom))
        }
    }

    private func tile(_ poster: WidgetLists.Poster, size: CGSize, scale: CGFloat) -> some View {
        // Se lee recortado y reducido al tamaño de la pieza × `scale` (el presupuesto de pixeles del muro), sin abrir el
        // archivo completo: así no se pasa ni del límite de pixeles de WidgetKit ni de la memoria corta del widget.
        Group {
            if let image = poster.imageFile.flatMap({ WidgetStore.listImageURL($0) })
                .flatMap({ WidgetImage.fill($0, size: size, scale: scale, anchor: .top) }) {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    DS.surface
                    Text(verbatim: poster.title).font(DS.font(.xs, weight: .semibold)).foregroundStyle(DS.textMuted)
                        .multilineTextAlignment(.center).padding(DS.Space.s1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}
