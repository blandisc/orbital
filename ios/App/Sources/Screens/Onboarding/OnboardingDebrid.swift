import SwiftUI
import UIKit
import OrbitalModels
import OrbitalAddons

/// 4 · Ver aquí mismo (D1, Fernando, 3 nov 2026): qué es Real-Debrid con los tres pasos de la nube (la misma pieza que la
/// tarjeta «Así funciona» de las versiones), cuánto cuesta, que es una cuenta por persona y que no ocupa espacio. Pagar no
/// detiene la guía: «Cuando quiera ver algo» sigue, y la hoja de conectar sale la primera vez que tocas «Ver». Al volver de
/// la página de Real-Debrid, la clave pegada se revisa sola. Conectar con un código (sin copiar ni pegar) llega cuando se
/// pruebe con una cuenta; mientras, la clave con sus tres pasos.
struct OnboardingSeeHere: View {
    let step: (current: Int, total: Int)
    let back: (() -> Void)?
    let next: () -> Void
    let skip: () -> Void
    @State private var guide: ModelObserver<OnboardingModel>
    @State private var debrid: ModelObserver<DebridModel>
    @State private var connecting = false
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    init(guide: OnboardingModel, step: (current: Int, total: Int), back: (() -> Void)?, next: @escaping () -> Void, skip: @escaping () -> Void) {
        _guide = State(wrappedValue: ModelObserver(guide)); _debrid = State(wrappedValue: ModelObserver(guide.debrid))
        self.step = step; self.back = back; self.next = next; self.skip = skip
        _connecting = State(initialValue: guide.answers[.debrid] == .has)
    }

    var body: some View {
        let model = debrid.model
        GuidePage(title: Text("Ver aquí mismo, sin esperar"),
                  message: Text("Real-Debrid es un servicio de pago que guarda los videos en su nube y te los entrega al instante."),
                  step: step,
                  primary: connecting ? Text("Continuar") : Text("Conectar ahora"),
                  primaryEnabled: !connecting || model.ready,
                  secondary: Text("Cuando quiera ver algo"),
                  next: { if connecting { next() } else { withAnimation(DS.Motion.fade) { connecting = true } } },
                  skip: next, skipGuide: skip, back: back) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DebridFlowStrip()
                if connecting {
                    GuideNumberedStep(number: 1, text: Text(verbatim: "real-debrid.com/apitoken")) {
                        Button("Abrir") { openURL(model.tokenURL) }.dsGlassButton()
                    }
                    GuideNumberedStep(number: 2, text: Text("Copia el texto largo que aparece")) { EmptyView() }
                    GuideNumberedStep(number: 3, text: Text("Vuelve aquí y pégalo")) { EmptyView() }
                    DebridKeyField(debrid: model)
                    DebridSharedOffer(debrid: model, carded: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.s3) {
                        GuidePiece(symbol: "calendar", tint: DS.ListTint.watching, title: Text("Desde unos 3 € cada 15 días"),
                                   detail: Text("Lo pagas en su página, por adelantado. No se renueva solo: Orbital te avisa antes."))
                        GuidePiece(symbol: "person.fill", tint: DS.ListTint.series, title: Text("Una cuenta por persona"),
                                   detail: Text("Si dos la usan a la vez, Real-Debrid la corta."))
                        GuidePiece(symbol: "iphone", tint: DS.ListTint.library, title: Text("No ocupa espacio"),
                                   detail: Text("El video llega desde la nube mientras lo ves."))
                    }
                    Button("Crear cuenta y pagar", systemImage: "arrow.up.right") { openURL(model.renewURL) }
                        .buttonStyle(.borderless).foregroundStyle(DS.textMuted)
                }
            }
        }
        .task { await model.checkShared() }
        // De regreso de la página de Real-Debrid: si ya pegaste la clave, se revisa sola.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, connecting, !model.token.isEmpty, !model.ready else { return }
            Task { await model.verify() }
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
