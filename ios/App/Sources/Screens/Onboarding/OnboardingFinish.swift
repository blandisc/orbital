import SwiftUI
import OrbitalCore
import OrbitalModels

/// U7 · U6 · «¿Ya usas Orbital en la TV?» (Fernando, 18 nov 2026; prototipo `screens/tvfirst.js`). Solo Ultra en el iPhone,
/// justo después de la bienvenida. «Sí, conectar mi TV» abre el código de la TV (Ajustes › Conectar un aparato); al conectar,
/// la pantalla cambia en su lugar a «Listo, trajimos lo de tu TV»: tu servicio de nube (si la TV lo tenía) y que Trakt se
/// conecta en el paso siguiente, porque cada aparato conecta el suyo. «No tengo la TV» sigue sin ella.
/// Pendiente: que la busque sola en tu red de casa (los anillos del prototipo); hoy ni la TV ni el iPhone se anuncian.
struct OnboardingTV: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var debrid: ModelObserver<DebridModel>
    @State private var connecting = false
    @State private var start = Date()
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _debrid = State(wrappedValue: ModelObserver(guide.debrid))
        self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let connected = guide.model.orbitalConfigured
        GuidePage(title: nil, step: step,
                  primary: connected ? guide.model.ahead(after: .tv) : Text("Sí, conectar mi TV"),
                  secondary: connected ? nil : Text("No tengo la TV"),
                  next: {
                      if connected { next() } else if guide.model.practice { guide.model.connectPracticeTV(); start = Date() } else { connecting = true }
                  },
                  skip: next, skipGuide: skip, back: back) {
            TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
                let t = reduceMotion ? GuideTVScene.askEnd + 1 : ctx.date.timeIntervalSince(start)
                VStack(alignment: .leading, spacing: DS.Space.s4) {
                    GuideTVScene(connected: connected, start: start)
                    if connected { done(t) } else { ask(t) }
                    // IOS-18: en el iPad con la invitación de tu iPhone, su tarjeta aquí mismo (CX4-A).
                    if !connected, env.services.pendingInvite != nil { IPadInviteCard { connecting = true } }
                }
            }
        }
        .dsFeedback(.success, trigger: connected)
        .sheet(isPresented: $connecting, onDismiss: {
            if guide.model.orbitalConfigured { start = Date(); Task { await debrid.model.load() } }
        }) { OrbitalSetupView() }
        .onAppear { start = Date() }
    }

    @ViewBuilder private func ask(_ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self, title = M.item(t, 0.12, 14), lead = M.item(t, 0.2, 10), fine = M.item(t, 0.32, 8)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Text("¿Ya usas Orbital en la TV?").recipe(.display, color: DS.text).fixedSize(horizontal: false, vertical: true)
                .opacity(title.opacity).offset(y: title.rise)
            Text("Conéctala con el código que sale en la TV. Tu iPhone se vuelve su control y, si la TV ya tiene tu servicio de nube, lo usas aquí también.")
                .font(DS.Welcome.lead).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
                .opacity(lead.opacity).offset(y: lead.rise)
        }
        Text("¿La tienes, pero no ahora? La conectas cuando quieras desde Ajustes.")
            .recipe(.caption, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            .opacity(fine.opacity).offset(y: fine.rise)
    }

    @ViewBuilder private func done(_ t: Double) -> some View {
        let M = GuideTraktScene.Motion.self, cloud = debrid.model
        let rows = [M.item(t, 0.1, 10), M.item(t, 0.24, 10)], title = M.item(t, 0, 12), fine = M.item(t, 0.4, 8)
        Text("Listo, trajimos lo de tu TV").recipe(.display, color: DS.text).fixedSize(horizontal: false, vertical: true)
            .opacity(title.opacity).offset(y: title.rise)
        VStack(spacing: DS.Space.s2) {
            if cloud.ready {
                row("icloud.fill", Text(verbatim: cloud.service.name), Text("Tu servicio de nube: ya puedes ver aquí"), done: true)
                    .opacity(rows[0].opacity).offset(y: rows[0].rise)
            } else {
                row("icloud", Text("Servicio de nube"), Text("Tu TV no tenía uno: lo conectas en un momento"), done: false)
                    .opacity(rows[0].opacity).offset(y: rows[0].rise)
            }
            row("person.crop.circle", Text("Tu Trakt"), Text("Lo conectas en el siguiente paso; cada aparato conecta el suyo"), done: false)
                .opacity(rows[1].opacity).offset(y: rows[1].rise)
        }
        Text("Y tu iPhone ya es el control de tu TV.").recipe(.caption, color: DS.textMuted)
            .opacity(fine.opacity).offset(y: fine.rise)
    }

    private func row(_ symbol: String, _ title: Text, _ detail: Text, done: Bool) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: symbol).font(DS.styled(.body)).foregroundStyle(DS.text).frame(width: DS.Guide.slot).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                title.recipe(.label, color: DS.text)
                detail.recipe(.caption, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.s2)
            Image(systemName: done ? "checkmark" : "circle.dashed").font(DS.styled(.body).weight(.semibold))
                .foregroundStyle(done ? DS.success : DS.textMuted).accessibilityHidden(true)
        }
        .padding(DS.Space.s2).dsCard()
        .accessibilityElement(children: .combine)
    }
}

/// 7 · Listo (G7): lo que elegiste baja y arma tu Inicio en miniatura («Porque te gustó…», «Nuevo en tus plataformas»); al
/// tocar «Ir a Inicio», ese Inicio crece a pantalla completa y se vuelve el de verdad. Sin resumen de piezas (Q4).
struct OnboardingDone: View {
    let finish: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var grow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guide: OnboardingModel, finish: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); self.finish = finish
    }

    var body: some View {
        let model = guide.model
        let liked = model.candidates.filter { model.liked.contains($0.imdb) }
        let more = model.candidates.filter { !model.liked.contains($0.imdb) }
        let logos = model.platforms.filter { model.chosenPlatforms.contains($0.brand) }.compactMap(\.logo)
        // G2-B y G4-B (18 nov 2026): no promete «lo que te gusta» si no elegiste nada, y sin nube dice dónde conectarla.
        let cloud = model.offersDebrid && !model.isConnected(.debrid)
        let message: Text = switch (liked.isEmpty, cloud) {
        case (false, false): Text("Te armé Inicio con lo que te gusta.")
        case (true, false): Text("Te armé Inicio con lo popular de ahora.")
        case (false, true): Text("Te armé Inicio con lo que te gusta. Para ver películas, conecta tu nube en Ajustes › Cuentas cuando quieras.")
        case (true, true): Text("Te armé Inicio con lo popular de ahora. Para ver películas, conecta tu nube en Ajustes › Cuentas cuando quieras.")
        }
        GuidePage(title: Text("Tu Orbital ya está lista."),
                  message: message,
                  primary: Text("Ir a Inicio"), next: go) {
            GuideMiniHome(liked: liked.isEmpty ? Array(more.prefix(3)) : liked, more: Array(more.dropFirst(liked.isEmpty ? 3 : 0)), logos: logos, grow: grow, chose: !liked.isEmpty)
        }
        .dsFeedback(.success, trigger: grow)
    }

    /// El Inicio en miniatura crece y se desvanece; luego, el de verdad.
    private func go() {
        guard !reduceMotion else { return finish() }
        withAnimation(DS.Motion.enter(reduceMotion)) { grow = true }
        Task { try? await Task.sleep(for: .seconds(DesignTokens.Motion.enter)); finish() }
    }
}
