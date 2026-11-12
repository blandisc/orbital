import CoreGraphics

/// Dónde va el video del reproductor, en un solo cálculo puro (sin pantalla) y probado en iPhone SE, mini y Pro Max: el video en
/// vertical (su alto según la proporción, hasta dónde sube y baja), y el ancho del panel de la derecha en horizontal. Antes vivía
/// dentro de la pantalla, sin pruebas. Las medidas vienen de los tokens de diseño de la app (`PlayerLayout.app`).
public struct PlayerLayout: Sendable {
    /// Lo más arriba que abre el video (debajo de ✕ y el nombre) y lo que deja libre abajo para los controles.
    public var topClearance: CGFloat
    public var controlsReserve: CGFloat
    /// Lo más cuadrado que se le da espacio (4:3) y la proporción ancha de siempre (16:9).
    public var minAspect: Double
    public var wideAspect: CGFloat
    /// El centro por omisión (parte del alto) cuando aún no se sabe el tamaño.
    public var defaultCenter: Double
    /// El panel de la derecha en horizontal: su ancho y lo más que ocupa del ancho total.
    public var panelWidth: CGFloat
    public var panelShare: CGFloat

    public init(topClearance: CGFloat, controlsReserve: CGFloat, minAspect: Double, wideAspect: CGFloat, defaultCenter: Double,
                panelWidth: CGFloat, panelShare: CGFloat) {
        self.topClearance = topClearance; self.controlsReserve = controlsReserve; self.minAspect = minAspect
        self.wideAspect = wideAspect; self.defaultCenter = defaultCenter; self.panelWidth = panelWidth; self.panelShare = panelShare
    }

    /// El alto del video en vertical: de orilla a orilla en la proporción del cuadro. Un video más cuadrado que 16:9 (Los Simpson
    /// en 4:3) crece a lo alto en vez de quedar con franjas a los lados; uno más ancho se queda en la banda 16:9. Nunca invade el
    /// lugar de los controles.
    public func portraitHeight(in size: CGSize, aspect: Double) -> CGFloat {
        // Una proporción rara del motor (no es número, infinita, cero) cuenta como 16:9: con un NaN el video ocupaba toda la
        // pantalla y empujaba los controles fuera de ella.
        let safe = aspect.isFinite && aspect > 0 ? aspect : Double(wideAspect)
        let ratio = CGFloat(min(max(safe, minAspect), Double(wideAspect)))
        let room = max(size.width / wideAspect, size.height - topClearance - controlsReserve)
        return min(size.width / ratio, room, size.height)
    }

    /// El video en vertical a la altura `center` (parte del alto). Sin mover (`center` negativo) abre bajo ✕ y el nombre;
    /// arrastrado, sube hasta la orilla. Abajo siempre deja el lugar de los controles.
    public func portraitRect(in size: CGSize, center: Double, aspect: Double) -> CGRect {
        let height = portraitHeight(in: size, aspect: aspect)
        let lowest = max(topClearance, size.height - controlsReserve - height)
        let y = center < 0 ? min(topClearance, lowest) : min(max(0, size.height * center - height / 2), lowest)
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }

    /// Lo más arriba y lo más abajo que puede ir el centro del video (parte del alto).
    public func portraitLimits(in size: CGSize, aspect: Double) -> ClosedRange<Double> {
        guard size.height > 0 else { return defaultCenter...defaultCenter }
        let height = portraitHeight(in: size, aspect: aspect)
        let lowest = max(topClearance, size.height - controlsReserve - height)
        return Double((height / 2) / size.height)...Double((lowest + height / 2) / size.height)
    }

    /// El centro guardado, o (negativo: sin mover) el de donde abre. Arrastrar o mover con VoiceOver parte de aquí.
    public func resolvedCenter(_ stored: Double, in size: CGSize, aspect: Double) -> Double {
        if stored >= 0 || size.height <= 0 { return stored }
        return Double(portraitRect(in: size, center: -1, aspect: aspect).midY / size.height)
    }

    /// El panel de la derecha en horizontal: su ancho, pero nunca más de `panelShare` del total (en un SE o mini quedaba poco video).
    public func sidePanelWidth(in total: CGFloat) -> CGFloat { min(panelWidth, total * panelShare) }

    /// Vertical con un panel pegado abajo («Audio y subtítulos», que mide `panel` con su aire de abajo): el video justo arriba
    /// de él, a `gap`, sin hueco negro entre los dos (antes se quedaba arriba y, con el panel chico, sobraban ~200 pt de negro).
    /// Si el panel no deja lugar, el video sube hasta la orilla de arriba (y el panel se desplaza por dentro); nunca sale de
    /// la pantalla.
    public func portraitRect(abovePanel panel: CGFloat, gap: CGFloat, in size: CGSize, aspect: Double) -> CGRect {
        let height = portraitHeight(in: size, aspect: aspect)
        let y = min(max(0, size.height - panel - gap - height), max(0, size.height - height))
        return CGRect(x: 0, y: y, width: size.width, height: height)
    }

    /// Las orillas que no se tapan (el área segura de la ventana).
    public struct Insets: Sendable, Equatable {
        public var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat
        public init(top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
            self.top = top; self.left = left; self.bottom = bottom; self.right = right
        }
    }

    /// Horizontal con el panel a la derecha: dónde va el panel y dónde el video.
    public struct SideDock: Sendable, Equatable {
        public let panel: CGRect
        public let video: CGRect
    }

    /// Horizontal con el panel: el panel a la derecha, de arriba abajo dentro del área segura (a `margin` de cada orilla), y
    /// el video en su proporción, centrado en lo que queda a la izquierda y a `margin` del panel. Los dos salen del mismo
    /// cálculo y del mismo tamaño (la pantalla entera): antes el panel medía su ancho sin el área segura, el video con ella,
    /// y el panel tapaba la orilla derecha del video y se cortaba abajo.
    public func sideDock(in size: CGSize, insets: Insets, margin: CGFloat, aspect: CGFloat) -> SideDock {
        let width = sidePanelWidth(in: size.width)
        let top = max(insets.top, margin), bottom = max(insets.bottom, margin)
        let panel = CGRect(x: size.width - max(insets.right, margin) - width, y: top, width: width, height: max(0, size.height - top - bottom))
        let left = max(insets.left, margin)
        let free = CGRect(x: left, y: 0, width: max(0, panel.minX - margin - left), height: size.height)
        let ratio = aspect.isFinite && aspect > 0 ? aspect : wideAspect
        let width2 = min(free.width, free.height * ratio)
        let height = width2 / ratio
        return SideDock(panel: panel, video: CGRect(x: free.midX - width2 / 2, y: free.midY - height / 2, width: width2, height: height))
    }
}
