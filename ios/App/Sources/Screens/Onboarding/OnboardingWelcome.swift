import SwiftUI
import UIKit
import OrbitalCore
import OrbitalModels

/// 1 · Bienvenida (A1): el planeta atrapa siete pósters y la luna llega con un toque en la mano. Si nadie la toca en 12 s,
/// se enseña sola (B1, la vitrina): dos vueltas y se detiene en «Empezar». No sale con VoiceOver ni con «Reducir movimiento».
struct OnboardingWelcome: View {
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var appeared = false
    @State private var showsButton = false
    @State private var moon = 0
    @State private var attract = false
    @State private var touched = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guide: OnboardingModel, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        VStack(spacing: DS.Space.s5) {
            HStack { Spacer(); GuideSkip(action: skip) }
            Spacer(minLength: DS.Space.s4)
            // En un iPhone chico (SE) la escena se encoge para que el texto y «Empezar» quepan.
            GeometryReader { geo in
                let scale = min(1, geo.size.height / DS.Welcome.sceneHeight)
                ZStack {
                    OrbitCatch(posters: model.candidates) { moon += 1 }
                        .opacity(attract ? 0 : 1)
                    if attract { AttractFilm(posters: model.candidates) { attract = false } }
                }
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(maxHeight: DS.Welcome.sceneHeight)
            Spacer(minLength: DS.Space.s4)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Text("Todo lo que quieres ver, en un solo lugar.").recipe(.display, color: DS.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Encuentra qué ver, sigue tus series y míralo aquí mismo.").recipe(.body, color: DS.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : DS.Welcome.rise)
            Button(action: next) { Text("Empezar").frame(maxWidth: .infinity) }
                .dsPrimaryButton().controlSize(.large)
                .opacity(showsButton ? 1 : 0)
                .accessibilityIdentifier("guide-next")
        }
        .padding(DS.Space.s6)
        .frame(maxWidth: DS.Guide.readable)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Backdrop())
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { touched += 1; attract = false })
        .dsFeedback(.impact(flexibility: .soft), trigger: moon)
        .task { await model.loadCandidates() }
        .task {
            if reduceMotion { appeared = true; showsButton = true; return }
            try? await Task.sleep(for: .seconds(DS.Welcome.phraseAt))
            withAnimation(DS.Motion.enter(reduceMotion)) { appeared = true }
            try? await Task.sleep(for: .seconds(DS.Welcome.buttonAt - DS.Welcome.phraseAt))
            withAnimation(DS.Motion.base(reduceMotion)) { showsButton = true }
        }
        // B1: la vitrina, a los 12 s sin tocar (cada toque vuelve a contar).
        .task(id: touched) {
            guard !reduceMotion, !UIAccessibility.isVoiceOverRunning, touched == 0 else { return }
            try? await Task.sleep(for: DS.Attract.idle)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Motion.fade) { attract = true }
        }
    }
}

/// La vitrina (B1): la bienvenida se enseña sola. La luna se posa en un póster, el póster se vuelve su ficha, se encienden
/// los tres pasos de la nube y «Ver» se presiona. Dos vueltas y regresa a la órbita (`finished`).
struct AttractFilm: View {
    let posters: [Suggestion]
    let finished: () -> Void
    @State private var scene = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let scenes = 4

    var body: some View {
        let pick = posters.first
        ZStack {
            switch scene % Self.scenes {
            case 0:
                // Encuentra qué ver: tres pósters y la luna sobre el de en medio.
                HStack(spacing: DS.Space.s3) {
                    ForEach(Array(posters.prefix(3).enumerated()), id: \.offset) { i, item in
                        PosterView(url: item.poster, title: item.title, maxPoints: DS.Welcome.posterHeight * 2)
                            .frame(height: DS.Welcome.posterHeight * 2)
                            .overlay(alignment: .topTrailing) {
                                if i == 1 { Circle().fill(DS.brandMoon).frame(width: DS.Welcome.moon, height: DS.Welcome.moon) }
                            }
                            .scaleEffect(i == 1 ? 1 : DS.Explainer.restScale)
                    }
                }
            case 1:
                // Su ficha: el póster grande, el título y «Ver».
                VStack(spacing: DS.Space.s3) {
                    PosterView(url: pick?.poster, title: pick?.title ?? "", maxPoints: DS.Welcome.planet * 2)
                        .frame(height: DS.Welcome.planet * 1.6)
                    if let pick { Text(verbatim: pick.title).recipe(.cardTitle, color: DS.text) }
                }
            case 2:
                DebridFlowStrip()
            default:
                Label("Ver", systemImage: "play.fill").recipe(.cardTitle, color: DS.onPrimary)
                    .padding(.horizontal, DS.Space.s6).padding(.vertical, DS.Space.s3)
                    .background(DS.primary, in: Capsule())
                    .scaleEffect(DS.Explainer.restScale)
            }
        }
        .id(scene)
        .transition(.opacity)
        .frame(maxWidth: .infinity, minHeight: DS.Welcome.orbitWidth)
        .accessibilityHidden(true)
        .task {
            for i in 1...(Self.scenes * DS.Attract.rounds) {
                try? await Task.sleep(for: i % Self.scenes == 3 ? DS.Attract.scene * 2 : DS.Attract.scene)
                guard !Task.isCancelled else { return }
                if i == Self.scenes * DS.Attract.rounds { withAnimation(DS.Motion.fade) { finished() }; return }
                withAnimation(DS.Motion.fade) { scene = i }
            }
        }
    }
}
