import SwiftUI
import OrbitalModels

/// Trajimos lo tuyo (K4-B · DP-A; Fernando, 18 nov 2026). Solo cuando Trakt trajo algo. Nada que elegir: lo tuyo aterriza
/// en la mesa (`WinMosaic`), los tres números y una sugerencia de ejemplo con su porqué («Porque viste <semilla>»), que se
/// ilumina en el mosaico al mismo tiempo que brota el destello. Una sola entrada para todo, con el mismo reloj.
struct OnboardingWin: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.titleName) private var titleName

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        GuidePage(title: nil, step: step, primary: Text("Continuar"), next: next, skipGuide: skip, back: back) {
            WinMosaic(tiles: model.winTiles, seedID: model.tonight?.seedID, start: start)
                .padding(.horizontal, -DS.Space.s6)
            TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
                let t = reduceMotion ? WinMosaic.end + 1 : ctx.date.timeIntervalSince(start)
                copy(model, t)
            }
        }
        .onAppear { start = Date() }
        .task { if model.brought == nil { await model.traktLinked() }; await model.loadWin() }
    }

    @ViewBuilder private func copy(_ model: OnboardingModel, _ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Trajimos lo tuyo").recipe(.display, color: DS.text).enter(M.item(t, 0.06, 14))
                Text("Lo que viste y tu lista ya están en Orbital.")
                    .font(DS.Welcome.lead).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
                    .enter(M.item(t, 0.14, 10))
            }
            if let brought = model.brought {
                HStack(spacing: 0) {
                    count("checkmark", brought.watched, Text("vistas"))
                    Divider().frame(height: DS.Guide.countDivider)
                    count("bookmark", brought.listed, Text("en Mi lista"))
                    Divider().frame(height: DS.Guide.countDivider)
                    count("tv", brought.shows, Text("series que sigues"))
                }
                .enter(M.item(t, 0.22, 10))
            }
            if let tonight = model.tonight {
                let pick = titleName(tonight.pick.title, id: tonight.pick.imdb, kind: tonight.pick.kind)
                let seed = titleName(tonight.seed, id: tonight.seedID, kind: tonight.seedKind)
                HStack(spacing: DS.Space.s4) {
                    PosterView(url: tonight.pick.poster, title: pick, aspect: nil, maxPoints: DS.Image.mosaic)
                        .frame(width: DS.Guide.whyPoster.width, height: DS.Guide.whyPoster.height)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("Para esta noche").recipe(.caption, color: DS.textMuted)
                        Text(verbatim: pick).recipe(.cardTitle, color: DS.text).lineLimit(2)
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s1) {
                            Image(systemName: "sparkles").scaleEffect(max(0, M.spring(t - WinMosaic.highlight - 0.04, 0.55, 0.45)))
                            Text("Porque viste \(seed)").lineLimit(2)
                        }
                        .font(DS.TextRecipe.caption.font).foregroundStyle(DS.brandMoon)
                    }
                    Spacer(minLength: 0)
                }
                .padding(DS.Space.s3)
                .dsCard()
                .enter(M.item(t, 0.30, 10))
                Text("Cada sugerencia te dice de dónde sale.").recipe(.caption, color: DS.textMuted)
                    .enter(M.item(t, 0.36, 8))
            }
        }
    }

    private func count(_ symbol: String, _ value: Int, _ label: Text) -> some View {
        VStack(spacing: DS.Space.s1) {
            Label {
                Text(value, format: .number).monospacedDigit()
            } icon: {
                Image(systemName: symbol).foregroundStyle(DS.brandMoon)
            }
            .font(DS.styled(.title2).weight(.semibold)).foregroundStyle(DS.text)
            label.recipe(.caption, color: DS.textMuted).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    /// La entrada estándar de la guía (aparece en 0.42 s y sube con un resorte sin rebote), dibujada en cada cuadro.
    func enter(_ state: (opacity: Double, rise: CGFloat)) -> some View { opacity(state.opacity).offset(y: state.rise) }
}
