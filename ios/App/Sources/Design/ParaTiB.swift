import SwiftUI
import OrbitalModels

// Las piezas de Para ti B (docs/producto/inicio-benchmark/para-ti/): los círculos para saltar a cada parte, la portada del mosaico y la
// tarjeta de «¿Qué vemos hoy?».

/// La portada de Para ti: un muro de pósters inclinado que se funde con el fondo, con su porqué y «Pasear por el mosaico».
/// El muro sube detrás de la barra y baja un poco bajo los círculos, apagándose poco a poco en las dos orillas (antes se
/// cortaba en seco); el espacio de la página no cambia. Cada vez que llegan otros pósters salen en otro orden, y el muro
/// se desliza despacio sobre su diagonal (quieto con «Reducir movimiento» o fuera de pantalla).
struct MosaicCover: View {
    let posters: [String]
    /// El muro de la última vez (de qué pósters salió y su orden), en `ParaTiModel`: sobrevive a que la pantalla se vuelva
    /// a armar. El orden lo decide `CoverWall` (OrbitalModels, con pruebas).
    let memory: CoverWallMemory
    let onWalk: () -> Void
    @State private var order: [String]
    @State private var onScreen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.perfTag) private var perfTag

    init(posters: [String], memory: CoverWallMemory, onWalk: @escaping () -> Void) {
        self.posters = posters
        self.memory = memory
        self.onWalk = onWalk
        // Al volver del mosaico (o de otra pestaña) el muro de antes ya en el primer cuadro: sin un instante vacío.
        _order = State(initialValue: memory.order(for: posters, size: DS.ParaTiB.coverPosters))
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: DS.ParaTiB.coverHeight)
            .overlay(alignment: .bottom) {
                // El arte ocupa más que su marco (arriba y abajo) pero no ensancha la página: se recorta a los lados. Con su
                // propio alto (no con un margen negativo): la máscara y el recorte medían el marco de 300 y cortaban en seco
                // todo lo que subía detrás del título y la barra (Fernando, 31 oct 2026: «ahora no se ve bien»).
                ZStack { moving; veil }
                    .frame(height: DS.ParaTiB.coverBleedUp + DS.ParaTiB.coverHeight + DS.ParaTiB.coverBleedDown)
                    .mask { fade }
                    .clipped()
                    .offset(y: DS.ParaTiB.coverBleedDown)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            // I10 (revisión del 10 nov): el botón del mosaico ya no flota suelto sobre el muro; va en la barra de arriba
            // (`ListsView`, «Pasear por el mosaico»). Tocar el muro también entra (VoiceOver usa el de la barra).
            .contentShape(Rectangle())
            .onTapGesture(perform: onWalk)
            .overlay { demoProbe }
            .onScrollVisibilityChange(threshold: DS.ParaTiB.coverVisibleFrom) { onScreen = $0 }
            // Otro muro solo cuando llegan pósters de verdad distintos; al volver del mosaico, el mismo de antes (Fernando,
            // 31 oct 2026: revolverlo otra vez pedía pósters nuevos y el muro se quedaba negro unos segundos).
            .onChange(of: posters) { order = memory.order(for: posters, size: DS.ParaTiB.coverPosters) }
    }

    /// Solo en el modo demo: qué muro se armó (cuántos pósters y los primeros), para que la prueba de interfaz compruebe que
    /// al volver del mosaico o de otra pestaña es el mismo (`MosaicUITests.testCoverWallAfterWalking`).
    @ViewBuilder private var demoProbe: some View {
        #if DEBUG
        if Demo.isOn {
            Color.clear
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(order.count) " + order.prefix(columns).map { $0.split(separator: "/").suffix(2).joined(separator: "/") }.joined(separator: ",")))
                .accessibilityIdentifier("paraTi-cover-wall")
                .allowsHitTesting(false)
        }
        #endif
    }

    /// El muro: una parrilla inclinada donde cada columna baja sola, cada una a su ritmo (Fernando, 31 oct 2026: «no debe ser
    /// uniforme»; antes el muro entero iba y venía de una pieza). Lo mueve Core Animation sobre las columnas ya pintadas
    /// (`CoreDrift`): SwiftUI no repinta nada en cada cuadro. Quieto con «Reducir movimiento» y en las pruebas
    /// (`-demo-no-idle`); fuera de pantalla se pausa donde iba.
    private var moving: some View {
        let columns = self.columns
        return HStack(spacing: DS.Space.s2) {
            ForEach(0..<columns, id: \.self) { c in
                let posters = column(c)
                CoreDrift(key: posters, content: AnyView(strip(posters).environment(\.perfTag, c == 0 ? perfTag : nil)),
                          contentHeight: Self.loop * 2, loop: Self.loop,
                          speed: DS.ParaTiB.coverPace[c % DS.ParaTiB.coverPace.count], phase: Double(c) * DS.ParaTiB.coverPhaseStep,
                          rising: DS.ParaTiB.coverAlternates && c % 2 == 1,
                          enabled: !still, running: onScreen)
                    .frame(width: Self.columnWidth, height: DS.ParaTiB.coverWallHeight)
            }
        }
        .frame(width: CGFloat(columns) * Self.columnWidth + DS.Space.s2 * CGFloat(columns - 1), height: DS.ParaTiB.coverWallHeight)
        .rotationEffect(.degrees(DS.ParaTiB.coverTilt))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Cuántas columnas lleva el muro en esta ventana (`DS.ParaTiB.coverColumns(forWidth:)`): ocho, o más en ventana ancha.
    private var columns: Int { DS.ParaTiB.coverColumns(forWidth: WindowMetrics.size.width) }

    private var still: Bool {
        #if DEBUG
        if Demo.noIdle { return true }
        #endif
        return reduceMotion
    }

    /// El ancho de una columna del muro y lo que mide una vuelta de su tira (sus pósters una vez, con su separación).
    private static let columnWidth = (DS.ParaTiB.coverWall - DS.Space.s2 * CGFloat(DS.ParaTiB.coverColumns - 1)) / CGFloat(DS.ParaTiB.coverColumns)
    private static let loop = (columnWidth / DS.Poster.aspect + DS.Space.s2) * CGFloat(DS.ParaTiB.coverRows)

    /// Los pósters de una columna: uno de cada `coverColumns` del orden del muro (así las vecinas no repiten).
    private func column(_ c: Int) -> [String] {
        guard !order.isEmpty else { return [] }
        return (0..<DS.ParaTiB.coverRows).map { order[(c + $0 * columns) % order.count] }
    }

    /// La tira de una columna, dos veces seguida: al bajar una vuelta entera queda igual que al principio y se repite sin corte.
    private func strip(_ posters: [String]) -> some View {
        VStack(spacing: DS.Space.s2) {
            ForEach(0..<(posters.count * 2), id: \.self) { i in
                PosterView(url: posters[i % posters.count], title: "", maxPoints: DS.Image.mosaic).frame(width: Self.columnWidth)
            }
        }
        .frame(width: Self.columnWidth, alignment: .top)
    }

    /// Las orillas: arriba sube mucho más que la pantalla (al jalar para actualizar siguen los pósters, Fernando, 31 oct
    /// 2026) y pasa detrás del título y la barra sin corte; abajo se apaga
    /// hasta perderse bajo los círculos.
    private var fade: some View {
        let up = DS.ParaTiB.coverBleedUp, total = up + DS.ParaTiB.coverHeight + DS.ParaTiB.coverBleedDown
        return LinearGradient(stops: [
            .init(color: .black.opacity(DS.ParaTiB.coverUnderBar), location: 0),
            .init(color: .black.opacity(DS.ParaTiB.coverUnderBar), location: (up - DS.ParaTiB.coverTitleZone) / total),
            .init(color: .black, location: up / total),
            .init(color: .black, location: (up + DS.ParaTiB.coverHeight * DS.ParaTiB.coverBaseAt) / total),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// Un velo bajo el porqué y el botón, para que se lean sobre cualquier póster; sigue de largo bajo los círculos.
    private var veil: some View {
        let up = DS.ParaTiB.coverBleedUp, total = up + DS.ParaTiB.coverHeight + DS.ParaTiB.coverBleedDown
        return LinearGradient(stops: [
            .init(color: DS.bg.opacity(DS.ParaTiB.coverTitleVeil), location: 0),   // el título grande se lee encima
            .init(color: DS.bg.opacity(DS.ParaTiB.coverTitleVeil), location: (up - DS.ParaTiB.coverTitleZone) / total),
            .init(color: .clear, location: up / total),
            .init(color: .clear, location: (up + DS.ParaTiB.coverHeight * DS.ParaTiB.coverClearAt) / total),
            .init(color: DS.bg.opacity(DS.ParaTiB.coverBaseVeil), location: (up + DS.ParaTiB.coverHeight) / total),
            .init(color: DS.bg.opacity(DS.ParaTiB.coverBaseVeil), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

/// «¿Qué vemos hoy?»: la entrada a encontrar tu match (tres pósters en abanico, el porqué y cómo se usa).
struct MatchTeaser: View {
    let posters: [String]
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Con letra de accesibilidad, el abanico arriba y el texto debajo: al lado, «¿Qué vemos» no cabía y ensanchaba toda
        // la página de Explorar (el botón del mosaico quedaba fuera de la orilla; ChaosRegressionUITests, letra máxima).
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4))
                                                  : AnyLayout(HStackLayout(spacing: DS.Space.s4))
        Button(action: onOpen) {
            layout {
                PosterFan(posters: posters, width: DS.ParaTiB.deckPoster)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Eyebrow(text: Text("Encuentra tu match perfecto"), reason: true)
                    Text("¿Qué vemos hoy?").recipe(.section)
                    Text("A la derecha la guardas, a la izquierda no.").recipe(.footnote, color: DS.textMuted)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)
            .dsCard(.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Space.gutter)
        .accessibilityIdentifier("paraTi-match")
    }
}

/// Tres pósters en abanico, el primero al frente y los otros asomando girados detrás («¿Qué vemos hoy?», «La temporada»).
struct PosterFan: View {
    let posters: [String]
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(posters.prefix(DS.ParaTiB.matchFan).enumerated().reversed()), id: \.offset) { i, url in
                PosterView(url: url, title: "")
                    .frame(width: width)
                    .rotationEffect(.degrees(Double(i) * DS.ParaTiB.deckTurn))
                    .offset(x: CGFloat(i) * DS.ParaTiB.deckShift)
                    .opacity(i == 0 ? 1 : DS.ParaTiB.deckBehind)
            }
        }
        .frame(width: width + DS.ParaTiB.deckShift * CGFloat(DS.ParaTiB.matchFan - 1), alignment: .leading)
        .accessibilityHidden(true)
    }
}

/// «La temporada»: la de ahora (o la siguiente en llegar) en grande, con su color, cuándo, su frase, sus tres más vistos en
/// abanico. Toda la tarjeta abre la colección (sin flecha ni cápsula).
struct SeasonFeature: View {
    let name: String
    let blurb: String
    let days: Int
    let posters: [String]
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.s4) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Eyebrow(text: when, reason: true)
                // Toda la tarjeta abre la colección, sin cápsula «Ver la colección» (H3) y sin flecha: la temporada de ahora es la
                // portada de la sección, no una fila (Fernando, 2 nov 2026).
                Text(verbatim: name).recipe(.title).lineLimit(2).minimumScaleFactor(DS.Size.titleShrink)
                Text(verbatim: blurb).recipe(.footnote, color: DS.textMuted).lineLimit(2)
            }
            Spacer(minLength: 0)
            if !posters.isEmpty { PosterFan(posters: posters, width: DS.ParaTiB.seasonPoster) }
        }
        .padding(DS.Space.s4)
        .background {
            Color.clear.dsCard(.card)
                .overlay(LinearGradient(colors: [tint.opacity(DS.ParaTiB.seasonGlow), .clear], startPoint: .topTrailing, endPoint: .bottomLeading)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// «La temporada · ahora», «… · mañana» o «… · en 12 días».
    private var when: Text {
        switch days {
        case 0: Text("La temporada · ahora")
        case 1: Text("La temporada · mañana")
        default: Text("La temporada · en \(days) días")
        }
    }
}

/// Un renglón de «Tuyo» (Mi lista, Favoritos, Tus series y tus listas de Trakt): tres pósters encimados, el nombre, qué es y
/// cuántos tiene.
struct ListRow: View {
    let name: String
    let detail: Text
    let posters: [String]

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            ZStack(alignment: .leading) {
                ForEach(Array(posters.prefix(DS.ParaTiB.matchFan).enumerated().reversed()), id: \.offset) { i, url in
                    PosterView(url: url, title: "").frame(width: DS.Collections.stackPoster)
                        .offset(x: CGFloat(i) * DS.ParaTiB.rowShift)
                        .shadow(DS.Elevation.low.drop(DS.Space.s1))
                }
            }
            .frame(width: DS.Collections.stackPoster + DS.ParaTiB.rowShift * CGFloat(DS.ParaTiB.matchFan - 1), alignment: .leading)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: name).recipe(.cardTitle).lineLimit(1)
                detail.recipe(.footnote, color: DS.textMuted).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.right").font(DS.TextRecipe.label.font).foregroundStyle(DS.textFaint)
        }
        .padding(DS.Space.s2)
        .padding(.trailing, DS.Space.s2)
        .dsCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Una columna del muro que baja sola, hecha por Core Animation: SwiftUI la pinta una vez y el servidor de render la desliza,
/// sin volver a pintarla ni despertar a la app en cada cuadro. La tira mide dos vueltas (`contentHeight`) y baja una vuelta
/// (`loop`) a `speed` puntos por segundo; al llegar empieza otra vez, sin que se note. `phase` (0 a 1) la arranca a medio
/// camino para que las columnas no vayan parejas. `running` en falso la pausa donde va; `enabled` en falso la deja quieta.
/// El contenido solo se vuelve a armar si cambian sus pósters (`key`): antes se rearmaba con cada cambio de la pantalla y
/// entrar a Explorar se trababa.
private struct CoreDrift: UIViewRepresentable {
    let key: [String]
    let content: AnyView
    let contentHeight: CGFloat
    let loop: CGFloat
    let speed: Double
    let phase: Double
    /// Sube en vez de bajar («Marea lenta»: una columna baja y la de al lado sube).
    var rising = false
    let enabled: Bool
    let running: Bool

    func makeUIView(context: Context) -> DriftView {
        let view = DriftView(content, contentHeight: contentHeight, loop: loop, duration: Double(loop) / max(speed, 1), phase: phase, rising: rising)
        view.key = key
        return view
    }

    func updateUIView(_ view: DriftView, context: Context) {
        if view.key != key { view.key = key; view.host.rootView = content }
        view.set(enabled: enabled, running: running)
    }
}

/// La vista de `CoreDrift`: aloja la tira de SwiftUI y anima su capa hacia abajo, sin fin.
private final class DriftView: UIView {
    let host: UIHostingController<AnyView>
    var key: [String] = []
    private let contentHeight: CGFloat, loop: CGFloat, duration: Double, phase: Double, rising: Bool
    private var enabled = false, running = false
    private static let animationKey = "orbital.coverDrift"

    init(_ content: AnyView, contentHeight: CGFloat, loop: CGFloat, duration: Double, phase: Double, rising: Bool) {
        host = UIHostingController(rootView: content)
        self.contentHeight = contentHeight; self.loop = loop; self.duration = duration; self.phase = phase; self.rising = rising
        host.safeAreaRegions = []   // el muro no se recorre por la barra ni la isla: va de orilla a orilla
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = true
        addSubview(host.view)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: contentHeight)
    }

    /// Al volver a la ventana (otra pestaña, la app al frente) la animación sigue ahí; si iOS la quitó, se vuelve a poner.
    /// El controlador del muro se cuelga del de la pantalla (como pide UIKit): así recibe el tamaño de letra, la apariencia y
    /// los cambios de la ventana por la vía normal (auditoría del 31 oct 2026, B8).
    /// Se cuelga una vez y se queda colgado mientras el muro exista: antes se descolgaba al salir de la ventana y se volvía a
    /// colgar al volver, y cada cambio de pestaña acomodaba otra vez las ocho columnas (~200 pósters) en el hilo principal
    /// (Fernando, 1 nov 2026: «Explorar cambia lento»). Se descuelga al irse el muro (`deinit`).
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, let parent = owningController, host.parent !== parent {
            if host.parent != nil { host.willMove(toParent: nil); host.removeFromParent() }
            parent.addChild(host)
            host.didMove(toParent: parent)
        }
        sync()
    }

    deinit {
        MainActor.assumeIsolated { [host] in
            guard host.parent != nil else { return }
            host.willMove(toParent: nil)
            host.removeFromParent()
        }
    }

    /// El controlador más cercano hacia arriba (el de SwiftUI que pinta esta pantalla).
    private var owningController: UIViewController? {
        var next = superview?.next
        while let responder = next {
            if let controller = responder as? UIViewController { return controller }
            next = responder.next
        }
        return nil
    }

    func set(enabled: Bool, running: Bool) {
        guard enabled != self.enabled || running != self.running else { return }
        (self.enabled, self.running) = (enabled, running)
        sync()
    }

    private func sync() {
        let layer = host.view.layer
        guard enabled else {
            layer.removeAnimation(forKey: Self.animationKey)
            (layer.speed, layer.timeOffset, layer.beginTime) = (1, 0, 0)
            layer.transform = CATransform3DMakeTranslation(0, -loop * CGFloat(phase), 0)
            return
        }
        if layer.animation(forKey: Self.animationKey) == nil, window != nil {
            layer.transform = CATransform3DIdentity
            let fall = CABasicAnimation(keyPath: "transform.translation.y")
            fall.fromValue = rising ? 0 : -loop
            fall.toValue = rising ? -loop : 0
            fall.duration = duration
            fall.timeOffset = duration * phase
            fall.repeatCount = .infinity
            fall.timingFunction = CAMediaTimingFunction(name: .linear)
            fall.isRemovedOnCompletion = false   // sobrevive a que la app pase al fondo
            layer.add(fall, forKey: Self.animationKey)
        }
        // Pausa y reanuda en el mismo punto (el reloj de la capa se detiene; nada brinca al volver a la vista).
        if running, layer.speed == 0 {
            let pausedAt = layer.timeOffset
            (layer.speed, layer.timeOffset, layer.beginTime) = (1, 0, 0)
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
        } else if !running, layer.speed != 0 {
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            (layer.speed, layer.timeOffset) = (0, now)
        }
    }
}
