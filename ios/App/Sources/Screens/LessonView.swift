import SwiftUI
import OrbitalCore
import OrbitalModels

/// Una lección de Aprende a tu ritmo (AF1-B · AF3-B, Fernando, 19 nov 2026; prototipo en
/// docs/producto/aprende-a-fondo-2026-11-19/prototipo/). Arriba, el arco de la guía con la luna en tu pantalla, «Atrás» y
/// «Cerrar»; en medio, la escena grande con pósters de verdad; abajo, de qué lección es (en turquesa), el titular y dos
/// líneas, que llegan justo después de que la escena arranca. Nada avanza solo: «Siguiente», o deslizar. La última pantalla
/// es «Pruébalo»: la escena se toca de verdad, de práctica (nada se pide, se manda ni se guarda) y, al lograrlo, «¡Eso es!»
/// con un toque en la mano. Al final, el botón a la función de verdad («Conectar mi nube») si aún no la tienes, y «Listo».
/// Desde un «?» (AF2-B) empieza en la pantalla que contesta tu duda y «Cerrar» te regresa adonde estabas.
struct LessonView: View {
    let lesson: Lesson
    var startAt = 0
    /// Ya tienes lo que ofrece el botón del final (tu nube conectada, Trakt, tu TV): entonces solo «Listo».
    var connected = false
    let finish: (_ seen: Bool) -> Void
    let act: (LearnStory.Destination) -> Void
    @State private var step = 0
    @State private var forward = true
    @State private var start = Date()
    @State private var art = LessonArt()
    @State private var tried = false
    @State private var shown = false
    @Environment(AppEnvironment.self) private var env
    @Environment(\.titleName) private var titleName
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var current: Lesson.Step { lesson.steps[min(step, lesson.steps.count - 1)] }
    private var last: Bool { step >= lesson.steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            top
            ScrollView {
                page.id(step)
                    // Entra de lado (hacia donde avanzas) y la que se va solo se apaga: un movimiento, no tres.
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? DS.Lesson.pageShift : -DS.Lesson.pageShift)),
                                            removal: .opacity))
                    .frame(maxWidth: DS.Guide.readable)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaBar(edge: .bottom) { buttons }
        .background(Backdrop())
        .tint(DS.accent)
        .contentShape(Rectangle())
        .gesture(current.practice ? nil : DragGesture(minimumDistance: DS.Space.s8).onEnded { g in
            guard abs(g.translation.width) > abs(g.translation.height) * 2 else { return }
            if g.translation.width < -DS.Space.s14 { next() } else if g.translation.width > DS.Space.s14 { back() }
        })
        .onKeyPress(.rightArrow) { next(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
        .onKeyPress(.escape) { finish(false); return .handled }
        .dsFeedback(.success, trigger: tried)
        .accessibilityAction(.escape) { finish(false) }
        .onAppear { step = min(max(startAt, 0), lesson.steps.count - 1); restart() }
        .task {
            let name = titleName
            art = await LessonArt.load(env.services) { name($0, id: $1, kind: $2) }
            // La escena arranca cuando ya están los pósters (no se anima sobre cuadros vacíos); «Pruébalo» no se reinicia.
            if !current.practice { start = Date() }
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("lesson-\(lesson.id)")
    }

    private var top: some View {
        HStack(spacing: DS.Space.s4) {
            DSIconButton(symbol: "chevron.backward", label: "Atrás", size: .regular, action: back)
                .opacity(step > 0 ? 1 : 0).disabled(step == 0)
                .accessibilityHidden(step == 0)
                .accessibilityIdentifier("lesson-back")
            GuideSteps(current: step, total: lesson.steps.count)
            Button { finish(false) } label: { Text("Cerrar") }
                .buttonStyle(.borderless).foregroundStyle(DS.textMuted).frame(minHeight: DS.Size.touchTarget)
                .accessibilityIdentifier("lesson-close")
        }
        .padding(.horizontal, DS.Space.s6).padding(.top, DS.Space.s2)
        .frame(maxWidth: DS.Guide.readable).frame(maxWidth: .infinity)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
            LessonScene(id: current.scene, art: art, start: start) { tried = true }
                .frame(maxWidth: DS.Lesson.sceneMax)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                eyebrow.id(tried).opacity(shown ? 1 : 0).offset(y: shown ? 0 : DS.Lesson.textRise)
                    .animation(DS.Motion.enter(reduceMotion)?.delay(DS.Lesson.textAt), value: shown)
                Text(current.title, cloud: art.cloud, locale: locale)   // no-es-título: el titular de la pantalla de la lección
                    .recipe(.display, color: DS.text).fixedSize(horizontal: false, vertical: true)
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : DS.Lesson.textRise)
                    .animation(DS.Motion.enter(reduceMotion)?.delay(DS.Lesson.textAt + DS.Lesson.textStep), value: shown)
                    .accessibilityAddTraits(.isHeader)
                Text(current.line, cloud: art.cloud, locale: locale)
                    .font(DS.Welcome.lead).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
                    .opacity(shown ? 1 : 0).offset(y: shown ? 0 : DS.Lesson.textRise)
                    .animation(DS.Motion.enter(reduceMotion)?.delay(DS.Lesson.textAt + 2 * DS.Lesson.textStep), value: shown)
            }
            .padding(.horizontal, DS.Space.s6)
            .animation(DS.Motion.spring(reduceMotion), value: tried)
        }
        .padding(.top, DS.Space.s3)
        .accessibilityElement(children: .contain)
    }

    /// El renglón turquesa de arriba: de qué lección es; en «Pruébalo», que es de práctica y, al lograrlo, «¡Eso es!» justo
    /// bajo la escena, donde está la vista (no más abajo).
    @ViewBuilder private var eyebrow: some View {
        if current.practice && tried {
            Label("¡Eso es! Así de fácil.", systemImage: "checkmark.circle.fill")
                .font(DS.TextRecipe.labelLarge.font).foregroundStyle(DS.fresh)
                .contentTransition(.symbolEffect(.replace))
                .transition(.opacity.combined(with: .scale(scale: DS.Scene.pressed)))
                .accessibilityIdentifier("lesson-tried")
        } else if current.practice {
            Label("Pruébalo", systemImage: "hand.tap.fill")
                .font(DS.TextRecipe.label.font).foregroundStyle(DS.eyebrow)
                .accessibilityLabel(Text("Pruébalo, de práctica"))
        } else {
            Label { Text(lesson.title) } icon: { Image(systemName: lesson.symbol) }   // no-es-título: de qué lección es
                .font(DS.TextRecipe.label.font).foregroundStyle(DS.eyebrow)
        }
    }

    private var buttons: some View {
        VStack(spacing: DS.Space.s2) {
            if last, let done = lesson.done, !connected {
                // Mientras practicas, la práctica manda: el botón a la función de verdad se enciende cuando lo logras.
                Button { act(done.destination); finish(true) } label: { Text(LocalizedStringKey(done.title)).frame(maxWidth: .infinity) }
                    .modifier(LessonActStyle(lit: tried || !current.practice))
                    .accessibilityIdentifier("lesson-act")
                Button { finish(true) } label: { Text("Listo").frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted)
                    .accessibilityIdentifier("lesson-done")
            } else {
                Button { last ? finish(true) : next() } label: { Text(last ? "Listo" : "Siguiente").frame(maxWidth: .infinity) }
                    .dsPrimaryButton().dsControlSize(.large)
                    .accessibilityIdentifier(last ? "lesson-done" : "lesson-next")
            }
        }
        .animation(DS.Motion.base(reduceMotion), value: tried)
        .frame(maxWidth: DS.Welcome.buttonWidth)
        .padding(.horizontal, DS.Space.s6).padding(.bottom, DS.Space.s3)
        .frame(maxWidth: .infinity)
    }

    private func next() {
        guard !last else { return }
        go(step + 1, forward: true)
    }

    private func back() {
        guard step > 0 else { return }
        go(step - 1, forward: false)
    }

    private func go(_ to: Int, forward: Bool) {
        self.forward = forward
        withAnimation(DS.Motion.enter(reduceMotion) ?? DS.Motion.fade) { step = to }
        restart()
    }

    /// La escena empieza de cero y el texto vuelve a llegar después de ella.
    private func restart() {
        start = Date(); tried = false; shown = false
        Task { @MainActor in shown = true }
    }
}

extension LessonArt {
    /// Lo popular de ahora (películas y series aparte), como la bienvenida; sin red, el último mosaico guardado.
    @MainActor static func load(_ services: Services, name: (String, String, String) -> String) async -> LessonArt {
        let forYou = services.forYou
        async let movies = (try? await forYou.items(listID: "trend", kind: "movie")) ?? []
        async let series = (try? await forYou.items(listID: "trend", kind: "series")) ?? []
        var (m, s) = await (movies, series)
        if m.isEmpty && s.isEmpty {
            let cached = await forYou.cachedMosaic()
            m = cached.filter { $0.kind == "movie" }; s = cached.filter { $0.kind != "movie" }
        }
        let item = { (x: Suggestion) in Item(url: x.poster.isEmpty ? nil : x.poster, title: name(x.title, x.imdb, x.kind), imdb: x.imdb,
                                         wide: x.wide.isEmpty ? nil : x.wide) }
        return LessonArt(movies: m.filter { !$0.poster.isEmpty }.prefix(12).map(item),
                         series: s.filter { !$0.poster.isEmpty }.prefix(8).map(item),
                         cloud: services.debrid.service)
    }
}

/// El botón del final de una lección: en segundo plano mientras practicas; principal cuando ya lo lograste.
private struct LessonActStyle: ViewModifier {
    let lit: Bool
    func body(content: Content) -> some View {
        if lit { content.dsPrimaryButton().dsControlSize(.large) } else { content.dsSecondaryButton().dsControlSize(.large) }
    }
}
