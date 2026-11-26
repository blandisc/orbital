import SwiftUI
import OrbitalCore
import OrbitalModels

/// ¿Qué plataformas tienes? (A1-B · A6; Fernando, 18 nov 2026; prototipo `screens/platforms.js`). Solo en la de la tienda,
/// que no reproduce. Arriba, una ficha de ejemplo dice lo que dirá «Dónde verla»: con una tuya, «Incluida en tu plan». Al
/// marcar una, su logo salta en arco de la casilla al hueco de la ficha (resorte 0.5 · 0.18) y, al llegar, el renglón cambia
/// (el viejo se va, el nuevo llega de abajo; Fernando, 18 nov 2026: «que vuele en el arco como en el prototipo»).
/// El botón dice «Ahora no» sin nada y «Continuar» con algo, sin moverse. Se guarda solo en Orbital (`Taste.platforms`).
struct OnboardingPlatforms: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var start = Date()
    /// La que enseña la ficha: la última que marcaste, en cuanto su logo aterriza.
    @State private var last: String?
    /// El logo que va volando de su casilla al hueco de la ficha.
    @State private var flight: Flight?
    @State private var logoFrames: [String: CGRect] = [:]
    @State private var slotFrame: CGRect = .zero

    struct Flight: Equatable { let brand: String; let logo: String?; let from: CGRect; let to: CGRect; let start: Date }
    static let land = 0.5
    @State private var picked = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.titleName) private var titleName

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        let any = !model.chosenPlatforms.isEmpty
        GuidePage(title: nil, step: step, primary: any ? guide.model.ahead(after: .platforms) : Text("Ahora no"), next: next, skipGuide: skip, back: back) {
            TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
                let t = reduceMotion ? Self.end + 1 : ctx.date.timeIntervalSince(start)
                content(model, t)
                    .overlay(alignment: .topLeading) { if let flight { flyer(flight, ctx.date) } }
            }
            .coordinateSpace(.named(Self.space))
        }
        .dsFeedback(.selection, trigger: picked)
        .onAppear { start = Date() }
        .task { await model.loadPlatforms(); await model.loadCandidates() }
    }

    static let end = 1.1

    @ViewBuilder private func content(_ model: OnboardingModel, _ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self
        let shown = model.platforms.first { $0.brand == last && model.chosenPlatforms.contains($0.brand) }
        let prev = M.item(t, 0, 12)
        VStack(alignment: .leading, spacing: DS.Space.s6) {
            preview(model.candidates.first, shown: shown, dash: max(0, M.spring(t - 0.62, 0.55, 0.45)))
                .scaleEffect(0.96 + 0.04 * M.spring(t, 0.55, 0.45), anchor: .bottom)   // ds-exception: coreografía de la bienvenida
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
                    tile(platform.brand, platform.name, logo: platform.logo, on: model.chosenPlatforms.contains(platform.brand)) {
                        toggle(model, platform)
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
                HStack(spacing: DS.Space.s2) {
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
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { slotFrame = $0 }
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
    private func tile(_ brand: String, _ name: String, logo: String?, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: DS.Space.s2) {
                Group {
                    if logo != nil { DSPlatformLogo(url: logo) } else { Image(systemName: "tv") }
                }
                .frame(width: DS.Guide.slot, height: DS.Guide.slot)
                .opacity(flight?.brand == brand ? 0 : 1)   // mientras vuela, la casilla no lo repite
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { logoFrames[brand] = $0 }
                Text(verbatim: name).recipe(.label, color: DS.text).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.palette).foregroundStyle(on ? DS.onPrimary : DS.textMuted, DS.brandMoon)
                    .font(DS.styled(.body))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, DS.Space.s2)
            .frame(minHeight: DS.Guide.platformTile)
            .dsCard(fill: on ? DS.fresh.opacity(DS.Opacity.selectedFill) : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private nonisolated static let space = "platforms"

    /// Marcar: la palomita brota y el logo sale volando; el renglón de la ficha cambia cuando aterriza. Desmarcar: la ficha
    /// enseña otra de las tuyas (o vuelve a «¿Ya la pagas?»).
    private func toggle(_ model: OnboardingModel, _ platform: (brand: String, name: String, logo: String?)) {
        let on = !model.chosenPlatforms.contains(platform.brand)
        picked += 1
        withAnimation(DS.Motion.spring(reduceMotion)) { model.togglePlatform(platform.brand) }
        guard on else {
            if last == platform.brand {
                withAnimation(DS.Motion.spring(reduceMotion)) { last = model.platforms.last { model.chosenPlatforms.contains($0.brand) }?.brand }
            }
            return
        }
        guard !reduceMotion, let from = logoFrames[platform.brand], slotFrame != .zero else {
            withAnimation(DS.Motion.spring(reduceMotion)) { last = platform.brand }
            return
        }
        let trip = Flight(brand: platform.brand, logo: platform.logo, from: from, to: slotFrame, start: Date())
        flight = trip
        Task {
            try? await Task.sleep(for: .seconds(Self.land))
            guard flight == trip else { return }
            flight = nil
            if model.chosenPlatforms.contains(trip.brand) { withAnimation(DS.Motion.spring(reduceMotion)) { last = trip.brand } }
        }
    }

    /// El logo en el aire: avanza con un resorte que se pasa un pelo, sube en arco (46 pt en lo alto), se ladea y crece un poco a
    /// media altura (como `fly` en `screens/platforms.js`).
    private func flyer(_ f: Flight, _ now: Date) -> some View {
        let M = GuideTraktScene.Motion.self
        let p = M.spring(now.timeIntervalSince(f.start), 0.5, 0.18), c = min(max(p, 0), 1), arc = sin(.pi * c)
        let x = f.from.midX + (f.to.midX - f.from.midX) * p, y = f.from.midY + (f.to.midY - f.from.midY) * p - 46 * arc
        return Group {
            if f.logo != nil { DSPlatformLogo(url: f.logo) } else { Image(systemName: "tv") }
        }
        .frame(width: DS.Guide.slot, height: DS.Guide.slot)
        .shadow(DS.Elevation.high)
        .rotationEffect(.degrees(-10 * arc))
        .scaleEffect(1 + 0.14 * arc)   // ds-exception: coreografía de la bienvenida
        .position(x: x, y: y)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
