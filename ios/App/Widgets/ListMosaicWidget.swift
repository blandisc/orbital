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
        let now = Date(), list = await ListMosaicImages.complete(WidgetStore.loadLists()?.list(configuration.list?.id))
        let entries = (0..<DS.Widget.listSteps).map { step in
            ListMosaicEntry(date: now.addingTimeInterval(Double(step) * DS.Widget.listStepMinutes * 60), list: list, step: step)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

/// Los pósters que le faltan al muro los baja el propio widget. La app los baja de todas tus listas (hasta 12 × 24), uno por
/// uno y solo mientras está abierta: si salías antes de que terminara, las listas de abajo se quedaban con uno o dos pósters y
/// lo demás en gris (Fernando, 3 nov 2026: «sigue sin cargar»). Aquí solo los de la lista elegida, unos cuantos a la vez, y
/// se guardan con el mismo nombre que usa la app (no se vuelven a bajar).
enum ListMosaicImages {
    static func complete(_ list: WidgetLists.List?) async -> WidgetLists.List? {
        guard var list else { return nil }
        let missing = list.posters.indices.filter { list.posters[$0].imageFile.flatMap(WidgetStore.listImageURL).map { !exists($0) } ?? true }
        let found: [Int: String] = await withTaskGroup(of: (Int, String?).self) { group in
            var next = missing.makeIterator(), result: [Int: String] = [:]
            func add() { if let i = next.next() { let poster = list.posters[i]; group.addTask { (i, await fetch(poster)) } } }
            for _ in 0..<DS.Widget.listDownloadsAtOnce { add() }
            for await (i, name) in group { if let name { result[i] = name }; add() }
            return result
        }
        for (i, name) in found { list.posters[i].imageFile = name }
        return list
    }

    private static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    /// El nombre del archivo si ya estaba o si se pudo bajar; nil si no.
    private static func fetch(_ poster: WidgetLists.Poster) async -> String? {
        let name = WidgetLists.imageFileName(for: poster.metaID)
        guard let target = WidgetStore.listImageURL(name) else { return nil }
        if exists(target) { return name }
        guard let url = URL(string: Artwork.variant(poster.poster, pixels: Int(DesignTokens.Widget.listImagePixels))) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = DS.Widget.listDownloadTimeout
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
              let reduced = WidgetImage.reduce(data, maxPixels: DesignTokens.Widget.listImagePixels, quality: DesignTokens.Widget.jpegQuality),
              (try? reduced.data.write(to: target, options: .atomic)) != nil else { return nil }
        return name
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
