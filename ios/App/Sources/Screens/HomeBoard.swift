import SwiftUI
import OrbitalCore
import OrbitalModels

/// MI2 · II1 (Fernando, 18 nov 2026: «aplica tus sugerencias», docs/producto/inicio-ancho-2026-11-18/): en una ventana
/// acostada y ancha (Mac, iPad acostado) Inicio es un tablero: la portada en dos tercios y, a su derecha, lo tuyo (lo que
/// tienes a medias y lo nuevo de tus series), para verlo sin bajar. En una ventana angosta o de pie (iPad parado, media
/// pantalla), la portada de siempre («cine»). La TV y el iPhone no cambian: en la tele, la portada de orilla a orilla con «A
/// continuación» (distinto a propósito, `docs/producto/paridad-registro.md`).
enum HomeBoard {
    /// Tablero o cine, con lo que de verdad le queda a Inicio (`WindowMetrics.column`): con el control abierto a la derecha,
    /// la columna se angosta y vuelve el cine (se anima). Con letra de accesibilidad, siempre cine: el panel no cabría.
    static func isOn(_ typeSize: DynamicTypeSize) -> Bool {
        let column = WindowMetrics.column
        return column.width >= DS.HomeBoard.from && column.width >= column.height * DS.TitleAction.portraitBelow && !typeSize.isAccessibilitySize
    }

    /// El ancho del panel (una tercera parte, entre `panelMin` y `panelMax`) y el de la portada (lo demás).
    static var panelWidth: CGFloat {
        min(DS.HomeBoard.panelMax, max(DS.HomeBoard.panelMin, room * DS.HomeBoard.panelShare))
    }
    static var heroWidth: CGFloat { room - DS.HomeBoard.gap - panelWidth }
    /// Lo alto de la portada y el panel: una parte del alto de la ventana (así se asoma la primera fila de abajo).
    static var height: CGFloat { (WindowMetrics.column.height * DS.HomeBoard.heightShare).rounded() }
    /// La proporción de la portada en el tablero (su ancho entre su alto), sin pasar de lo que el arte 16:9 llena.
    static var heroAspect: CGFloat { min(DS.HomeHero.aspectWideMax, max(DS.HomeBoard.heroAspectMin, heroWidth / height)) }
    private static var room: CGFloat { WindowMetrics.column.width - 2 * DS.Space.gutter }
}

/// El panel de la derecha del tablero, en el alto de la portada: «Seguir viendo» en renglones grandes, debajo «Lo nuevo de lo
/// tuyo» y al pie «Decide por mí». Caben tantos renglones como alcance el alto («Ver todo» abre los demás); si no cabe «Lo nuevo
/// de lo tuyo», se va antes que «Seguir viendo». Fernando, 22 nov 2026: «Seguir viendo… más grandes y metería más» y «lo nuevo
/// que viene me gustaba cuando estaba abajo de continuar viendo».
///
/// Cuántos caben se cuenta, no se prueba: cada renglón mide lo mismo (`DS.HomeBoard.height(compact:)`), así que basta medir el alto
/// libre, lo que ocupa el encabezado y «Lo nuevo» y dividir. Antes un `ViewThatFits` armaba doce paneles completos (seis
/// cantidades, con y sin «Lo nuevo») cada vez que volvías a Inicio y la Mac se trababa al cambiar de pestaña (Fernando, 22 nov
/// 2026: «le doy clic a inicio, explorar y se tarda muchísimo»).
struct HomeBoardPanel<Rows: View, News: View, Decide: View>: View {
    @ViewBuilder let rows: (_ limit: Int) -> Rows
    @ViewBuilder let news: () -> News
    @ViewBuilder let decide: () -> Decide

    @State private var free: CGFloat = 0
    @State private var block: CGFloat = 0
    @State private var newsHeight: CGFloat = 0
    @State private var shown = Fit(rows: 1, compact: false, news: true)

    var body: some View {
        let fit = Self.fit(free: free, block: block, shown: shown.rows, compact: shown.compact, news: newsHeight)
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            VStack(alignment: .leading, spacing: DS.Space.s6) {
                VStack(alignment: .leading, spacing: DS.Space.s2) { rows(fit.rows) }
                    .environment(\.boardRowCompact, fit.compact)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { block = $0; shown = fit }
                if fit.news {
                    news().onGeometryChange(for: CGFloat.self) { $0.size.height } action: { newsHeight = $0 }
                }
            }
            // `minHeight: 0`: lo de arriba cede su alto a «Decide por mí»; sin él, los renglones empujaban la tarjeta fuera del
            // panel (22 nov 2026) y `free` medía de más.
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { free = $0 }
            .clipped()
            decide().layoutPriority(1)
        }
        .padding(DS.Space.s4)
        .frame(width: HomeBoard.panelWidth, height: HomeBoard.height, alignment: .topLeading)
        .dsCard(translucent: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-board-panel")
    }

    /// Cuántos renglones, si van chicos y si va «Lo nuevo». Primero renglones grandes con «Lo nuevo»; si no caben dos, chicos
    /// con «Lo nuevo»; si ni así, sin «Lo nuevo» (Fernando, 22 nov 2026: «sí te alcanza el espacio para poner dos de seguir
    /// viendo… que si haces más chico, se ajuste»). El encabezado es lo que mide el bloque menos sus `shown` renglones.
    static func fit(free: CGFloat, block: CGFloat, shown: Int, compact: Bool, news: CGFloat) -> Fit {
        guard free > 0, block > 0 else { return Fit(rows: 1, compact: false, news: true) }
        let gap = DS.Space.s2
        let head = max(0, block - CGFloat(shown) * (DS.HomeBoard.height(compact: compact) + gap))
        func count(_ small: Bool, _ room: CGFloat) -> Int {
            min(DS.HomeBoard.rows, Int(((room - head) / (DS.HomeBoard.height(compact: small) + gap)).rounded(.down)))
        }
        let withNews = free - news - DS.Space.s6
        if count(false, withNews) >= 2 { return Fit(rows: count(false, withNews), compact: false, news: true) }
        if count(true, withNews) >= 2 { return Fit(rows: count(true, withNews), compact: true, news: true) }
        if count(false, free) >= 2 { return Fit(rows: count(false, free), compact: false, news: false) }
        return Fit(rows: max(1, count(true, free)), compact: true, news: false)
    }

    struct Fit: Equatable { let rows: Int, compact: Bool, news: Bool }
}

/// Un renglón del panel: la imagen del capítulo con su avance a la izquierda y el nombre y los datos a la derecha.
struct BoardRow: View {
    @Environment(\.boardRowCompact) private var compact
    let title: String
    let art: String?
    var data: [String] = []
    var progress: Double?
    var fallback: String?

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            ZStack(alignment: .bottom) {
                PosterView(url: art, title: title, aspect: DS.Poster.stillAspect, fallback: fallback)
                if let progress { DSProgress(fraction: progress).padding(.horizontal, DS.Space.s1).padding(.bottom, DS.Space.s1) }
            }
            .frame(width: DS.HomeBoard.thumb(compact: compact))
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.cardTitle).lineLimit(2)
                if !data.isEmpty { DataLine(parts: data) }
            }
            Spacer(minLength: 0)
        }
        .frame(height: DS.HomeBoard.height(compact: compact))   // todos iguales: el panel cuenta cuántos caben sin probar (`HomeBoardPanel`)
        .contentShape(Rectangle())
        .pointerHover(.lift)
    }
}

/// C4 (Fernando, 18 nov 2026): con mouse o trackpad, al pasar el puntero por una fila salen ‹ › en sus orillas y la avanzan
/// una pantalla. Con el dedo no salen (no hay puntero): la fila se desliza como siempre. Va en la `ScrollView` horizontal.
struct PagingArrows: ViewModifier {
    @State private var position = ScrollPosition(edge: .leading)
    @State private var edges = ScrollEdges()
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct ScrollEdges: Equatable {
        var offset: CGFloat = 0, end: CGFloat = 0, page: CGFloat = 0, inset: CGFloat = 0
        var canGoBack: Bool { offset > 1 }
        var canGoOn: Bool { offset < end - 1 }
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollEdges.self) { g in
                ScrollEdges(offset: g.contentOffset.x + g.contentInsets.leading,
                            end: max(0, g.contentSize.width + g.contentInsets.leading + g.contentInsets.trailing - g.containerSize.width),
                            page: g.containerSize.width, inset: g.contentInsets.leading)
            } action: { _, new in edges = new }
            .overlay(alignment: .leading) { arrow("chevron.left", label: "Anteriores", shown: edges.canGoBack, step: -1) }
            .overlay(alignment: .trailing) { arrow("chevron.right", label: "Siguientes", shown: edges.canGoOn, step: 1) }
            .onHover { inside in withAnimation(DS.Motion.fade) { hovering = inside } }
    }

    @ViewBuilder private func arrow(_ symbol: String, label: LocalizedStringKey, shown: Bool, step: CGFloat) -> some View {
        if hovering && shown {
            DSIconButton(symbol: symbol, label: label, size: .regular, steady: true) {
                let target = min(edges.end, max(0, edges.offset + step * edges.page * DS.HomeBoard.arrowPage))
                withAnimation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade) { position.scrollTo(x: target - edges.inset) }   // el desplazamiento cuenta desde antes del margen
            }
            .padding(.horizontal, DS.Space.s2)
            .transition(.opacity)
            .accessibilityIdentifier(step < 0 ? "row-back" : "row-next")
        }
    }
}

extension View {
    /// C4: ‹ › al pasar el puntero por una fila horizontal (`PagingArrows`).
    func pagingArrows() -> some View { modifier(PagingArrows()) }
}

extension DS {
    /// El tablero de Inicio (MI2 · II1).
    enum HomeBoard {
        /// Desde este ancho de columna (y acostada): en la Mac, con su letra más grande, un poco más.
        static let from: CGFloat = ProcessInfo.processInfo.isiOSAppOnMac ? 1200 : 1100
        static let panelShare: CGFloat = 0.34, panelMin: CGFloat = 340, panelMax: CGFloat = 520
        static let gap = DS.Space.s6, heightShare: CGFloat = 0.6, heroAspectMin: CGFloat = 1.1
        /// Hasta cuántos de lo que tienes a medias van en el panel (los que quepan; «Ver todo» abre los demás) y el ancho de su imagen.
        static let rows = 6, thumb: CGFloat = 176
        /// La imagen de un renglón cuando no caben dos grandes (`HomeBoardPanel.fit`).
        static let thumbCompact: CGFloat = 128
        static func thumb(compact: Bool) -> CGFloat { compact ? thumbCompact : thumb }
        /// El alto de cada renglón: el de su imagen (16:9). Fijo, para contar cuántos caben sin armar el panel varias veces.
        static func height(compact: Bool) -> CGFloat { (thumb(compact: compact) / DS.Poster.stillAspect).rounded(.up) }
        /// Cuánto avanzan ‹ › (C4): casi una pantalla, para que lo último se siga viendo.
        static let arrowPage: CGFloat = 0.9
        /// C1: desde este ancho las pestañas del iPad van al centro de la barra (más angosta, junto al logo y solo con íconos).
        static let padCenteredTabsFrom: CGFloat = 1180
        /// C6: «Decide por mí» como tarjeta, un poco más ancha que las de «Seguir viendo» (su abanico y su nombre caben).
        static var decideWidth: CGFloat { max(DS.Poster.stillWidth * 1.3, DS.Mac.sized(decideMin)) }
        static let decideMin: CGFloat = 380
    }
}

/// Renglones chicos en el panel de Inicio cuando no caben dos grandes (`HomeBoardPanel`).
private struct BoardRowCompactKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var boardRowCompact: Bool {
        get { self[BoardRowCompactKey.self] }
        set { self[BoardRowCompactKey.self] = newValue }
    }
}
