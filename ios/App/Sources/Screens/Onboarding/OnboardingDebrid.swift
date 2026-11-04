import SwiftUI
import UIKit
import OrbitalModels
import OrbitalAddons

/// 4 · Ver aquí mismo (D1; G4 de la revisión): una escena viva en lugar de dos pantallas de lectura. La ficha, el dedo toca
/// «Ver» y arranca; abajo, una sola línea con el precio y la regla de una cuenta por persona (Q2: el detalle vive en la
/// historia «Ver al instante»). Un solo botón: «Abrir Real-Debrid y copiar clave»; al volver, si copiaste algo, «Pegar tu
/// clave» con un toque. Escribirla a mano queda en «Otra forma». Pagar no detiene la guía: «Cuando quiera ver algo».
struct OnboardingSeeHere: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var debrid: ModelObserver<DebridModel>
    @State private var opened = false
    @State private var canPaste = false
    @State private var byHand = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _debrid = State(wrappedValue: ModelObserver(guide.debrid))
        self.step = step; self.back = back; self.next = next; self.skip = skip
    }

    var body: some View {
        let model = debrid.model
        GuidePage(title: Text("Ve todo al instante, aquí"),
                  step: step,
                  primary: model.ready ? Text("Seguir") : Text("Abrir Real-Debrid y copiar clave"),
                  secondary: model.ready ? nil : Text("Cuando quiera ver algo"),
                  next: { if model.ready { next() } else { opened = true; openURL(model.tokenURL) } },
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
                Text("Unos 3 € cada 15 días · una cuenta por persona").recipe(.secondary, color: DS.textMuted)
                // El campo no se quita mientras se revisa la clave (antes desaparecía y perdía el teclado).
                if case .ok(let status) = model.check {
                    GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text(verbatim: "\(status.username) · Premium"), detail: DebridWords.text(status))
                } else {
                    if canPaste || opened {
                        Button {
                            if let text = UIPasteboard.general.string { model.token = text; Task { await model.verify() } }
                        } label: { Label("Pegar tu clave", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity) }
                            .dsGlassButton().controlSize(.large)
                            .accessibilityIdentifier("debrid-paste")
                    }
                    if byHand {
                        DebridKeyField(debrid: model)   // dice lo que contestó Real-Debrid, con su arreglo
                    } else {
                        switch model.check {
                        case .checking: DSInlineProgress(text: Text("Revisando tu cuenta…"))
                        case .free: DSNotice(text: "Tu cuenta es gratuita: necesitas Premium para ver.", tone: .warn)
                        case .failed(let message): DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .warn)
                        default: EmptyView()
                        }
                        Button { withAnimation(DS.Motion.fade) { byHand = true } } label: { Text("Otra forma: escribirla").recipe(.footnote, color: DS.textMuted) }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("debrid-by-hand")
                    }
                    Button("Crear cuenta y pagar", systemImage: "arrow.up.right") { openURL(model.renewURL) }
                        .buttonStyle(.borderless).foregroundStyle(DS.textMuted)
                }
                DebridSharedOffer(debrid: model, carded: true)
            }
        }
        .sensoryFeedback(.success, trigger: model.ready)
        .task { await model.checkShared(); canPaste = UIPasteboard.general.hasStrings }
        // De regreso de la página de Real-Debrid: si copiaste algo, «Pegar tu clave» a la vista.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            canPaste = UIPasteboard.general.hasStrings
        }
    }
}

/// El campo de la clave con «Pegar» y lo que dijo Real-Debrid. Lo comparten la guía y Ajustes › Cuentas › «Cambiar clave».
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
                Button("Abrir real-debrid.com/apitoken", systemImage: "arrow.up.right") { openURL(debrid.tokenURL) }
                    .dsGlassButton()
                    .accessibilityIdentifier("debrid-open-apitoken")
            }
        }
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
