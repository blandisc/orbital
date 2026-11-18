import SwiftUI
import UIKit
import OrbitalModels
import OrbitalAddons

/// 4 · Ver aquí mismo (D1; G4 de la revisión): una escena viva en lugar de dos pantallas de lectura. La ficha, el dedo toca
/// «Ver» y arranca; abajo, una sola línea: es un servicio de pago y sirve cualquiera de las tres. DN1 (18 nov 2026): un solo
/// botón, «Conectar tu nube», abre la hoja «Tu nube» (la misma de Ajustes › Cuentas): «Ya tengo cuenta» o «Todavía no
/// tengo». Nunca dice «Real-Debrid» solo antes de elegir. Pagar no detiene la guía: «Cuando quiera ver algo».
struct OnboardingSeeHere: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var debrid: ModelObserver<DebridModel>
    @State private var choosing = false

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _debrid = State(wrappedValue: ModelObserver(guide.debrid))
        self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = debrid.model
        GuidePage(title: Text("Ve todo al instante, aquí"),
                  step: step,
                  primary: model.ready ? Text("Seguir") : Text("Elegir tu nube"),   // G1-B (18 nov 2026)
                  secondary: model.ready ? nil : Text("Ahora no, después"),
                  next: { if model.ready { next() } else { choosing = true } },
                  skip: next, skipGuide: skip, back: back) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                StorySceneView(scene: .titlePlay, tint: DS.ListTint.flame)
                    .frame(height: DS.GuideScene.sceneHeight)
                    .overlay(alignment: .topTrailing) {
                        if model.ready {
                            Image(systemName: "checkmark.icloud.fill").font(DS.TextRecipe.title.font).foregroundStyle(DS.fresh)
                                .padding(DS.Space.s3).transition(.scale.combined(with: .opacity))
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(Text("Así funciona: tocas «Ver», la nube lo tiene y lo ves"))
                Text("Para ver aquí necesitas una nube: un servicio de pago que guarda películas y series. Sirve Real-Debrid, TorBox o AllDebrid.")
                    .recipe(.secondary, color: DS.textMuted)
                if model.ready, let status = model.status {
                    GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success,
                               title: Text(verbatim: "\(model.service.name) · \(status.username)"), detail: DebridWords.text(status))
                }
                DebridSharedOffer(debrid: model, carded: true)
            }
        }
        .dsFeedback(.success, trigger: model.ready)
        .sheet(isPresented: $choosing) { DebridCloudSheet(debrid: model) }
        .onChange(of: model.ready) { _, ready in if ready { choosing = false } }
        .task { await model.checkShared() }
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
        VStack(alignment: .leading, spacing: DS.Space.s3) {
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
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            HStack(spacing: DS.Space.s2) {
                TextField("Pega tu clave", text: Binding(get: { debrid.token }, set: { debrid.token = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().font(DS.TextRecipe.data.font)
                    .onSubmit { Task { await debrid.verify() } }
                    .padding(DS.Space.s3).dsCard(translucent: true)
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
            HStack(spacing: DS.Space.s3) {
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
