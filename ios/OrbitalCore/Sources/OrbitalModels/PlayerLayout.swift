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
        let ratio = CGFloat(min(max(aspect, minAspect), Double(wideAspect)))
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
}
