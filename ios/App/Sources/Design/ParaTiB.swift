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
            .overlay(alignment: .bottomTrailing) {
                // El ícono del mosaico abajo a la derecha, negro sobre blanco (Fernando, 31 oct 2026: en vez de «Pasear por
                // el mosaico»).
                Button(action: onWalk) {
                    Image(systemName: "square.grid.3x3.fill").font(DS.TextRecipe.cardTitle.font.weight(.semibold))
                        .foregroundStyle(DS.backdropDeep)
                        .frame(width: DS.ParaTiB.walkButton, height: DS.ParaTiB.walkButton)
                        .background(DS.paper, in: Circle())
                        .shadow(color: DS.scrimStrong, radius: DS.Space.s2, y: DS.Space.s1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Pasear por el mosaico"))
                .accessibilityIdentifier("paraTi-walk-mosaic")
                .padding(.horizontal, DS.Space.gutter)
            }
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
                .accessibilityLabel(Text(verbatim: "\(order.count) " + order.prefix(DS.ParaTiB.coverColumns).map { $0.split(separator: "/").suffix(2).joined(separator: "/") }.joined(separator: ",")))
                .accessibilityIdentifier("paraTi-cover-wall")
                .allowsHitTesting(false)
        }
        #endif
    }

    /// El vaivén: el muro baja y sube un renglón sobre su diagonal, sin prisa. Lo mueve Core Animation sobre el muro ya
    /// pintado (`CoreDrift`): con `phaseAnimator` SwiftUI volvía a pintar los 72 pósters en cada cuadro, un núcleo entero
    /// en reposo y el muro negro o apagado mientras tanto (Fernando, 31 oct 2026). Quieto con «Reducir movimiento» y en las
    /// pruebas (`-demo-no-idle`); fuera de pantalla se pausa donde iba.
    private var moving: some View {
        CoreDrift(content: AnyView(wall.environment(\.perfTag, perfTag)), enabled: !still, running: onScreen)
    }

    private var still: Bool {
        #if DEBUG
        if Demo.noIdle { return true }
        #endif
        return reduceMotion
    }

    /// Un muro fijo (no perezoso): girado y más alto que su marco dentro del desplazamiento de la página, una rejilla perezosa
    /// no sabía qué piezas se veían y las armaba tarde (al volver del mosaico se quedaba negro unos segundos).
    private var wall: some View {
        let columns = DS.ParaTiB.coverColumns
        let rows = stride(from: 0, to: order.count, by: columns).map { Array(order[$0..<min($0 + columns, order.count)]) }
        return VStack(spacing: DS.Space.s2) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: DS.Space.s2) {
                    ForEach(rows[r].indices, id: \.self) { c in PosterView(url: rows[r][c], title: "", maxPoints: DS.Image.mosaic) }
                }
            }
        }
        .frame(width: DS.ParaTiB.coverWall)
        .rotationEffect(.degrees(DS.ParaTiB.coverTilt))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DS.Space.s4) {
                PosterFan(posters: posters, width: DS.ParaTiB.deckPoster)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Eyebrow(text: Text("Encuentra tu match perfecto"), reason: true)
                    Text("¿Qué vemos hoy?").recipe(.section)
                    Text("A la derecha la guardas, a la izquierda no.").recipe(.footnote, color: DS.textMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s4)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
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
/// abanico y «Ver la colección».
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
                Text(verbatim: name).recipe(.title).lineLimit(2).minimumScaleFactor(DS.Size.titleShrink)
                Text(verbatim: blurb).recipe(.footnote, color: DS.textMuted).lineLimit(2)
                DSCapsuleLabel(title: Text("Ver la colección"), symbol: "chevron.right", symbolFirst: false).padding(.top, DS.Space.s2)
            }
            Spacer(minLength: 0)
            if !posters.isEmpty { PosterFan(posters: posters, width: DS.ParaTiB.seasonPoster) }
        }
        .padding(DS.Space.s4)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous).fill(DS.surface)
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
            Image(systemName: "chevron.right").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textFaint)
        }
        .padding(DS.Space.s2)
        .padding(.trailing, DS.Space.s2)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Un vaivén lento hecho por Core Animation: SwiftUI pinta el contenido una vez y el servidor de render lo desliza, sin
/// volver a pintarlo ni despertar a la app en cada cuadro (`phaseAnimator` lo repintaba entero 60 veces por segundo).
/// `running` en falso lo pausa donde va, sin brincar; `enabled` en falso lo quita y lo deja en su lugar.
private struct CoreDrift: UIViewRepresentable {
    let content: AnyView
    let enabled: Bool
    let running: Bool

    func makeUIView(context: Context) -> DriftView { DriftView(content) }

    func updateUIView(_ view: DriftView, context: Context) {
        view.host.rootView = content
        view.set(enabled: enabled, running: running)
    }
}

/// La vista de `CoreDrift`: aloja el contenido de SwiftUI y anima su capa (ida y vuelta, sin fin).
private final class DriftView: UIView {
    let host: UIHostingController<AnyView>
    private var enabled = false, running = false
    private static let key = "orbital.coverDrift"

    init(_ content: AnyView) {
        host = UIHostingController(rootView: content)
        host.safeAreaRegions = []   // el muro no se recorre por la barra ni la isla: va de orilla a orilla
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        addSubview(host.view)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.frame = bounds
    }

    /// Al volver a la ventana (otra pestaña, la app al frente) la animación sigue ahí; si iOS la quitó, se vuelve a poner.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        sync()
    }

    func set(enabled: Bool, running: Bool) {
        guard enabled != self.enabled || running != self.running else { return }
        (self.enabled, self.running) = (enabled, running)
        sync()
    }

    private func sync() {
        let layer = host.view.layer
        guard enabled else {
            layer.removeAnimation(forKey: Self.key)
            (layer.speed, layer.timeOffset, layer.beginTime) = (1, 0, 0)
            return
        }
        if layer.animation(forKey: Self.key) == nil, window != nil {
            let drift = CABasicAnimation(keyPath: "transform.translation")
            drift.fromValue = NSValue(cgSize: .zero)
            drift.toValue = NSValue(cgSize: CGSize(width: DS.ParaTiB.coverDriftX, height: DS.ParaTiB.coverDrift))
            drift.duration = DS.ParaTiB.coverDriftSeconds
            drift.autoreverses = true
            drift.repeatCount = .infinity
            drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            drift.isRemovedOnCompletion = false   // sobrevive a que la app pase al fondo
            layer.add(drift, forKey: Self.key)
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
