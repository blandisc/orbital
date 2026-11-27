import SwiftUI
import OrbitalCore
import OrbitalAddons

// Aprende, a fondo (AF1-B · AF3-B; Fernando, 19 nov 2026: «construye las lecciones de la app, ponle mucho detalle»;
// prototipo en docs/producto/aprende-a-fondo-2026-11-19/prototipo/). Las piezas con que se dibujan las escenas de las
// lecciones: un lienzo fijo de 402 × 330 que se escala al ancho, el tiempo `t` desde que entra la escena y piezas puestas en
// coordenadas del lienzo (el iPhone, la TV, el póster, el dedo fantasma, el aviso de arriba, la hoja de Versión). Cada escena
// es pura en `t`: lo mismo en `t` se ve igual, así que con «Reducir movimiento» se pinta su último cuadro y ya.

/// El ritmo de las escenas: resortes y curvas en función del tiempo (los mismos del prototipo y de la guía).
enum LessonMotion {
    static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    static func lerp(_ a: Double, _ b: Double, _ k: Double) -> Double { a + (b - a) * k }
    static func easeOut(_ x: Double) -> Double { GuideTraktScene.Motion.easeOut(x) }
    /// De 0 a 1 entre `a` y `b`, con arranque y llegada suaves.
    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double { let c = clamp((x - a) / (b - a)); return c * c * (3 - 2 * c) }
    static func spring(_ t: Double, _ response: Double, _ bounce: Double) -> Double { GuideTraktScene.Motion.spring(t, response, bounce) }
    /// La entrada de una pieza en `s`: su opacidad y cuánto le falta por subir (se asienta con un resorte sin rebote).
    static func enter(_ t: Double, _ s: Double, _ rise: CGFloat = 12) -> (o: Double, y: CGFloat) {
        let item = GuideTraktScene.Motion.item(t, s, rise)
        return (item.opacity, item.rise)
    }
    /// Una marca que brota con un poco de rebote (la palomita, el chip del resultado).
    static func pop(_ t: Double, _ s: Double) -> Double { spring(t - s, 0.5, 0.25) }
    /// Un punto de una curva de Bézier cuadrática (lo que viaja en arco).
    static func quad(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
        let u = 1 - k
        return CGPoint(x: u * u * a.x + 2 * u * k * c.x + k * k * b.x, y: u * u * a.y + 2 * u * k * c.y + k * k * b.y)
    }
}

/// Lo que se ve en las escenas: pósters de verdad (lo popular de ahora, como la bienvenida), películas y series aparte para
/// que la escena de los episodios lleve una serie. Sin red, los nombres sobre su fondo.
struct LessonArt: Equatable {
    struct Item: Equatable {
        var url: String?
        var title: String
        var imdb = ""
        /// El fondo a lo ancho (16:9): lo que se ve en un video o una TV dibujados. Sin él, el póster.
        var wide: String?
    }
    var movies: [Item] = []
    var series: [Item] = []
    /// Tu nube, para decirla por su nombre («Tu nube (TorBox)»).
    var cloud: DebridService = .realDebrid

    func movie(_ i: Int) -> Item { movies.isEmpty ? Item(url: nil, title: "") : movies[i % movies.count] }
    func show(_ i: Int) -> Item { series.isEmpty ? movie(i + 3) : series[i % series.count] }
    /// Una mezcla para los mosaicos: película, serie, película…
    func mixed(_ i: Int) -> Item { i % 2 == 0 ? movie(i / 2) : show(i / 2) }
}

/// El lienzo de una escena: 402 × 330 puntos que se escalan al ancho disponible; el reloj corre desde `start` y se detiene
/// poco después de `end` (no gasta batería mirando una escena quieta), salvo `live` (las de «Pruébalo», que se animan al
/// tocarlas). Con «Reducir movimiento», el último cuadro. La letra de adentro no crece con el tamaño del texto del
/// sistema: es un dibujo (el titular y la línea de abajo sí crecen). Sigue el modo claro u oscuro de la app (27 nov 2026: forzada
/// en oscuro, en claro la letra salía blanca sobre el fondo claro); lo que es oscuro siempre (el iPhone, la tele, las etiquetas
/// flotantes) lo dice cada pieza.
struct LessonCanvas<Content: View>: View {
    let end: Double
    let start: Date
    var live = false
    let label: Text
    @ViewBuilder let content: (Double) -> Content
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var size: CGSize { DS.Lesson.canvas }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.size.width, geo.size.height / Self.size.height)
            TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion || (settled && !live))) { ctx in
                let t = reduceMotion ? end + 1 : ctx.date.timeIntervalSince(start)
                ZStack(alignment: .topLeading) { content(t) }
                    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
                    .clipped()   // nada de la escena pasa por encima del texto de abajo
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .dynamicTypeSize(.large)
        .task(id: start) {
            settled = false
            // Si la escena vuelve a empezar, esta espera se cancela y no la congela (19 nov 2026: la primera pantalla salía vacía).
            guard (try? await Task.sleep(for: .milliseconds(Int((end + DS.Lesson.settleAfter) * 1000)))) != nil else { return }
            settled = true
        }
        .accessibilityElement(children: live ? .contain : .ignore)
        .accessibilityLabel(label)
    }
}

extension View {
    /// La pieza con su esquina en (x, y) del lienzo.
    func sceneAt(_ x: CGFloat, _ y: CGFloat) -> some View { offset(x: x, y: y) }
    /// La pieza con su tamaño en el lienzo.
    func sceneBox(_ w: CGFloat, _ h: CGFloat) -> some View { frame(width: w, height: h) }
    /// El ancho de la pieza en el lienzo (`fits`: como mucho ese ancho, la burbuja que crece con lo que dices).
    func sceneWidth(_ w: CGFloat, alignment: Alignment = .center, fits: Bool = false) -> some View {
        frame(width: fits ? nil : w, alignment: alignment).frame(maxWidth: fits ? w : nil, alignment: alignment)
    }
    /// La pieza en su momento: opacidad, cuánto se mueve, escala y giro. La escala y el giro solo en piezas sin `sceneAt`
    /// (las que vuelan con `dx`/`dy`): después de `sceneAt` crecen y giran alrededor de la esquina del lienzo y la pieza se
    /// sale de su lugar. Con `sceneAt`, `.scaleEffect`/`.rotationEffect` van antes (DesignRulesTests lo vigila).
    func scenePut(_ o: Double, _ dx: CGFloat = 0, _ dy: CGFloat = 0, _ s: CGFloat = 1, _ rot: Double = 0) -> some View {
        scaleEffect(s).rotationEffect(.degrees(rot)).offset(x: dx, y: dy).opacity(LessonMotion.clamp(o))
    }
}

/// Un póster en la escena: la imagen recortada con sus esquinas y su sombra.
struct LessonPoster: View {
    let item: LessonArt.Item
    let w: CGFloat
    let h: CGFloat
    var radius: CGFloat?
    var shadow = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? max(DS.Radius.xs, w * DS.Lesson.posterShare), style: .continuous)
        PosterView(url: item.url, title: item.title, aspect: w / h, bleed: true, maxPoints: DS.Image.mosaic, decorative: true)   // no-es-título: ya pasó por titleName al cargar
            .sceneBox(w, h).clipShape(shape)
            .shadow(shadow ? DS.Elevation.floating : DS.Elevation.floating.color(.clear))
    }
}

/// El dedo fantasma: llega, toca (se hunde y suelta un anillo turquesa) y se va. (x, y) es el centro del toque; `at`, cuándo.
struct LessonFinger: View {
    let t: Double
    let x: CGFloat
    let y: CGFloat
    let at: Double

    var body: some View {
        let M = LessonMotion.self
        let a = M.clamp((t - (at - 0.35)) / 0.35), d = M.clamp((t - (at + 0.15)) / 0.3)
        let press = max(0, 1 - pow((t - at) / 0.09, 2))
        let side = DS.Lesson.finger
        LessonFingerDot()
            .background(Circle().stroke(DS.fresh.opacity(DS.Lesson.ringOpacity * press), lineWidth: DS.Lesson.ring * press))
            .sceneBox(side, side)
            .scenePut(a * (1 - d) * DS.Lesson.fingerOpacity, x - side / 2 + (1 - M.easeOut(a)) * 14, y - side / 2 + (1 - M.easeOut(a)) * 18,
                      1 - DS.Lesson.fingerPress * press)
            .allowsHitTesting(false)
    }
}

/// La yema del dedo fantasma: blanca translúcida en oscuro (y dentro del iPhone dibujado); en claro, de tinta, para que se vea
/// sobre el fondo claro (27 nov 2026).
struct LessonFingerDot: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = scheme == .dark ? DS.paper : DS.text
        Circle().fill(ink.opacity(DS.Lesson.fingerFill))
            .overlay(Circle().strokeBorder(ink.opacity(DS.Lesson.fingerRim), lineWidth: DS.Stroke.regular))
    }
}

/// Un aparato dibujado: el iPhone (o el iPad) con su marco y su pantalla oscura, y adentro lo que pase.
struct LessonPhone<Inner: View>: View {
    let w: CGFloat
    let h: CGFloat
    /// La esquina en proporción del ancho: la del iPhone, o `DS.Lesson.padCorner` para el iPad (más cuadrado).
    var corner = DS.Lesson.phoneCorner
    @ViewBuilder var inner: Inner

    var body: some View {
        let outer = RoundedRectangle(cornerRadius: w * corner, style: .continuous)
        ZStack(alignment: .topLeading) {
            outer.fill(DS.backdropDeep)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [DS.surfaceRaised, DS.surface], startPoint: .top, endPoint: .bottom)
                inner
            }
            .sceneBox(w - 2 * DS.Lesson.bezel, h - 2 * DS.Lesson.bezel)
            .clipShape(RoundedRectangle(cornerRadius: max(0, w * corner - DS.Lesson.bezel), style: .continuous))
            .sceneAt(DS.Lesson.bezel, DS.Lesson.bezel)
            outer.strokeBorder(DS.Lesson.deviceRim, lineWidth: DS.Stroke.regular)
        }
        .sceneBox(w, h)
        .environment(\.colorScheme, .dark)
    }
}

/// La TV dibujada: su pantalla, el cuello y la base. `w` × `h` es la pantalla.
struct LessonTV<Inner: View>: View {
    let w: CGFloat
    let h: CGFloat
    @ViewBuilder var inner: Inner

    var body: some View {
        let screen = RoundedRectangle(cornerRadius: DS.Lesson.tvCorner, style: .continuous)
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                screen.fill(DS.backdropDeep)
                ZStack(alignment: .topLeading) {
                    LinearGradient(colors: [DS.surfaceRaised, DS.surface], startPoint: .top, endPoint: .bottom)
                    inner
                }
                .sceneBox(w - 2 * DS.Lesson.bezel, h - 2 * DS.Lesson.bezel)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous))
                .sceneAt(DS.Lesson.bezel, DS.Lesson.bezel)
                screen.strokeBorder(DS.Lesson.deviceRim, lineWidth: DS.Stroke.regular)
            }
            .sceneBox(w, h)
            Rectangle().fill(DS.Lesson.deviceRim).sceneBox(DS.Lesson.tvNeck, DS.Lesson.tvNeck)
            Capsule().fill(DS.Lesson.deviceRim).sceneBox(DS.Lesson.tvBase, DS.Lesson.tvBaseHeight)
        }
        .environment(\.colorScheme, .dark)   // la pantalla de la tele, oscura en claro y en oscuro (como el iPhone dibujado)
    }
}

/// Una etiqueta flotante («Latino · 1080p · Al instante», «Sigue en el minuto 34»): oscura, con su borde fino.
struct LessonChip<Inner: View>: View {
    @ViewBuilder var inner: Inner

    var body: some View {
        HStack(spacing: DS.Space.s1) { inner }
            .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.text).lineLimit(1).fixedSize()
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s2)
            .background(DS.backdropDeep.opacity(DS.Lesson.chipFill), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(DS.hairline, lineWidth: DS.Stroke.hairline))
            .shadow(DS.Elevation.floating)
            .environment(\.colorScheme, .dark)   // oscura también con la app en claro: sin esto, fondo negro y letra negra
    }
}

/// El aviso de arriba (como el del sistema): el ícono de Orbital, quién avisa y qué.
struct LessonNote: View {
    let title: Text
    let detail: Text
    var symbol = "bell.fill"

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.fresh)
                .sceneBox(DS.Lesson.noteIcon, DS.Lesson.noteIcon)
                .background(DS.backdropDeep, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: DS.Lesson.tight) {
                title.font(DS.TextRecipe.label.font).foregroundStyle(DS.text)
                detail.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s2)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(DS.Elevation.floating)
        .sceneBox(DS.Lesson.canvas.width - 2 * DS.Space.s6, DS.Lesson.noteHeight)
    }
}

/// Una tarjeta de la app en la escena (la hoja de Versión, los episodios): su título y sus renglones.
struct LessonCard<Rows: View>: View {
    let title: Text
    let w: CGFloat
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title.font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text).lineLimit(1)
                .padding(.horizontal, DS.Space.s4).padding(.top, DS.Space.s4).padding(.bottom, DS.Space.s2)
            rows
        }
        .frame(width: w, alignment: .topLeading)
        .dsCard(fill: DS.surfaceRaised)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).strokeBorder(DS.hairline, lineWidth: DS.Stroke.hairline))
        .shadow(DS.Elevation.floating)
    }
}

/// Un renglón de una tarjeta de la escena: algo a la izquierda (la bandera), qué es con su detalle y algo a la derecha.
struct LessonRow<Leading: View, Trailing: View>: View {
    let title: Text
    var detail: Text?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            leading
            VStack(alignment: .leading, spacing: DS.Lesson.tight) {
                title.font(DS.TextRecipe.secondary.font).foregroundStyle(DS.text)
                if let detail { detail.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted) }
            }
            .lineLimit(1)
            Spacer(minLength: DS.Space.s2)
            trailing
        }
        .padding(.horizontal, DS.Space.s4)
        .frame(height: DS.Lesson.row)
        .overlay(alignment: .top) { Rectangle().fill(DS.hairline).frame(height: DS.Stroke.hairline) }
    }
}

/// «Al instante» (turquesa, con su rayo) o «Por pedir» (ámbar, con su flecha): el estado de una versión.
struct LessonReadiness: View {
    enum State { case instant, request, progress(Int), ready }
    let state: State

    var body: some View {
        Group {
            switch state {
            case .instant: Label("Al instante", systemImage: "bolt.fill").foregroundStyle(DS.fresh)
            case .request: Label("Por pedir", systemImage: "arrow.down").foregroundStyle(DS.warning)
            case .progress(let n): Text(verbatim: "\(n)\u{00A0}%").monospacedDigit().foregroundStyle(DS.warning)
            case .ready: Label("Lista", systemImage: "checkmark").foregroundStyle(DS.fresh)
            }
        }
        .font(DS.TextRecipe.label.font).labelStyle(.titleAndIcon).imageScale(.small).lineLimit(1).fixedSize()
    }
}

/// La barra de avance de un video en la escena.
struct LessonProgress: View {
    let value: Double
    var tint: Color = DS.paper

    var body: some View {
        Capsule().fill(DS.paper.opacity(DS.Lesson.trackOpacity))
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(tint).frame(width: g.size.width * LessonMotion.clamp(value)) }
            }
            .frame(height: DS.Lesson.progress)
    }
}

/// Un hilo turquesa punteado que se dibuja de `a` a `b` pasando cerca de `c` (lo que viaja de un aparato a otro).
struct LessonThread: View {
    let a: CGPoint
    let c: CGPoint
    let b: CGPoint
    let drawn: Double
    var dashed = true
    var width = DS.Stroke.regular

    var body: some View {
        Path { $0.move(to: a); $0.addQuadCurve(to: b, control: c) }
            .trim(from: 0, to: LessonMotion.clamp(drawn))
            .stroke(DS.fresh, style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dashed ? DS.Lesson.dash : []))
            .opacity(drawn > 0 ? 1 : 0)
    }
}

/// Un letrero chico de la escena («Tu iPhone», «Tu nube»).
struct LessonCaption: View {
    let text: Text
    let w: CGFloat
    var alignment: TextAlignment = .center

    var body: some View {
        text.font(DS.TextRecipe.caption.font).foregroundStyle(DS.textMuted).multilineTextAlignment(alignment)
            .frame(width: w, alignment: alignment == .center ? .center : .leading)
    }
}

/// El botón principal de una ficha en miniatura («Ver», «Ver en la TV»): claro, con su ícono.
struct LessonPlayButton: View {
    let title: Text
    let symbol: String
    var compact = false

    var body: some View {
        HStack(spacing: DS.Space.s1) { Image(systemName: symbol); title }
            .font(compact ? DS.TextRecipe.badge.font : DS.TextRecipe.labelLarge.font).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            .foregroundStyle(DS.onPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.primary, in: Capsule())
    }
}

/// Un video en la escena: el arte del título a lo ancho, oscuro abajo, con su barra de avance.
struct LessonVideo: View {
    let item: LessonArt.Item
    let w: CGFloat
    let h: CGFloat
    var progress: Double = 0
    var corner: CGFloat = DS.Radius.lg
    var showsBar = true

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [DS.surfaceRaised, DS.surface], startPoint: .top, endPoint: .bottom)   // mientras llega el arte: nunca un hueco negro
            PosterView(url: item.wide ?? item.url, title: item.title, aspect: w / h, bleed: true, maxPoints: DS.Image.mosaic, decorative: true).sceneBox(w, h).clipped()   // no-es-título: ya pasó por titleName al cargar
            if showsBar { LessonProgress(value: progress).padding(.horizontal, w * DS.Lesson.barShare).padding(.bottom, h * DS.Lesson.barShare) }
        }
        .sceneBox(w, h)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(DS.Elevation.floating)
    }
}

/// «Pruébalo»: el anillo turquesa que late sobre lo que hay que tocar hasta que lo tocas (quieto con «Reducir movimiento»).
struct LessonTryRing: View {
    /// Redondo (un círculo o una cápsula) en lugar del rectángulo de una fila.
    var round = false
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: round ? DS.Radius.pill : DS.Radius.md, style: .continuous)
            .strokeBorder(DS.fresh, lineWidth: DS.Lesson.tryRing)
            .padding(.horizontal, round ? 0 : DS.Space.s2).padding(.vertical, round ? 0 : DS.Space.s1)
            .opacity(dim ? DS.Opacity.faint : 1)
            .animation(DS.Lesson.pulse(reduceMotion), value: dim)
            .onAppear { dim = !reduceMotion }
            .allowsHitTesting(false)
    }
}
