import SwiftUI
import OrbitalModels

/// K4-B · «Trajimos lo tuyo» (Fernando, 18 nov 2026; prototipo `screens/win.js`): lo tuyo cae del aire y aterriza sobre una
/// mesa inclinada, en una onda que sale de la semilla del porqué (al centro). Cada póster cae desde cerca (130 %) con un
/// resorte que se pasa un pelo y su sombra se encoge al tocar; lo de tu lista lleva su marcador, que brota 0.2 s después. A
/// 0.95 s la semilla se levanta con su anillo turquesa y los demás bajan un poco la luz: de ahí sale la sugerencia de abajo.
/// Con «Reducir movimiento», quieto en su final.
struct WinMosaic: View {
    let tiles: [OnboardingModel.WinTile]
    /// El título del que sale el porqué (se ilumina); sin él, nada se ilumina.
    let seedID: String?
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.titleName) private var titleName

    static let cols = 6, rows = 3, seed = 8
    static let tile = CGSize(width: 54, height: 81), gap: CGFloat = 9
    static let end = 1.7, highlight = 0.95
    static let height: CGFloat = 284
    /// El marcador de tu lista: un círculo de 20 pt con el fondo casi opaco, a 4 pt de la orilla.
    static let badge: CGFloat = 20, badgeBacking = 0.84, badgeInset: CGFloat = 4
    /// La sombra crece mientras el póster va en el aire; el anillo de la semilla brilla un poco.
    static let shade = 0.32, ringGlow = 0.35

    /// Los 18 lugares: la semilla en el centro (8) y lo demás alrededor; si hay menos de 18, se repiten.
    private var placed: [OnboardingModel.WinTile?] {
        guard !tiles.isEmpty else { return Array(repeating: nil, count: Self.cols * Self.rows) }
        var rest = tiles
        let seedTile = seedID.flatMap { id in rest.firstIndex { $0.id == id }.map { rest.remove(at: $0) } }
        if rest.isEmpty, let seedTile { rest = [seedTile] }
        var out: [OnboardingModel.WinTile?] = (0..<(Self.cols * Self.rows)).map { rest[$0 % rest.count] }
        if let seedTile { out[Self.seed] = seedTile }
        return out
    }

    /// Una onda que sale del centro: cada espera más corta (raíz cuadrada), todo entre 0.10 y 0.50 s.
    private static let delays: [Double] = {
        let n = cols * rows
        func d(_ i: Int) -> Double { hypot(Double(i % cols - seed % cols), Double(i / cols - seed / cols) * 1.3) + Double(i) * 1e-3 }
        let order = (0..<n).sorted { d($0) < d($1) }
        var out = Array(repeating: 0.0, count: n)
        for (rank, i) in order.enumerated() { out[i] = 0.10 + 0.40 * sqrt(Double(rank) / Double(n - 1)) }
        return out
    }()
    private static let tilts: [Double] = (0..<(cols * rows)).map { Double((($0 * 37) % 9) - 4) }

    var body: some View {
        TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? Self.end + 1 : ctx.date.timeIntervalSince(start)
            wall(t)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .mask(RadialGradient(stops: [.init(color: .black, location: 0.58), .init(color: .clear, location: 1)],
                             center: UnitPoint(x: 0.5, y: 0.44), startRadius: 0, endRadius: Self.height * 0.92))
        .accessibilityHidden(true)
    }

    private func wall(_ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let lit = seedID != nil && placed[Self.seed]?.id == seedID
        let hl = max(0, M.spring(t - Self.highlight, 0.55, 0.45)), dim = M.easeOut((t - Self.highlight) / 0.4)
        let w = CGFloat(Self.cols) * (Self.tile.width + Self.gap) - Self.gap, h = CGFloat(Self.rows) * (Self.tile.height + Self.gap) - Self.gap
        return ZStack(alignment: .topLeading) {
            ForEach(Array(placed.enumerated()), id: \.offset) { i, item in
                let d = Self.delays[i], p = M.spring(t - d, 0.5, 0.3), pc = min(max(p, 0), 1), isSeed = lit && i == Self.seed
                let scale = (1.3 + (1 - 1.3) * p) * (isSeed ? 1 + 0.06 * hl : 1)
                let lift = 1 - pc
                tile(item, ring: isSeed ? M.easeOut((t - Self.highlight) / 0.3) : 0,
                     badge: max(0, M.spring(t - d - 0.2, 0.55, 0.45)), lift: lift)
                    .scaleEffect(scale)
                    .rotationEffect(.degrees(Self.tilts[i] * (1 - pc)))
                    .offset(y: -24 * (1 - p))
                    .opacity(M.easeOut((t - d) / 0.16) * (isSeed ? 1 : 1 - 0.2 * dim))
                    .zIndex(isSeed && t >= Self.highlight ? 3 : pc < 1 ? 2 : 1)
                    .offset(x: CGFloat(i % Self.cols) * (Self.tile.width + Self.gap), y: CGFloat(i / Self.cols) * (Self.tile.height + Self.gap))
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .rotationEffect(.degrees(-7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ item: OnboardingModel.WinTile?, ring: Double, badge: Double, lift: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
        return ZStack(alignment: .bottomTrailing) {
            if let item {
                PosterView(url: item.poster, title: titleName(item.title, id: item.id, kind: item.kind), aspect: nil, maxPoints: DS.Image.mosaic)
                    .frame(width: Self.tile.width, height: Self.tile.height).clipShape(shape)
            } else {
                shape.fill(DS.surfaceRaised).frame(width: Self.tile.width, height: Self.tile.height)
            }
            if item?.listed == true {
                Image(systemName: "bookmark.fill").font(DS.styled(.caption2).weight(.bold)).foregroundStyle(DS.brandMoon)
                    .frame(width: Self.badge, height: Self.badge).background(DS.bg.opacity(Self.badgeBacking), in: Circle())
                    .padding(Self.badgeInset).scaleEffect(badge)
            }
        }
        .shadow(color: DS.scrimStrong.opacity(Self.shade + lift * 0.24), radius: 4 + lift * 13, y: 3 + lift * 18)
        .overlay(shape.inset(by: -4).stroke(DS.brandMoon, lineWidth: 2).shadow(color: DS.brandMoon.opacity(Self.ringGlow), radius: 9).opacity(ring))
    }
}
