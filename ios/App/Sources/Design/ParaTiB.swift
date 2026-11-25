import SwiftUI
import OrbitalModels
import OrbitalCore

// Las piezas de Para ti B (docs/producto/inicio-benchmark/para-ti/): los círculos para saltar a cada parte, la portada del mosaico y la
// puerta de «Decide por mí».

/// La portada de Para ti: un muro de pósters inclinado que se funde con el fondo. MO1 (Fernando, 13 nov 2026: «lo saquemos de
/// la barra de menú… y lo pongamos de manera creativa abajo»): es la puerta del mosaico, con su chapa (`MosaicDoorBadge`); se
/// hunde al tocarla (`DS.Motion.press`), se endereza y crece al abrir y hace el camino inverso al volver. La primera vez se
/// endereza sola un momento (nunca con «Reducir movimiento»); jalar más allá de «actualizar» también la abre. Sin piezas
/// (`count` 0) no se toca. Sube detrás de la barra, se apaga en las orillas, cambia de orden con pósters nuevos y se
/// desliza despacio en diagonal (quieto con «Reducir movimiento» o fuera de pantalla).
struct MosaicCover: View {
    let posters: [String]
    /// El muro de la última vez (de qué pósters salió y su orden), en `ParaTiModel`: sobrevive a que la pantalla se vuelva
    /// a armar. El orden lo decide `CoverWall` (OrbitalModels, con pruebas).
    let memory: CoverWallMemory
    /// Cuántas piezas trae el mosaico (lo que dice la chapa). 0: la portada no es puerta.
    var count = 0
    /// Ya llegó lo que se sugiere: el aviso de la primera vez espera esto (si no, el muro se revolvía en medio del aviso).
    var settled = true
    let onWalk: () -> Void
    @State private var order: [String]
    @State private var onScreen = true
    /// 0…1: qué tan abierta (derecha y crecida) está, por un toque o por el aviso de la primera vez. Lo que se jala lo suma
    /// `CoverOpening`.
    @State private var opening: CGFloat
    @State private var walking: Task<Void, Never>?
    /// MT4-A: dónde empieza el muro en la pantalla, sin inclinar.
    @State private var wallX: CGFloat = 0
    /// Cuántas columnas del muro ya están armadas. La primera vez entran una por una (`coverColumnStep`): armarlas todas
    /// juntas (unos 200 pósters, cada columna con su motor) trababa medio segundo el cambio a Explorar (17 nov 2026). Las
    /// siguientes veces, todas desde el primer cuadro.
    @State private var built = MosaicCover.firstBuilt
    @MainActor private static var builtColumns = 0
    @MainActor private static var firstBuilt: Int {
        #if DEBUG
        if MacSelfCheck.off.contains("steps") { return 99 }   // para comparar: todas de una vez
        #endif
        return builtColumns
    }
    @AppStorage(MosaicCover.hintKey) private var hintSeen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.perfTag) private var perfTag
    @Environment(RefreshPull.self) private var pull: RefreshPull?
    /// MT3: cuánto se abrió la puerta (al tocarla o al jalar): el muro baja hasta tapar la pantalla.
    private var reach: CGFloat {
        guard isDoor else { return 0 }
        return max(opening, (pull?.entering ?? false) ? 1 : (pull?.doorProgress ?? 0))
    }
    /// MT4-A: lo que hay que recorrer el muro (a lo más media columna) para que una columna empiece donde la primera del mosaico.
    private var alignShift: CGFloat {
        guard matchedWidth != nil else { return 0 }
        let pitch = columnWidth + DS.Space.s2
        var d = (DS.Space.s2 - wallX).truncatingRemainder(dividingBy: pitch)
        if d > pitch / 2 { d -= pitch } else if d < -pitch / 2 { d += pitch }
        return d
    }
    /// Ya se vio que la portada se abre sola (una vez, en los ajustes locales).
    static let hintKey = "mosaic-door-hint-seen"
    /// Se abrió para entrar al mosaico: al volver, la portada sale derecha y se inclina (el camino inverso).
    @MainActor static var cameFromMosaic = false

    init(posters: [String], memory: CoverWallMemory, count: Int = 0, settled: Bool = true, onWalk: @escaping () -> Void) {
        self.posters = posters
        self.memory = memory
        self.count = count
        self.settled = settled
        self.onWalk = onWalk
        // Al volver del mosaico (o de otra pestaña) el muro de antes ya en el primer cuadro: sin un instante vacío.
        _order = State(initialValue: memory.order(for: posters, size: DS.ParaTiB.coverPosters))
        _opening = State(initialValue: MosaicCover.cameFromMosaic ? 1 : 0)
    }

    private var isDoor: Bool { count > 0 }

    /// Cómo entra y sale el mosaico: crece desde arriba (donde estaba la portada) con un fundido; con «Reducir movimiento»,
    /// solo el fundido.
    /// MT2 (25 nov 2026, «ánclala a los pósters… seamless entre los pósters que están en pantalla y los del mosaico»): el
    /// mosaico entra con el tamaño y la inclinación del muro (sus pósters del mismo ancho que los del muro) y se endereza y
    /// crece a su lugar mientras el muro hace lo mismo y se apaga: a medio camino coinciden.
    static func mosaicTransition(_ reduce: Bool) -> AnyTransition {
        // MT4-A: el mosaico arranca con los mismos pósters del muro en su mismo lugar: entra de golpe (sin fundido entre dos
        // muros) y se va con un fundido al volver.
        .asymmetric(insertion: .identity, removal: .opacity)
    }
    /// Lo que deja el mosaico (Explorar) se apaga y crece tantito, como si entraras: antes se quitaba de golpe.
    static func listsTransition(_ reduce: Bool) -> AnyTransition {
        // MT4-A: al entrar al mosaico, Explorar se quita de una vez (el mosaico ya es lo que se veía; con fundido se veía el
        // muro regresar encimado); al volver, entra con un fundido.
        .asymmetric(insertion: .opacity, removal: .identity)
    }
    /// El paso entre Explorar y el mosaico: un resorte suave y pausado.
    static func doorAnimation(_ reduce: Bool) -> Animation { DS.Motion.door(reduce) ?? DS.Motion.fade }

    var body: some View {
        Group {
            if isDoor {
                Button(action: walk) { cover }
                    .buttonStyle(MosaicDoorPress())
                    .accessibilityLabel(Text("Pasea por tus \(count)"))
                    .accessibilityHint(Text("Abre el mosaico"))
                    .accessibilityIdentifier("paraTi-walk-mosaic")
            } else {
                cover
            }
        }
        .overlay { demoProbe }
        .onScrollVisibilityChange(threshold: DS.ParaTiB.coverVisibleFrom) { onScreen = $0 }
        // Otro muro solo cuando llegan pósters de verdad distintos; al volver del mosaico, el mismo de antes (Fernando,
        // 31 oct 2026: revolverlo otra vez pedía pósters nuevos y el muro se quedaba negro unos segundos).
        .onChange(of: posters) { order = memory.order(for: posters, size: DS.ParaTiB.coverPosters) }
        .task(id: isDoor && settled) { await returnOrHint() }
        .task(id: columns) { await buildColumns() }
        .onDisappear { walking?.cancel() }
    }

    /// El muro con su chapa. La chapa va anclada a la orilla de abajo de la portada, dentro de ella (no flota sobre lo demás).
    private var cover: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: DS.ParaTiB.coverHeight)
            .overlay(alignment: .bottom) {
                // El arte ocupa más que su marco (arriba y abajo) pero no ensancha la página: se recorta a los lados. Con su
                // propio alto (no con un margen negativo): la máscara y el recorte medían el marco de 300 y cortaban en seco
                // todo lo que subía detrás del título y la barra (Fernando, 31 oct 2026: «ahora no se ve bien»).
                // MT3 (25 nov 2026, «cuando le das para abajo los pósters se empiezan a poner vertical, desaparecen los otros
                // elementos y quedan esos pósters»): mientras se abre, el muro baja `doorReveal` sobre un fondo propio y tapa
                // «Decide por mí» y las listas; al soltar, el mosaico aparece en su lugar con un fundido.
                ZStack {
                    DS.bg.opacity(Double(reach))
                    // MT4-A: los pósters se quedan donde estaban (el marco crece hacia abajo; sin esto bajaban la mitad).
                    moving.modifier(CoverOpening(opening: opening, door: isDoor)).offset(y: -DS.ParaTiB.doorReveal * reach / 2)
                    veil.modifier(CoverOpening(opening: opening, door: isDoor, unveil: true))
                }
                .frame(height: DS.ParaTiB.coverBleedUp + DS.ParaTiB.coverHeight + DS.ParaTiB.coverBleedDown + DS.ParaTiB.doorReveal * reach)
                .mask { fade }
                .mask { mosaicEdge }
                .clipped()
                .offset(y: DS.ParaTiB.coverBleedDown + DS.ParaTiB.doorReveal * reach)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .overlay(alignment: .bottomLeading) {
                // MT4-A: la chapa se apaga mientras se abre (no es del mosaico) y va un poco más abajo (Fernando, 25 nov 2026).
                if isDoor { MosaicDoorBadge(count: count).padding(.horizontal, DS.Space.gutter).offset(y: DS.ParaTiB.badgeDrop).opacity(1 - Double(reach)) }
            }
            .contentShape(Rectangle())
    }

    /// Tocarla: el muro se endereza y crece (`DS.Motion.grow`) y entonces entra el mosaico. Con «Reducir movimiento», de una vez.
    private func walk() {
        MosaicCover.cameFromMosaic = true
        guard let grow = DS.Motion.grow(reduceMotion) else { onWalk(); return }
        walking?.cancel()
        withAnimation(grow) { opening = 1 }
        // MT4-A: ya derecho, se mide dónde quedó cada póster y el mosaico arranca con esos mismos. Con un reloj y no con el
        // `completion` de la animación: a veces no llegaba y el muro se quedaba abierto sin entrar al mosaico.
        walking = Task { @MainActor in
            guard (try? await Task.sleep(for: .seconds(DS.Motion.growDuration))) != nil else { return }
            MosaicHandoff.capture()
            onWalk()
        }
    }

    /// De vuelta del mosaico, la portada se inclina otra vez (`DS.Motion.fold`). La primera vez, se endereza sola un momento y
    /// regresa, para enseñar que se abre: una sola vez, nunca con «Reducir movimiento» ni fuera de pantalla.
    private func returnOrHint() async {
        if MosaicCover.cameFromMosaic || opening > 0 {
            MosaicCover.cameFromMosaic = false
            try? await Task.sleep(for: DS.Motion.tabSettle)
            withAnimation(DS.Motion.fold(reduceMotion)) { opening = 0 }
            return
        }
        var forced = false, quiet = reduceMotion
        #if DEBUG
        forced = Demo.isOn && Demo.has("-demo-door-hint")   // capturas: el aviso aunque ya se haya visto
        quiet = quiet || (Demo.noIdle && !forced)
        #endif
        guard isDoor, settled, !quiet, !hintSeen || forced else { return }
        try? await Task.sleep(for: DS.ParaTiB.doorHintDelay)
        guard !Task.isCancelled, onScreen, opening == 0, let grow = DS.Motion.grow(reduceMotion) else { return }
        hintSeen = true
        withAnimation(grow) { opening = 1 }
        try? await Task.sleep(for: DS.ParaTiB.doorHintHold)
        withAnimation(DS.Motion.fold(reduceMotion)) { opening = 0 }
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
                if c >= built { Color.clear.frame(width: columnWidth, height: DS.ParaTiB.coverWallHeight) } else {
                CoreDrift(key: posters, content: AnyView(strip(posters).environment(\.perfTag, c == 0 ? perfTag : nil)),
                          contentHeight: loop * 2, loop: loop,
                          speed: DS.ParaTiB.coverPace[c % DS.ParaTiB.coverPace.count], phase: Double(c) * DS.ParaTiB.coverPhaseStep,
                          rising: DS.ParaTiB.coverAlternates && c % 2 == 1,
                          enabled: !still, running: onScreen)
                    .frame(width: columnWidth, height: DS.ParaTiB.coverWallHeight)
                    .transition(.opacity)
                }
            }
        }
        .frame(width: CGFloat(columns) * columnWidth + DS.Space.s2 * CGFloat(columns - 1), height: DS.ParaTiB.coverWallHeight)
        // MT4-A: dónde empieza el muro (sin la inclinación); al enderezarse se recorre lo que le falta para que sus columnas
        // caigan justo donde van las del mosaico (si no, al cambiar brincaban de lado).
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { wallX = $0 }
        .offset(x: alignShift * reach)
        // MT4-A: en la puerta se endereza aquí mismo (un solo giro). Antes giraba aquí y se desgiraba en `CoverOpening` sobre
        // otro centro: derecho quedaba corrido de lado y el mosaico no podía tomar sus pósters (salían dos mosaicos).
        .rotationEffect(.degrees(DS.ParaTiB.coverTilt * (isDoor ? 1 - reach : 1)))
        // Al tocar la chapa el giro no seguía la animación (se enderezaba de golpe): se anima aquí con el mismo resorte.
        .animation(DS.Motion.grow(reduceMotion), value: opening)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Arma las columnas que faltan, una por paso, para que ninguna vuelta de la pantalla cargue con todas.
    private func buildColumns() async {
        while built < columns, !Task.isCancelled {
            withAnimation(DS.Motion.fade) { built += 1 }
            MosaicCover.builtColumns = max(MosaicCover.builtColumns, built)
            try? await Task.sleep(for: DS.ParaTiB.coverColumnStep)
        }
    }

    /// Cuántas columnas lleva el muro en esta ventana: ocho, o más en ventana ancha, pero nunca más de `coverMaxColumns`; lo
    /// que falta para cubrir la ventana lo ponen columnas más anchas (`widen`), con menos renglones. En la Mac eran 13 columnas
    /// de 26 pósters (~340 a la vez) y cambiar de Inicio a Explorar se trababa (Fernando, 17 nov 2026: «está lentísimo»).
    private var needed: Int {
        if let w = matchedWidth {   // MT4-A: columnas del ancho del mosaico, en número impar (así quedan centradas igual)
            let n = Int(((WindowMetrics.column.width + 2 * DS.ParaTiB.coverTiltSlack) / (w + DS.Space.s2)).rounded(.up))
            return n % 2 == 0 ? n + 1 : n
        }
        return DS.ParaTiB.coverColumns(forWidth: WindowMetrics.column.width)
    }
    /// MT4-A: en el iPhone parado, cada columna del muro mide lo que una del mosaico (así al enderezarse ya es el mosaico).
    private var matchedWidth: CGFloat? {
        guard isDoor, ThisDevice.platform == "iphone", horizontalSizeClass != .regular else { return nil }
        let width = WindowMetrics.column.width
        let count = CGFloat(Mosaic.columnCount(width: width, horizontalSizeClass: horizontalSizeClass))
        return (width - 2 * DS.Space.s2 - DS.Space.s2 * (count - 1)) / count
    }   // lo que le queda a la pantalla (sin el panel del control)
    private var columns: Int { matchedWidth != nil ? needed : min(needed, DS.ParaTiB.coverMaxColumns) }
    private var widen: CGFloat { matchedWidth.map { $0 / Self.columnWidth } ?? CGFloat(needed) / CGFloat(columns) }
    /// MT4-A: con columnas del ancho del mosaico, una vuelta cubre todo el alto del muro; si no, al abrirse se veía la misma
    /// tira repetida abajo (un segundo mosaico igual al de arriba; Fernando, 25 nov 2026).
    private var rows: Int {
        if matchedWidth != nil { return Int((DS.ParaTiB.coverWallHeight / (columnWidth / DS.Poster.aspect + DS.Space.s2)).rounded(.up)) + 1 }
        return Int((Double(DS.ParaTiB.coverRows) / Double(widen)).rounded(.up))
    }
    private var columnWidth: CGFloat { Self.columnWidth * widen }
    private var loop: CGFloat { (columnWidth / DS.Poster.aspect + DS.Space.s2) * CGFloat(rows) }

    private var still: Bool {
        #if DEBUG
        if Demo.noIdle { return true }
        #endif
        return reduceMotion || !ThisDevice.ambientMotion
    }

    /// El ancho de una columna del muro y lo que mide una vuelta de su tira (sus pósters una vez, con su separación).
    private static let columnWidth = (DS.ParaTiB.coverWall - DS.Space.s2 * CGFloat(DS.ParaTiB.coverColumns - 1)) / CGFloat(DS.ParaTiB.coverColumns)

    /// Los pósters de una columna: uno de cada `coverColumns` del orden del muro (así las vecinas no repiten).
    private func column(_ c: Int) -> [String] {
        guard !order.isEmpty else { return [] }
        return (0..<rows).map { order[(c + $0 * columns) % order.count] }
    }

    /// La tira de una columna, dos veces seguida: al bajar una vuelta entera queda igual que al principio y se repite sin corte.
    private func strip(_ posters: [String]) -> some View {
        VStack(spacing: DS.Space.s2) {
            ForEach(0..<(posters.count * 2), id: \.self) { i in
                PosterView(url: posters[i % posters.count], title: "", maxPoints: matchedWidth != nil ? DS.Image.mosaic : DS.Image.mosaic * widen, decorative: true)   // MT4-A: la misma imagen que el mosaico (sin volver a cargarla).frame(width: columnWidth)
            }
        }
        .frame(width: columnWidth, alignment: .top)
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
            // MT4-A: abierta, abajo ya no se apaga: los pósters de abajo son los del mosaico (antes se veían oscuros, un
            // «fondo falso», y se prendían de golpe al cambiar).
            .init(color: .black.opacity(Double(reach)), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }

    /// MT4-A: al abrirse, lo que queda arriba del mosaico (detrás de la barra) se apaga como en el mosaico, con su mismo
    /// desvanecido; si no, al cambiar desaparecían de golpe los pósters de arriba.
    private var mosaicEdge: some View {
        GeometryReader { g in
            let box = g.frame(in: .global)
            let top = max(0, MosaicHandoff.mosaicTop - box.minY)
            let fade = (WindowMetrics.column.height - MosaicHandoff.mosaicTop) * DesignTokens.Opacity.hairline * 0.7
            let hidden = Color.black.opacity(1 - Double(reach))
            // MT4-A: las columnas del muro que caen fuera del mosaico (en las orillas) se apagan al abrirse; si no, quedaban
            // detrás como un segundo mosaico (Fernando, 25 nov 2026).
            let screen = WindowMetrics.column.width
            let left = max(0, DS.Space.s2 - box.minX), right = max(0, box.maxX - (screen - DS.Space.s2))
            VStack(spacing: 0) {
                hidden.frame(height: top)
                LinearGradient(colors: [hidden, .black], startPoint: .top, endPoint: .bottom).frame(height: fade)
                Color.black
            }
            .mask {
                HStack(spacing: 0) {
                    hidden.frame(width: left)
                    Color.black
                    hidden.frame(width: right)
                }
            }
        }
    }

    /// Un velo bajo el título y la chapa, para que se lean sobre cualquier póster; sigue de largo bajo los círculos.
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

/// MO1: lo abierta que está la portada. Endereza el muro (le quita su inclinación) y lo crece desde el centro de lo que se ve;
/// al velo lo aclara. Suma lo que se jala la orilla de arriba (`RefreshPull.doorProgress`, siguiendo al dedo) a lo que abrió
/// un toque o el aviso; soltada pasada la puerta, se queda abierta mientras la orilla regresa (`entering`).
private struct CoverOpening: ViewModifier {
    let opening: CGFloat
    let door: Bool
    var unveil = false
    @Environment(RefreshPull.self) private var pull: RefreshPull?

    func body(content: Content) -> some View {
        let dragged = door ? ((pull?.entering ?? false) ? 1 : (pull?.doorProgress ?? 0)) : 0
        let p = max(opening, dragged)
        // El centro de lo que se ve de la portada (no el del arte, que sube mucho detrás de la barra): ahí gira y crece.
        let up = DS.ParaTiB.coverBleedUp, total = up + DS.ParaTiB.coverHeight + DS.ParaTiB.coverBleedDown
        let center = UnitPoint(x: 0.5, y: (up + DS.ParaTiB.coverHeight / 2) / total)
        if unveil {
            let left = 1 - DS.ParaTiB.doorUnveil * p   // lo que queda del velo
            content.opacity(left)
        } else {
            content
                .rotationEffect(.degrees(door ? 0 : -DS.ParaTiB.coverTilt * p), anchor: center)
                .scaleEffect(1 + DS.ParaTiB.doorGrow * p, anchor: center)
        }
    }
}

/// MO1: la chapa de la puerta del mosaico, en la orilla de abajo de la portada: la cuadrícula del mosaico (`DS.Symbol.mosaic`)
/// y cuántas piezas trae, en vidrio. Con letra grande parte en dos renglones; nunca se corta.
struct MosaicDoorBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: DS.Symbol.mosaic).accessibilityHidden(true)
            Text("Pasea por tus \(count)").lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText(value: Double(count)))   // mientras llegan, el número sube sin brincar
        }
        .font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.text)
        .padding(.horizontal, DS.Space.s4)
        .padding(.vertical, DS.Space.s2)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityHidden(true)   // la portada entera dice «Pasea por tus 96»
    }
}

/// Al tocar la portada se hunde tantito, en cuanto la tocas (`DS.Motion.press`).
private struct MosaicDoorPress: ButtonStyle {   // ds-exception: el hundido de la portada-puerta del mosaico (MO1)
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? DS.ParaTiB.doorPressed : 1)
            .animation(DS.Motion.press, value: configuration.isPressed)
    }
}

/// «Decide por mí»: la única puerta (DE2, Fernando, 13 nov 2026). Tres pósters en abanico (en Inicio, el dado), «Para cuando
/// no sabes qué ver» y las dos maneras de adentro, «Tres que caben · Una por una». Antes eran dos puertas: el dado de la barra
/// y la tarjeta «¿Qué vemos hoy?».
struct DecideDoor: View {
    /// Sin pósters (Inicio, o sin red): el dado.
    var posters: [String] = []
    /// Sin red y sin pósters: lo dice en vez de prometer opciones.
    var offline = false
    var id = "paraTi-decide"
    /// Más carteles para la tira de la derecha (solo en la Mac, `DS.ParaTiB.stripCount`).
    var more: [String] = []
    /// Su margen a los lados: 0 cuando va como tarjeta dentro de una fila o del panel del tablero (C6).
    var inset: CGFloat?
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Un renglón junto al abanico; con letra de accesibilidad el texto va debajo, a todo lo ancho, y puede partirse.
    private var oneLine: Int? { typeSize.isAccessibilitySize ? nil : 1 }

    var body: some View {
        // Con letra de accesibilidad, el abanico arriba y el texto debajo: al lado no cabía y ensanchaba toda la página de
        // Explorar (ChaosRegressionUITests, letra máxima).
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4))
                                                  : AnyLayout(HStackLayout(spacing: DS.Space.s4))
        Button(action: onOpen) {
            layout {
                if posters.isEmpty {
                    Image(systemName: DS.Symbol.decide).font(DS.TextRecipe.title.font).foregroundStyle(DS.accent)
                        .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                } else {
                    PosterFan(posters: posters, width: DS.ParaTiB.doorPoster, shift: DS.ParaTiB.doorShift)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    // En el SE, junto al abanico, se cortaba («…no sabes qu…»): se achica un poco en vez de cortarse.
                    Eyebrow(text: Text("Para cuando no sabes qué ver"), reason: true).minimumScaleFactor(DS.Size.statScale)
                    // El dado una sola vez: junto al nombre si hay pósters; si no, ya es el ícono de la izquierda.
                    // Más grande y con su color (Fernando, 17 nov 2026: «Decide por mí, hazlo más vistoso en ambos, un poquito
                    // más grande»): el nombre en tamaño de título y el dado en turquesa.
                    // DM-A (Fernando, 18 nov 2026: «ajuste fino, pero ponle más grande el icono del dado»): el nombre en un
                    // renglón; si no cabe (el SE), se achica tantito en vez de partirse en «Decide / por mí».
                    if posters.isEmpty { Text("Decide por mí").recipe(.title).lineLimit(oneLine).minimumScaleFactor(DS.ParaTiB.doorTitleScale) }
                    else {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: DS.Symbol.decide).foregroundStyle(DS.brandMoon).accessibilityHidden(true)
                            Text("Decide por mí").recipe(.title)
                        }
                        .font(DS.TextRecipe.title.font)
                        .lineLimit(oneLine).minimumScaleFactor(DS.ParaTiB.doorTitleScale)
                    }
                    (offline && posters.isEmpty ? Text("Sin conexión por ahora.") : Text("Tres que caben · Una por una"))
                        .recipe(.secondary, color: DS.textMuted)
                        .lineLimit(oneLine).minimumScaleFactor(DS.ParaTiB.doorTitleScale)
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                Spacer(minLength: 0)
                if !more.isEmpty, !typeSize.isAccessibilitySize {
                    DecideStrip(posters: more)
                    Image(systemName: "chevron.right").font(DS.TextRecipe.section.font).foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)   // DM-A: 16, el mismo aire que el margen de la pantalla (antes 20: le quitaba ancho al nombre)
            .background {
                // Un brillo del color de acento desde el abanico, como el color de «La temporada»: la puerta se ve como puerta.
                Color.clear.dsCard(.card)
                    .overlay(LinearGradient(colors: [DS.accent.opacity(DS.ParaTiB.doorGlow), .clear], startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, inset ?? DS.Space.gutter)
        .accessibilityIdentifier(id)
    }
}

/// La tira de carteles de la puerta de «Decide por mí» en la Mac: de lo que sale en la hoja, cada vez más claros hacia el
/// texto (los de la derecha, nítidos).
/// Muestra solo los que caben (los más nítidos, los de la derecha): en el iPad la tira de ocho aplastaba el título a una letra
/// por renglón (17 nov 2026). El texto de al lado lleva `layoutPriority(1)` y la tira toma lo que sobra.
/// Cuántos caben se cuenta con el ancho libre (cada cartel mide lo mismo), no se prueba: antes un `ViewThatFits` armaba hasta
/// ocho tiras de pósters cada vez que se dibujaba Explorar (revisión de velocidad de la Mac, 22 nov 2026).
struct DecideStrip: View {
    let posters: [String]
    @State private var width: CGFloat = 0

    var body: some View {
        let step = DS.ParaTiB.stripPoster + DS.Space.s2
        let fits = max(0, min(posters.count, Int(((width + DS.Space.s2) / step).rounded(.down))))
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: (DS.ParaTiB.stripPoster / DS.Poster.aspect).rounded(.up))   // el alto de un cartel: no estira la fila
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .trailing) { if fits > 0 { row(Array(posters.suffix(fits))) } }
            .accessibilityHidden(true)
    }

    private func row(_ shown: [String]) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, url in
                PosterView(url: url, title: "", decorative: true)
                    .frame(width: DS.ParaTiB.stripPoster)
                    .opacity(DS.ParaTiB.stripFadeFrom + (1 - DS.ParaTiB.stripFadeFrom) * Double(i + 1) / Double(shown.count))
            }
        }
        .fixedSize()
    }
}

/// Una columna del muro que baja sola con Core Animation: SwiftUI la pinta una vez y el servidor de render la desliza sin
/// despertar a la app. La tira mide dos vueltas (`contentHeight`) y baja una (`loop`) a `speed` puntos por segundo, sin que se
/// note el reinicio; `phase` (0 a 1) la desfasa, `running` en falso la pausa y `enabled` en falso la deja quieta. Solo se
/// vuelve a armar si cambian sus pósters (`key`): antes se rearmaba con cada cambio y entrar a Explorar se trababa.
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
        MosaicHandoff.live.append(WeakDrift(view))
        MosaicHandoff.live.removeAll { $0.view == nil }
        return view
    }

    func updateUIView(_ view: DriftView, context: Context) {
        if view.key != key { view.key = key; view.host.rootView = content }
        view.set(enabled: enabled, running: running)
    }
}

/// La vista de `CoreDrift`: aloja la tira de SwiftUI y anima su capa hacia abajo, sin fin.
final class DriftView: UIView {
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

    /// Al volver a la ventana la animación sigue ahí; si iOS la quitó, se vuelve a poner. El controlador del muro se cuelga del
    /// de la pantalla (como pide UIKit: tamaño de letra, apariencia y cambios de ventana; auditoría del 31 oct, B8) una sola vez
    /// y se descuelga al irse el muro (`deinit`): antes cada cambio de pestaña acomodaba otra vez ~200 pósters en el hilo
    /// principal (Fernando, 1 nov 2026: «Explorar cambia lento»).
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

/// MT4-A: dónde quedó cada columna del muro derecho, para que el mosaico arranque con esos mismos pósters en ese lugar.
struct MosaicHandoff {
    struct Column { let minX: CGFloat; let width: CGFloat; let firstTop: CGFloat; let posters: [String] }
    let columns: [Column]
    let pitch: CGFloat
    @MainActor static var live: [WeakDrift] = []
    /// Dónde empieza el mosaico en la pantalla (lo dice el mosaico al aparecer; antes, lo de un iPhone con isla).
    @MainActor static var mosaicTop: CGFloat = 124
    @MainActor private static var pending: MosaicHandoff?

    /// Mide cada columna en pantalla (con lo que lleva bajado su deriva) justo antes de cambiar al mosaico.
    @MainActor static func capture() {
        var out: [Column] = []
        var pitch: CGFloat = 0
        for weak in live {
            guard let view = weak.view, view.window != nil, !view.key.isEmpty else { continue }
            let rect = view.convert(view.bounds, to: nil)
            let layer = view.host.view.layer
            let drift = (layer.presentation() ?? layer).transform.m42
            out.append(Column(minX: rect.minX, width: rect.width, firstTop: rect.minY + drift, posters: view.key))
            pitch = rect.width / DS.Poster.aspect + DS.Space.s2
        }
        // Al tocar la chapa (el muro dentro de un botón) cada columna reporta el ancho de toda su tira, no el suyo: el ancho
        // sale de la distancia entre columnas, que sí es la buena (si no, el mosaico no la empataba y salía otro).
        let xs = out.map(\.minX).sorted()
        if xs.count > 1, let step = zip(xs, xs.dropFirst()).map({ $1 - $0 }).min(), step > DS.Space.s2 {
            let width = step - DS.Space.s2
            out = out.map { Column(minX: $0.minX, width: width, firstTop: $0.firstTop, posters: $0.posters) }
            pitch = width / DS.Poster.aspect + DS.Space.s2
        }
        pending = out.isEmpty ? nil : MosaicHandoff(columns: out, pitch: pitch)
    }

    /// Lo toma el mosaico al aparecer (una sola vez).
    @MainActor static func take() -> MosaicHandoff? { defer { pending = nil }; return pending }
}

final class WeakDrift { weak var view: DriftView?; init(_ v: DriftView) { view = v } }
