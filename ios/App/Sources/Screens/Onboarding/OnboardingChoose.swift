import SwiftUI
import OrbitalCore
import OrbitalModels

/// 2 · Lo que te gusta (H1): pósters de lo popular de ahora y tus plataformas, en una pantalla. Son gustos, no vistos: arman
/// «Porque viste» y «Nuevo en tus plataformas» mientras Trakt no sabe nada de ti. Se puede seguir sin elegir.
struct OnboardingLikes: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var picked = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        let count = model.liked.count
        GuidePage(title: Text("¿Qué te gusta?"), message: Text("Elige 3 o más y armo tu Inicio con eso."), step: step,
                  next: next, skipGuide: skip, back: back) {
            VStack(alignment: .leading, spacing: DS.Space.s5) {
                if model.candidates.isEmpty {
                    DSLoadingState()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3), count: DS.Likes.columns), spacing: DS.Space.s3) {
                        ForEach(model.candidates) { item in likeTile(item, on: model.liked.contains(item.imdb)) { model.toggleLike(item); picked += 1 } }
                    }
                    (count >= OnboardingModel.minimumLikes ? Text("Listo: \(String(count)) elegidos.")
                                                            : Text("Llevas \(String(count)) de \(String(OnboardingModel.minimumLikes)).")).recipe(.footnote, color: DS.textMuted)
                        .contentTransition(.numericText())
                }
                if !model.platforms.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        Text("¿Dónde ves hoy?").recipe(.cardTitle, color: DS.text)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.s3), count: 2), spacing: DS.Space.s3) {
                            ForEach(model.platforms, id: \.brand) { platform in
                                platformTile(platform.name, on: model.chosenPlatforms.contains(platform.brand)) { model.togglePlatform(platform.brand); picked += 1 }
                            }
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: picked)
        .task { await model.loadCandidates() }
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
                .scaleEffect(on ? DS.Explainer.restScale : 1)
                .animation(DS.Motion.pop(reduceMotion), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: item.title))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func platformTile(_ name: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: DS.Space.s2) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? DS.brandMoon : DS.textMuted)
                Text(verbatim: name).recipe(.body, color: DS.text)
                Spacer(minLength: 0)
            }
            .padding(DS.Space.s3)
            .frame(maxWidth: .infinity)
            .dsCard()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 3 · ¿Qué ya tienes? (C1): Real-Debrid, Trakt y, donde hay TV, Orbital en la TV. Lo que contestas arma el resto: «Ya lo
/// tengo» va directo a conectar, «¿Qué es?» lo explica y «Después» se lo salta. Lo ya conectado dice «Conectado».
struct OnboardingHave: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        GuidePage(title: Text("¿Qué ya tienes?"), message: Text("Así te explico solo lo que te falta."), step: step,
                  next: next, skipGuide: skip, back: back) {
            VStack(spacing: DS.Space.s3) {
                ForEach(model.pieces, id: \.self) { piece in card(piece, model) }
                Text("Todo se puede conectar después en Ajustes.").recipe(.footnote, color: DS.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func card(_ piece: OnboardingModel.Piece, _ model: OnboardingModel) -> some View {
        let words = Self.words(piece)
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s3) {
                DSIconTile(symbol: words.symbol, tint: words.tint)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text(words.title).recipe(.cardTitle, color: DS.text)
                    Text(words.detail).recipe(.secondary, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if model.isConnected(piece) {
                Label("Conectado", systemImage: "checkmark.circle.fill").recipe(.label, color: DS.success)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.s2) { answers(piece, model) }
                    VStack(spacing: DS.Space.s2) { answers(piece, model) }
                }
            }
        }
        .padding(DS.Space.s4)
        .dsCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func answers(_ piece: OnboardingModel.Piece, _ model: OnboardingModel) -> some View {
        let options: [(OnboardingModel.Answer, LocalizedStringKey)] = piece == .tv
            ? [(.has, "La tengo"), (.later, "No la tengo")]
            : [(.has, "Ya lo tengo"), (.explain, "¿Qué es?"), (.later, "Después")]
        ForEach(options, id: \.0) { value, title in
            let chosen = model.answers[piece] == value
            Button { model.answer(piece, value) } label: { Text(title).frame(maxWidth: .infinity) }
                .modifier(AnswerStyle(chosen: chosen))
                .accessibilityAddTraits(chosen ? .isSelected : [])
                .accessibilityIdentifier("have-\(piece.rawValue)-\(value.rawValue)")
        }
    }

    static func words(_ piece: OnboardingModel.Piece) -> (symbol: String, tint: Color, title: LocalizedStringKey, detail: LocalizedStringKey) {
        switch piece {
        case .debrid: ("cloud.fill", DS.ListTint.flame, "Real-Debrid", "Para ver aquí mismo, al instante.")
        case .trakt: ("checkmark.seal.fill", DS.ListTint.chart, "Trakt", "Tu avance, en todos tus aparatos. Gratis.")
        case .tv: ("tv.fill", DS.ListTint.series, "Orbital en la TV", "Tu iPhone como su control.")
        }
    }
}

/// La respuesta elegida va llena; las otras, de vidrio.
private struct AnswerStyle: ViewModifier {
    let chosen: Bool
    func body(content: Content) -> some View {
        if chosen { content.dsPrimaryButton() } else { content.dsGlassButton() }
    }
}
