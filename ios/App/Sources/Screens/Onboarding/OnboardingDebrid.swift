import SwiftUI
import UIKit
import OrbitalModels
import OrbitalAddons

/// Tu servicio de nube (P1 · P2-B · P12 · P13 · P18; Fernando, 18 nov 2026; prototipo `screens/cloud.js`). Solo Plus y Ultra.
/// Arriba, la escena de tres pasos (`GuideCloudScene`); abajo, que es aparte de Orbital, que se paga en su página y que es
/// una cuenta por persona. Tres caminos: «Ya tengo uno» (la hoja «Tu nube» de Ajustes › Cuentas: elegir y conectar), «Aún no
/// tengo» (las tres, con Real-Debrid sugerido porque se conecta con un código, y «Ya lo contraté, conectar») y «Ahora no».
/// Al conectar, la pantalla cambia en su lugar a «Listo: <nube> conectado» con «Listas al instante».
struct OnboardingSeeHere: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var debrid: ModelObserver<DebridModel>
    @State private var choosing = false
    @State private var none = false
    /// «Ya lo contraté, conectar»: la hoja «Tu nube» se abre cuando se cierra la de «Aún no tienes uno».
    @State private var chooseAfter = false
    @State private var explaining = false
    @State private var start = Date()
    @State private var readyStart = Date()
    @Environment(\.titleName) private var titleName
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _debrid = State(wrappedValue: ModelObserver(guide.debrid))
        self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = debrid.model
        let posters = guide.model.candidates.prefix(4).map { (url: $0.poster, title: titleName($0.title, id: $0.imdb, kind: $0.kind)) }
        GuidePage(title: nil, step: step,
                  primary: model.ready ? Text("Continuar") : Text("Ya tengo uno"),
                  secondary: model.ready ? Text("Cambiar") : Text("Ahora no"),
                  alternate: model.ready ? nil : Text("Aún no tengo"), alternateAction: { none = true },
                  next: { if model.ready { next() } else { choosing = true } },
                  skip: { if model.ready { choosing = true } else { next() } }, skipGuide: skip, back: back) {
            if model.ready {
                ready(model, posters: Array(posters))
            } else {
                ask(Array(posters))
            }
        }
        .dsFeedback(.success, trigger: model.ready)
        .sheet(isPresented: $choosing) { DebridCloudSheet(debrid: model) }
        .sheet(isPresented: $none, onDismiss: { if chooseAfter { chooseAfter = false; choosing = true } }) {
            CloudNoneSheet(connect: { chooseAfter = true; none = false }, later: { none = false; next() })
        }
        .sheet(isPresented: $explaining) { DebridCloudsExplainer() }
        .onChange(of: model.ready) { _, ready in if ready { choosing = false; readyStart = Date() } }
        .onAppear { start = Date() }
        .task { await guide.model.loadCandidates() }
        .task { await model.checkShared() }
    }

    @ViewBuilder private func ask(_ posters: [(url: String?, title: String)]) -> some View {
        let model = debrid.model
        TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? GuideCloudScene.end + 1 : ctx.date.timeIntervalSince(start), M = GuideTraktScene.Motion.self
            let title = M.item(t, 0.12, 14), lead = M.item(t, 0.2, 10), f0 = M.item(t, 0.26, 8), f1 = M.item(t, 0.31, 8)
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                GuideCloudScene(posters: posters, start: start)
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    Text("Para ver aquí, conecta un servicio de nube").recipe(.display, color: DS.text)
                        .fixedSize(horizontal: false, vertical: true).opacity(title.opacity).offset(y: title.rise)
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Text("Es aparte de Orbital: guarda las películas y las tiene listas para ti.")
                            .font(DS.Welcome.lead).foregroundStyle(DS.textMuted).fixedSize(horizontal: false, vertical: true)
                        Button("¿Cómo funciona?") { explaining = true }.font(DS.Welcome.lead).foregroundStyle(DS.accent)
                            .accessibilityIdentifier("cloud-how")
                    }
                    .opacity(lead.opacity).offset(y: lead.rise)
                }
                VStack(alignment: .leading, spacing: DS.Space.s2) {
                    fact("creditcard", Text("Se paga en su página."), Text("Orbital no cobra nada.")).opacity(f0.opacity).offset(y: f0.rise)
                    fact("person", Text("Una cuenta por persona."), Text("Si dos la usan a la vez, se corta.")).opacity(f1.opacity).offset(y: f1.rise)
                }
                DebridSharedOffer(debrid: model, carded: true)
            }
        }
    }

    private func fact(_ symbol: String, _ bold: Text, _ rest: Text) -> some View {
        HStack(spacing: DS.Space.s2) {
            Image(systemName: symbol).font(DS.styled(.body)).foregroundStyle(DS.text).frame(width: DS.Guide.slot).accessibilityHidden(true)
            Text("\(bold.foregroundStyle(DS.text).bold()) \(rest.foregroundStyle(DS.textMuted))")
                .font(DS.TextRecipe.secondary.font).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func ready(_ model: DebridModel, posters: [(url: String?, title: String)]) -> some View {
        let name = model.service.name
        TimelineView(.animation(minimumInterval: DS.Welcome.introFrame, paused: reduceMotion)) { ctx in
            let t = reduceMotion ? GuideCloudReady.end + 1 : ctx.date.timeIntervalSince(readyStart), M = GuideTraktScene.Motion.self
            let title = M.item(t, 0.12, 12), lead = M.item(t, 0.2, 8)
            VStack(spacing: DS.Space.s6) {
                GuideCloudReady.badge(t).padding(.top, DS.Space.s8)
                VStack(spacing: DS.Space.s2) {
                    Text("Listo: \(name) conectado").recipe(.display, color: DS.text).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).opacity(title.opacity).offset(y: title.rise)
                    Group {
                        if let status = model.status {
                            Text("\(Text(verbatim: status.username).foregroundStyle(DS.text)) · \(DebridWords.short(status))")
                        }
                    }
                    .font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted)
                    Text("Ya puedes ver aquí. Lo que tu servicio ya tiene arranca al instante.")
                        .font(DS.Welcome.lead).foregroundStyle(DS.textMuted).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).opacity(lead.opacity).offset(y: lead.rise)
                }
                GuideCloudReady.row(posters, t)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// «Aún no tienes uno»: las tres, con Real-Debrid sugerido (se conecta con un código, sin copiar claves); cada una abre su
/// página para contratarla. «Ya lo contraté, conectar» vuelve a la hoja «Tu nube»; «Seguir sin él por ahora» sigue la guía.
struct CloudNoneSheet: View {
    let connect: () -> Void
    let later: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSheetHeader(title: Text("Aún no tienes uno"))
            Text("Hay tres y hacen lo mismo. Se contrata en su página y puedes cambiar después.")
                .recipe(.secondary, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: DS.Space.s2) {
                ForEach(DebridService.allCases) { cloud in
                    Link(destination: cloud.signupURL) {
                        HStack(spacing: DS.Space.s2) {
                            DSCloudMark(cloud: cloud)
                            TorrentioRowLabel(title: Text(verbatim: cloud.name),   // no-es-título: el nombre de la nube
                                              detail: cloud == .realDebrid ? Text("Te lo sugerimos: se conecta con un código, sin copiar claves")
                                                                           : Text("Se conecta con tu clave"))
                            Spacer(minLength: DS.Space.s2)
                            Image(systemName: "arrow.up.right").foregroundStyle(DS.textMuted).accessibilityHidden(true)
                        }
                        .padding(DS.Space.s2).contentShape(Rectangle())
                        .dsCard(fill: cloud == .realDebrid ? DS.fresh.opacity(DS.Opacity.selectedFill) : nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cloud-none-\(cloud.rawValue)")
                }
            }
            VStack(spacing: DS.Space.s2) {
                Button(action: connect) { Text("Ya lo contraté, conectar").frame(maxWidth: .infinity) }
                    .dsPrimaryButton().dsControlSize(.large).accessibilityIdentifier("cloud-none-connect")
                Button(action: later) { Text("Seguir sin él por ahora").frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                    .buttonStyle(.plain).foregroundStyle(DS.textMuted).accessibilityIdentifier("cloud-none-later")
                Text("Te lo recordamos en Inicio. Mientras, Orbital ya te sirve para descubrir y guardar.")
                    .recipe(.caption, color: DS.textMuted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
        }
        .dsSheetContent()
        .fittedSheet()
    }
}

/// RC1 · conectar con un código, como Trakt (solo Real-Debrid: Ajustes › Cuentas › Tu nube): el código grande para real-debrid.com/device,
/// el botón que la abre y la espera; en cuanto lo apruebas, queda conectado solo. `showsStart`: con su propio botón para
/// empezar (en Ajustes; en la guía lo empieza el botón de abajo).
struct DebridCodeConnect: View {
    @State private var observer: ModelObserver<DebridModel>
    var showsStart = true

    init(debrid: DebridModel, showsStart: Bool = true) { _observer = State(wrappedValue: ModelObserver(debrid)); self.showsStart = showsStart }

    var body: some View {
        let model = observer.model
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            switch model.codeFlow {
            case .idle:
                if showsStart {
                    Button("Conectar con un código", systemImage: "qrcode") { model.connectWithCode() }.dsGlassButton()
                        .accessibilityIdentifier("debrid-code-start")
                }
            case .asking: DSInlineProgress(text: Text("Pidiendo un código…"))
            case .waiting(let code, let url):
                DeviceCodeCard(service: "Real-Debrid", code: code, url: url).accessibilityIdentifier("debrid-code")   // solo Real-Debrid: el código es suyo
            case .connecting: DSInlineProgress(text: Text("Conectando…"))
            case .failed(let message):
                DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .warn)
                Button("Pedir otro código", systemImage: "arrow.clockwise") { model.connectWithCode() }.dsGlassButton()
            }
        }
        .onDisappear { if case .waiting = model.codeFlow { model.cancelCode() } }
    }
}

/// El campo de la clave con «Pegar» y lo que dijo tu nube (la que se conecta). Lo comparten la guía y Ajustes › Cuentas › «Cambiar clave».
struct DebridKeyField: View {
    @State private var observer: ModelObserver<DebridModel>
    @Environment(\.openURL) private var openURL

    init(debrid: DebridModel) { _observer = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let debrid = observer.model
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                TextField("Pega tu clave", text: Binding(get: { debrid.token }, set: { debrid.token = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(DS.TextRecipe.data.font)
                    .onSubmit { Task { await debrid.verify() } }
                    .padding(DS.Space.s2).dsCard(translucent: true)
                    .accessibilityIdentifier("debrid-token")
                Button("Pegar", systemImage: "doc.on.clipboard") {
                    if let text = UIPasteboard.general.string { debrid.token = text; Task { await debrid.verify() } }
                }
                .dsGlassButton()
            }
            switch debrid.check {
            case .idle: if !debrid.token.isEmpty { Button("Comprobar") { Task { await debrid.verify() } }.dsGlassButton() }
            case .checking: DSInlineProgress(text: Text("Comprobando…"))
            case .ok(let status):
                GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text(verbatim: "\(status.username) · Premium"),
                           detail: DebridWords.text(status))
            case .free:
                DSNotice(text: "Tu cuenta es gratuita: necesitas Premium para ver.", tone: .warn)
                Button("Hacerla Premium") { openURL(debrid.renewURL) }.dsGlassButton()
            case .failed(let message):
                // IOS-9, IOS-18: en ámbar y con su arreglo (antes, rojo y sin botón).
                DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .warn)
                Button("Abrir \(debrid.connecting.keyPlace)", systemImage: "arrow.up.right") { openURL(debrid.tokenURL) }
                    .dsGlassButton()
                    .accessibilityIdentifier("debrid-open-apitoken")
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }   // F: la raya de abajo, de orilla a orilla (salía una rayita suelta a la derecha)
    }
}

/// «Sacar tu clave» y, abajo, dónde (`real-debrid.com/apitoken`): en dos renglones para que la dirección nunca se parta a
/// media palabra (F, 18 nov 2026: salía «real- / debrid.com/apitoken»). Lo usan «Pega tu clave» y «Cambiar la clave».
struct DebridKeyLink: View {
    @State private var observer: ModelObserver<DebridModel>
    init(debrid: DebridModel) { _observer = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = observer.model
        Link(destination: model.tokenURL) {
            HStack(spacing: DS.Space.s2) {
                TorrentioRowLabel(title: Text("Sacar tu clave"), detail: Text(verbatim: model.connecting.keyPlace))
                Spacer(minLength: DS.Space.s2)
                Image(systemName: "arrow.up.right").foregroundStyle(DS.textMuted).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("debrid-key-link")
    }
}

/// «Te quedan 143 días · vence el 21 de marzo de 2027», «Vence hoy», «Venció hace 2 días» o «Cuenta gratuita».
@MainActor
enum DebridWords {
    static func text(_ status: DebridStatus, now: Date = Date()) -> Text {
        let (state, days) = DebridModel.summary(status, now: now)
        // En el idioma de la app, no en el del sistema.
        let date = status.expires.map { $0.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(AppEnvironment.shared.uiLocale)) }
        switch state {
        case .active, .expiringSoon:
            if days == 0 { return Text("Vence hoy") }
            if days == .max { return Text(verbatim: "Premium") }
            if let date { return Text("Te quedan \(String(days)) días · vence el \(date)") }
            return Text("Te quedan \(String(days)) días")
        case .expired: return days == 0 ? Text("Venció hoy") : Text("Venció hace \(String(days)) días")
        case .free: return Text("Cuenta gratuita")
        }
    }

    /// Para un renglón: «143 días», «Vence hoy», «Venció».
    static func short(_ status: DebridStatus, now: Date = Date()) -> Text {
        let (state, days) = DebridModel.summary(status, now: now)
        switch state {
        case .active, .expiringSoon: return days == 0 ? Text("Vence hoy") : days == .max ? Text(verbatim: "Premium") : Text("\(String(days)) días")
        case .expired: return Text("Venció")
        case .free: return Text("Cuenta gratuita")
        }
    }
}
