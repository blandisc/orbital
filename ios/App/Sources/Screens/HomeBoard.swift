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

/// El panel de la derecha del tablero: «Seguir viendo» en renglones, «Lo nuevo de lo tuyo» y «Decide por mí», en el alto de
/// la portada (`ViewThatFits`): si no cabe, primero se van renglones de lo que tienes a medias («Ver todo» los abre); «Decide
/// por mí» siempre está.
struct HomeBoardPanel<Rows: View, News: View, Decide: View>: View {
    @ViewBuilder let rows: (_ limit: Int) -> Rows
    @ViewBuilder let news: () -> News
    @ViewBuilder let decide: () -> Decide

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(Array((1...DS.HomeBoard.rows).reversed()), id: \.self) { limit in column(limit, news: true) }
            column(DS.HomeBoard.rows, news: false)
        }
        .padding(DS.Space.s4)
        .frame(width: HomeBoard.panelWidth, height: HomeBoard.height, alignment: .topLeading)
        .dsCard(translucent: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home-board-panel")
    }

    private func column(_ limit: Int, news shows: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            VStack(alignment: .leading, spacing: DS.Space.s2) { rows(limit) }
            if shows { news() }
            decide()
        }
    }
}

/// Un renglón del panel: la imagen del capítulo con su avance a la izquierda y el nombre y los datos a la derecha.
struct BoardRow: View {
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
            .frame(width: DS.HomeBoard.thumb)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(title).recipe(.cardTitle).lineLimit(2)
                if !data.isEmpty { DataLine(parts: data) }
            }
            Spacer(minLength: 0)
        }
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
        /// Cuántos de lo que tienes a medias caben en el panel («Ver todo» abre los demás) y el ancho de su imagen.
        static let rows = 3, thumb: CGFloat = 128
        /// Cuánto avanzan ‹ › (C4): casi una pantalla, para que lo último se siga viendo.
        static let arrowPage: CGFloat = 0.9
        /// C1: desde este ancho las pestañas del iPad van al centro de la barra (más angosta, junto al logo y solo con íconos).
        static let padCenteredTabsFrom: CGFloat = 1180
        /// C6: «Decide por mí» como tarjeta, un poco más ancha que las de «Seguir viendo» (su abanico y su nombre caben).
        static var decideWidth: CGFloat { max(DS.Poster.stillWidth * 1.3, DS.Mac.sized(decideMin)) }
        static let decideMin: CGFloat = 380
    }
}
