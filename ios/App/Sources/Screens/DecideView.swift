import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Decide por mí»: dos preguntas (cuánto tiempo tienes, qué quieres) y una sola propuesta grande con su porqué.
struct DecideView: View {
    @StateObject private var observer: ModelObserver<DecideModel>
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let open: (TitleRoute) -> Void

    init(pool: [Suggestion], open: @escaping (TitleRoute) -> Void) {
        _observer = StateObject(wrappedValue: ModelObserver(DecideModel(AppEnvironment.shared.services, pool: pool)))
        self.open = open
    }

    var body: some View {
        let m = observer.model
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            if let pick = m.pick { proposal(pick, m) } else { questions(m) }
        }
        .padding(DS.Space.s5)
        .animation(DS.Motion.base(false), value: m.pick?.imdb)
    }

    @ViewBuilder private func questions(_ m: DecideModel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("¿Qué vemos?").recipe(.title)
            Text("Una sola, de tus sugerencias, que no hayas visto.").recipe(.footnote)
        }
        PanelGroupTitle(title: "Tengo")
        FlowChips {
            ForEach(DecideModel.Time.allCases, id: \.self) { t in
                PanelChip(title: timeName(t), selected: m.time == t, font: DS.TextRecipe.body.font) { m.time = t }
            }
        }
        PanelGroupTitle(title: "Quiero algo")
        FlowChips {
            ForEach(DecideModel.Mood.allCases, id: \.self) { mood in
                PanelChip(title: moodName(mood), selected: m.mood == mood, font: DS.TextRecipe.body.font, symbol: moodSymbol(mood)) { m.mood = mood }
            }
        }
        if m.exhausted { DSNotice(text: "No encontré otra con eso: prueba otro ánimo o más tiempo.") }
        Button { Task { await m.decide() } } label: {
            HStack { if m.isLoading { ProgressView() }; Text("Decide por mí") }.frame(maxWidth: .infinity)
        }
        .dsPrimaryButton().controlSize(.large).disabled(m.isLoading)
    }

    @ViewBuilder private func proposal(_ s: Suggestion, _ m: DecideModel) -> some View {
        let why = [m.minutes.map { "\($0) min" }, Strings.tr(moodLabel(m.mood), language: env.services.appSettings.uiLanguage)].compactMap { $0 }.joined(separator: " · ")
        CoverCard(art: s.wide, logo: s.logo, title: s.title, why: Text(verbatim: why), detail: Text(badgeKey(s.reason)))
            .frame(height: DS.Editorial.decideHeight)
            .onTapGesture { dismiss(); open(s.route) }
        HStack(spacing: DS.Space.s3) {
            Button {
                dismiss()
                if s.kind == "series" { open(s.route) } else { Task { await env.play(s) } }
            } label: { Label(s.kind == "series" ? "Ver la serie" : "Ver", systemImage: "play.fill").frame(maxWidth: .infinity) }
                .dsPrimaryButton().controlSize(.large)
            Button { Task { await m.next() } } label: { Text("Otra").frame(maxWidth: .infinity) }
                .buttonStyle(.glass).controlSize(.large).disabled(m.isLoading)
        }
        HStack {
            Button("Hoy no") { Task { await m.skipToday() } }
            Spacer()
            Button("Cambiar lo que quiero") { Task { await m.reset() } }
        }
        .font(DS.TextRecipe.footnote.font).buttonStyle(.borderless).foregroundStyle(DS.textMuted)
    }

    private func timeName(_ t: DecideModel.Time) -> Text {
        switch t { case .short: Text("30 min"); case .hour: Text("1 h"); case .long: Text("2 h o más") }
    }

    private func moodName(_ m: DecideModel.Mood) -> Text { Text(LocalizedStringKey(moodLabel(m))) }

    private func moodSymbol(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "sun.max"; case .intense: "bolt"; case .think: "lightbulb"; case .together: "heart" }
    }

    private func moodLabel(_ m: DecideModel.Mood) -> String {
        switch m { case .light: "Ligero"; case .intense: "Intenso"; case .think: "Para pensar"; case .together: "En pareja" }
    }
}
