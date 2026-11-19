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
    @State private var showsTop = false
    /// Cuántos de los cuatro renglones ya entraron (BV-T2).
    @State private var rows = 0
    @Environment(AppEnvironment.self) private var env
    @State private var moon = 0
    @State private var attract = false
    @State private var touched = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// En pantalla ancha (iPad, Mac) la marca crece hasta `DS.Welcome.wideScale`.
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(guide: OnboardingModel, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.next = next; self.skip = skip
    }

    var body: some View {
        let model = guide.model
        VStack(spacing: DS.Space.s5) {
            // BV-L1 (Fernando, 18 nov 2026): el idioma en un globo arriba a la izquierda; «Saltar» a la derecha.
            HStack { WelcomeLanguageMenu(settings: model.settings); Spacer(); GuideSkip(action: skip) }
                .opacity(showsTop ? 1 : 0)
            Spacer(minLength: DS.Space.s4)
            // En un iPhone chico (SE) la escena se encoge para que el texto y «Empezar» quepan.
            GeometryReader { geo in
                let scale = min(sizeClass == .regular ? DS.Welcome.wideScale : 1, geo.size.height / DS.Welcome.sceneHeight)
                ZStack {
                    OrbitCatch(posters: model.candidates) { moon += 1 }
                        .opacity(attract ? 0 : 1)
                    if attract { AttractFilm(posters: model.candidates) { attract = false } }
                }
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(maxHeight: DS.Welcome.sceneHeight * DS.Welcome.wideScale)
            .layoutPriority(1)   // la marca toma su alto antes que los espacios (si no, se quedaba chica en el iPad y la Mac)
            Spacer(minLength: DS.Space.s4)
            // BV-T2 (Fernando, 18 nov 2026): el titular y cuatro renglones con ícono que entran al ritmo de la órbita.
            VStack(alignment: .center, spacing: DS.Space.s4) {
                Text("Todo lo que quieres ver, en un solo lugar.").recipe(.display, color: DS.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : DS.Welcome.rise)
                VStack(alignment: .leading, spacing: DS.Space.s3) {
                    ForEach(Array(WelcomeRow.rows(env.services.capabilities).enumerated()), id: \.offset) { i, row in
                        WelcomeRowView(row: row, shown: rows > i)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            Button(action: next) { Text("Empezar").frame(maxWidth: .infinity) }
                .dsPrimaryButton().dsControlSize(.large)
                .frame(maxWidth: DS.Welcome.buttonWidth)
                .opacity(showsButton ? 1 : 0)
                .accessibilityIdentifier("guide-next")
        }
        .padding(DS.Space.s6)
        .frame(maxWidth: DS.Guide.readable)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Backdrop())
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            touched += 1; attract = false
            // F (18 nov 2026): un toque antes de que salga «Empezar» no se pierde: el texto y el botón salen ya (parecía trabada).
            if !showsButton { withAnimation(DS.Motion.base(reduceMotion)) { appeared = true; showsTop = true; rows = WelcomeRow.count; showsButton = true } }
        })
        .dsFeedback(.impact(flexibility: .soft), trigger: moon)
        .task { await model.loadCandidates() }
        .task {
            if reduceMotion { appeared = true; showsTop = true; rows = WelcomeRow.count; showsButton = true; return }
            try? await Task.sleep(for: .seconds(DS.Welcome.topAt))
            withAnimation(DS.Motion.fade) { showsTop = true }
            try? await Task.sleep(for: .seconds(DS.Welcome.phraseAt - DS.Welcome.topAt))
            withAnimation(DS.Motion.enter(reduceMotion)) { appeared = true }
            // Los renglones, en una ola que se acorta (cada uno llega un poco más pegado al anterior).
            var at = DS.Welcome.phraseAt
            for (i, start) in DS.Welcome.rowsAt.enumerated() {
                try? await Task.sleep(for: .seconds(start - at)); at = start
                guard rows <= i else { continue }
                withAnimation(DS.Motion.enter(reduceMotion)) { rows = i + 1 }
            }
            try? await Task.sleep(for: .seconds(max(0, DS.Welcome.buttonAt - at)))
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
    @Environment(\.titleName) var titleName
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
                        PosterView(url: item.poster, title: titleName(item.title, id: item.imdb, kind: item.kind), maxPoints: DS.Welcome.posterHeight * 2)
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
                    PosterView(url: pick?.poster, title: pick.map { titleName($0.title, id: $0.imdb, kind: $0.kind) } ?? "", maxPoints: DS.Welcome.planet * 2)
                        .frame(height: DS.Welcome.planet * 1.6)
                    if let pick { Text(verbatim: titleName(pick.title, id: pick.imdb, kind: pick.kind)).recipe(.cardTitle, color: DS.text) }
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

/// BV-L1: el globo con el nombre del idioma. Un toque abre el menú (Español / English); cambia toda la app al momento.
struct WelcomeLanguageMenu: View {
    @State private var settings: ModelObserver<SettingsModel>

    init(settings: SettingsModel) { _settings = State(wrappedValue: ModelObserver(settings)) }

    var body: some View {
        let model = settings.model
        let language = model.settings.uiLanguage
        Menu {
            Picker(selection: Binding(get: { language }, set: { v in model.update { $0.uiLanguage = v } })) {
                Text(verbatim: "Español").tag("es")
                Text(verbatim: "English").tag("en")
            } label: { Text("Idioma de la app") }
        } label: {
            HStack(spacing: DS.Space.s1) {
                Image(systemName: "globe")
                Text(verbatim: language == "en" ? "English" : "Español")
                Image(systemName: "chevron.down").font(DS.styled(.caption).weight(.semibold))
            }
            .foregroundStyle(DS.textMuted)
        }
        .accessibilityIdentifier("guide-language")
        .accessibilityLabel(Text("Idioma de la app"))
    }
}
