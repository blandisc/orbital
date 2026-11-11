import SwiftUI
import OrbitalCore
import OrbitalModels

/// 2 · Lo que te gusta (H1; G2 de la revisión del director): los pósters llegan cayendo, como si siguieran a los de la
/// bienvenida; al tocar uno se voltea y una copia entra en tu órbita, arriba; con tres, el anillo se cierra y llega la luna.
/// Tus plataformas son sus logos, en gris hasta que los enciendes. Son gustos, no vistos. Se puede seguir sin elegir.
struct OnboardingLikes: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var picked = 0
    @State private var arrived = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        let chosen = model.liked.compactMap { id in model.candidates.first { $0.imdb == id } }
        GuidePage(title: Text("¿Qué te gusta?"), message: chosen.count >= OnboardingModel.minimumLikes ? nil : Text("Elige 3 o más y armo tu Inicio con eso."),
                  step: step, next: next, skipGuide: skip, back: back) {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                GuideOrbit(picked: chosen, needed: OnboardingModel.minimumLikes)
                if model.candidates.isEmpty {
                    DSLoadingState()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3), count: DS.Likes.columns), spacing: DS.Space.s3) {
                        ForEach(Array(model.candidates.enumerated()), id: \.element.imdb) { i, item in
                            likeTile(item, on: model.liked.contains(item.imdb)) { model.toggleLike(item); picked += 1 }
                                .offset(y: arrived || reduceMotion ? 0 : -DS.Welcome.fallFrom)
                                .opacity(arrived || reduceMotion ? 1 : 0)
                                .animation(DS.Motion.spring(reduceMotion)?.delay(Double(i) * DS.GuideScene.dropStep), value: arrived)
                        }
                    }
                }
                if !model.platforms.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        Text("¿Dónde ves hoy?").recipe(.cardTitle, color: DS.text)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3), count: 3), spacing: DS.Space.s3) {
                            ForEach(model.platforms, id: \.brand) { platform in
                                platformTile(platform.name, logo: platform.logo, on: model.chosenPlatforms.contains(platform.brand)) {
                                    model.togglePlatform(platform.brand); picked += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        .dsFeedback(.selection, trigger: picked)
        .dsFeedback(.success, trigger: chosen.count >= OnboardingModel.minimumLikes)
        .task { await model.loadCandidates(); arrived = true }
        .task { await model.loadPlatforms() }
    }

    private func likeTile(_ item: Suggestion, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            PosterView(url: item.poster, title: item.title)
                .overlay(alignment: .topTrailing) {
                    if on {
                        Image(systemName: "checkmark.circle.fill").font(DS.TextRecipe.section.font)
                            .symbolRenderingMode(.palette).foregroundStyle(DS.onPrimary, DS.brandMoon)
                            .padding(DS.Space.s2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay { if on { RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).strokeBorder(DS.text, lineWidth: DS.Stroke.selected) } }
                .rotation3DEffect(.degrees(on && !reduceMotion ? DS.GuideScene.flip : 0), axis: (x: 0, y: 1, z: 0))
                .rotation3DEffect(.degrees(on && !reduceMotion ? DS.GuideScene.flip : 0), axis: (x: 0, y: 1, z: 0))   // la media vuelta de regreso: queda al derecho
                .scaleEffect(on ? DS.Explainer.restScale : 1)
                .animation(DS.Motion.pop(reduceMotion), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Una plataforma: su logo, en gris hasta que la enciendes (o su nombre si el logo no carga).
    private func platformTile(_ name: String, logo: String?, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            Group {
                if logo != nil { DSPlatformLogo(url: logo) } else { Text(verbatim: name).recipe(.label, color: DS.text) }
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Space.s3)
            .dsCard(fill: on ? DS.fresh.opacity(DS.Opacity.selectedFill) : nil)
            .saturation(on ? 1 : 0)
            .opacity(on ? 1 : DS.Opacity.dimmed)
            .overlay(alignment: .bottom) { if on { Circle().fill(DS.brandMoon).frame(width: DS.Space.s2, height: DS.Space.s2).offset(y: DS.Space.s1).transition(.scale) } }
            .animation(DS.Motion.pop(reduceMotion), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 3 · ¿Qué ya tienes? (C1; G3 de la revisión): tres objetos de línea en lugar de tarjetas y botones. Un toque enciende lo
/// que tienes (la nube se llena, el hilo entre aparatos se dibuja, la TV prende); lo que no tienes, no se marca (Q1). Mantener
/// presionado dice qué es. Lo ya conectado sale encendido.
struct OnboardingHave: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var explaining: OnboardingModel.Piece?
    @State private var taps = 0

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        GuidePage(title: Text("¿Qué ya tienes?"), message: Text("Toca lo que ya tienes. Mantén presionado para saber qué es."), step: step,
                  primary: Text("Seguir"), next: next, skipGuide: skip, back: back) {
            VStack(spacing: DS.Space.s5) {
                HStack(alignment: .top, spacing: DS.Space.s3) {
                    ForEach(model.pieces, id: \.self) { piece in object(piece, model) }
                }
                if let explaining {
                    let words = Self.words(explaining)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text(words.title).recipe(.cardTitle, color: DS.text)
                        Text(words.detail).recipe(.secondary, color: DS.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.s4).dsCard()
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Text("Lo que no tengas, te lo explico en el siguiente paso o lo conectas después en Ajustes.").recipe(.footnote, color: DS.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .dsFeedback(.selection, trigger: taps)
    }

    @ViewBuilder private func object(_ piece: OnboardingModel.Piece, _ model: OnboardingModel) -> some View {
        let words = Self.words(piece)
        let on = model.isConnected(piece) || model.answers[piece] == .has
        Button {
            guard !model.isConnected(piece) else { return }
            model.toggle(piece); taps += 1
        } label: {
            VStack(spacing: DS.Space.s2) {
                GuideHaveObject(kind: piece == .debrid ? .cloud : piece == .trakt ? .thread : .tv, on: on)
                Text(words.title).recipe(.label, color: on ? DS.text : DS.textMuted).multilineTextAlignment(.center)
                if model.isConnected(piece) { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.s4)
            .dsCard(fill: on ? DS.fresh.opacity(DS.Opacity.selectedFill) : nil)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(LongPressGesture().onEnded { _ in withAnimation(DS.Motion.fade) { explaining = explaining == piece ? nil : piece } })
        .accessibilityLabel(Text(words.title))
        .accessibilityValue(on ? Text("Lo tengo") : Text("No lo tengo"))
        .accessibilityHint(Text(words.detail))
        .accessibilityIdentifier("have-\(piece.rawValue)")
    }

    static func words(_ piece: OnboardingModel.Piece) -> (symbol: String, tint: Color, title: LocalizedStringKey, detail: LocalizedStringKey) {
        switch piece {
        case .debrid: ("cloud.fill", DS.ListTint.flame, "Real-Debrid", "Para ver aquí mismo, al instante.")
        case .trakt: ("checkmark.seal.fill", DS.ListTint.chart, "Trakt", "Tu avance, en todos tus aparatos. Gratis.")
        case .tv: ("tv.fill", DS.ListTint.series, "Orbital en la TV", "Tu iPhone como su control.")
        }
    }
}
