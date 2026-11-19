import SwiftUI
import OrbitalCore
import OrbitalModels

/// ¿Qué plataformas tienes? (A1-B · A6; Fernando, 18 nov 2026; prototipo `screens/platforms.js`). Solo en la de la tienda,
/// que no reproduce. Arriba, una ficha de ejemplo dice lo que dirá «Dónde verla»: con una tuya, «Incluida en tu plan». Al
/// marcar una, su logo brota en el hueco de la ficha y el renglón cambia (el viejo sube y se va, el nuevo llega de abajo).
/// El botón dice «Ahora no» sin nada y «Continuar» con algo, sin moverse. Se guarda solo en Orbital (`Taste.platforms`).
struct OnboardingPlatforms: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var start = Date()
    /// La última que marcaste: la que enseña la ficha.
    @State private var last: String?
    @State private var picked = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.titleName) private var titleName

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        let any = !model.chosenPlatforms.isEmpty
        GuidePage(title: nil, step: step, primary: any ? Text("Continuar") : Text("Ahora no"), next: next, skipGuide: skip, back: back) {
            TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
                let t = reduceMotion ? Self.end + 1 : ctx.date.timeIntervalSince(start)
                content(model, t)
            }
        }
        .dsFeedback(.selection, trigger: picked)
        .onAppear { start = Date() }
        .task { await model.loadPlatforms(); await model.loadCandidates() }
    }

    static let end = 1.1

    @ViewBuilder private func content(_ model: OnboardingModel, _ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let shown = model.platforms.first { $0.brand == last && model.chosenPlatforms.contains($0.brand) }
            ?? model.platforms.last { model.chosenPlatforms.contains($0.brand) }
        let prev = M.item(t, 0, 12)
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            preview(model.candidates.first, shown: shown, dash: max(0, M.spring(t - 0.62, 0.55, 0.45)))
                .scaleEffect(0.96 + 0.04 * M.spring(t, 0.55, 0.45), anchor: .bottom)
                .opacity(prev.opacity).offset(y: prev.rise)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                let title = M.item(t, 0.08, 14), lead = M.item(t, 0.16, 10)
                Text("¿Qué plataformas tienes?").recipe(.display, color: DS.text).fixedSize(horizontal: false, vertical: true)
                    .opacity(title.opacity).offset(y: title.rise)
                Text("Así te decimos qué puedes ver sin pagar más, y lo nuevo en lo tuyo.")
                    .font(DS.Welcome.lead).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
                    .opacity(lead.opacity).offset(y: lead.rise)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s2), count: 2), spacing: DS.Space.s2) {
                ForEach(Array(model.platforms.enumerated()), id: \.element.brand) { i, platform in
                    let count = max(model.platforms.count - 1, 1)
                    let enter = M.item(t, 0.22 + 0.22 * sqrt(Double(i) / Double(count)), 10)
                    tile(platform.name, logo: platform.logo, on: model.chosenPlatforms.contains(platform.brand)) {
                        let wasOn = model.chosenPlatforms.contains(platform.brand)
                        withAnimation(DS.Motion.spring(reduceMotion)) {
                            model.togglePlatform(platform.brand)
                            last = wasOn ? nil : platform.brand
                        }
                        picked += 1
                    }
                    .opacity(enter.opacity).offset(y: enter.rise)
                }
            }
            let fine = M.item(t, 0.40, 8)
            Text("Solo se guarda en Orbital. Lo cambias en Ajustes.").recipe(.caption, color: DS.textMuted)
                .opacity(fine.opacity).offset(y: fine.rise)
        }
    }

    /// La ficha de ejemplo: un póster, «Dónde verla» y lo que diría con tus plataformas.
    private func preview(_ item: Suggestion?, shown: (brand: String, name: String, logo: String?)?, dash: Double) -> some View {
        let name = item.map { titleName($0.title, id: $0.imdb, kind: $0.kind) }
        return HStack(spacing: DS.Space.s4) {
            PosterView(url: item?.poster, title: name ?? "", aspect: nil, maxPoints: DS.Image.mosaic)
                .frame(width: DS.Guide.platformPoster.width, height: DS.Guide.platformPoster.height)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                if let name { Text(verbatim: name).recipe(.cardTitle, color: DS.text).lineLimit(1) }
                Text("Dónde verla").recipe(.caption, color: DS.textMuted)
                HStack(spacing: DS.Space.s3) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .stroke(DS.textMuted, style: StrokeStyle(lineWidth: DS.Stroke.hairline, dash: DS.Guide.slotDash))
                            .scaleEffect(dash).opacity(shown == nil ? 1 : 0)
                        if let shown {
                            Group {
                                if shown.logo != nil { DSPlatformLogo(url: shown.logo) } else { Image(systemName: "checkmark") }
                            }
                            .id(shown.brand)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                        } else {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(DS.textMuted)
                        }
                    }
                    .frame(width: DS.Guide.slot, height: DS.Guide.slot)
                    VStack(alignment: .leading, spacing: 0) {
                        if let shown {
                            let platform = shown.name
                            Text("Incluida en tu plan").recipe(.label, color: DS.brandMoon)
                            Text("En \(platform)").recipe(.caption, color: DS.textMuted)
                        } else {
                            Text("¿Ya la pagas?").recipe(.label, color: DS.text)
                            Text("Elige tus plataformas").recipe(.caption, color: DS.textMuted)
                        }
                    }
                    .lineLimit(1)
                    .id(shown?.brand ?? "none")
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
        .dsCard()
    }

    /// Una plataforma: su logo y su nombre; marcada, su palomita brota.
    private func tile(_ name: String, logo: String?, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: DS.Space.s2) {
                Group {
                    if logo != nil { DSPlatformLogo(url: logo) } else { Image(systemName: "tv") }
                }
                .frame(width: DS.Guide.slot, height: DS.Guide.slot)
                Text(verbatim: name).recipe(.label, color: DS.text).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette).foregroundStyle(on ? DS.onPrimary : DS.textMuted, DS.brandMoon)
                    .font(DS.styled(.body))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, DS.Space.s3)
            .frame(minHeight: DS.Guide.platformTile)
            .dsCard(fill: on ? DS.fresh.opacity(DS.Opacity.selectedFill) : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
