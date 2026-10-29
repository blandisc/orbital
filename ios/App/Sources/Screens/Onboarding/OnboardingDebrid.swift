import SwiftUI
import UIKit
import OrbitalModels
import OrbitalAddons

/// 3 · Real-Debrid: qué es, cuánto cuesta y que no se renueva solo. «Ya tengo cuenta» o crearla en su web.
struct OnboardingDebridIntro: View {
    let step: (current: Int, total: Int)
    let signUp: URL
    let next: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        GuidePage(title: Text(verbatim: "Real-Debrid"),
                  message: Text("Es un servicio de pago que guarda los videos en sus servidores y te los entrega al instante, sin descargar nada de otras personas."),
                  step: step, primary: Text("Ya tengo cuenta"), secondary: Text("Crear cuenta en real-debrid.com"), next: next,
                  skip: { openURL(signUp) }) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Label("Se paga por adelantado, por días.", systemImage: "calendar")
                Label("No se renueva solo: Orbital te avisa antes de que se te acabe.", systemImage: "bell.badge")
                GuidePiece(symbol: "eurosign.circle", tint: DS.ListTint.trophy, title: Text("Cuánto cuesta"),
                           detail: Text("Desde unos 3 € por 15 días. El precio lo confirma su web."))
            }
            .font(DS.TextRecipe.body.font).foregroundStyle(DS.text)
        }
    }
}

/// 4 y 5 · Tu clave: abrir real-debrid.com/apitoken, copiar, pegar. Se comprueba al momento; con un problema (incompleta,
/// no la reconoce, cuenta gratuita) dice qué hacer y «Continuar» se queda apagado.
struct OnboardingDebridKey: View {
    let step: (current: Int, total: Int)
    let next: () -> Void
    @State private var debrid: ModelObserver<DebridModel>
    @Environment(\.openURL) private var openURL

    init(debrid: DebridModel, step: (current: Int, total: Int), next: @escaping () -> Void) {
        _debrid = State(wrappedValue: ModelObserver(debrid)); self.step = step; self.next = next
    }

    var body: some View {
        let model = debrid.model
        GuidePage(title: Text("Tu clave de Real-Debrid"), message: Text("Con ella Orbital puede pedir videos a tu cuenta."), step: step,
                  primaryEnabled: model.ready, next: next) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                GuideNumberedStep(number: 1, text: Text(verbatim: "real-debrid.com/apitoken")) {
                    Button("Abrir") { openURL(model.tokenURL) }.buttonStyle(.glass)
                }
                GuideNumberedStep(number: 2, text: Text("Copia el texto largo que aparece")) { EmptyView() }
                GuideNumberedStep(number: 3, text: Text("Vuelve aquí y pégalo")) { EmptyView() }
                DebridKeyField(debrid: model)
            }
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
                    .padding(DS.Space.s3).background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                    .accessibilityIdentifier("debrid-token")
                Button("Pegar", systemImage: "doc.on.clipboard") {
                    if let text = UIPasteboard.general.string { debrid.token = text; Task { await debrid.verify() } }
                }
                .buttonStyle(.glass)
            }
            switch debrid.check {
            case .idle: if !debrid.token.isEmpty { Button("Comprobar") { Task { await debrid.verify() } }.buttonStyle(.glass) }
            case .checking: ProgressView()
            case .ok(let status):
                GuidePiece(symbol: "checkmark.circle.fill", tint: DS.success, title: Text(verbatim: "\(status.username) · Premium"),
                           detail: DebridWords.text(status))
            case .free:
                DSNotice(text: "Tu cuenta es gratuita: necesitas Premium para ver.", tone: .warn)
                Button("Hacerla Premium") { openURL(debrid.renewURL) }.buttonStyle(.glass)
            case .failed(let message):
                DSNotice(verbatim: AppEnvironment.shared.message(message), tone: .error)
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
        case .expired: return Text("Venció hace \(String(days)) días")
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

/// 6 · Complementos: ya vienen elegidos; quien no sabe qué es solo toca «Continuar».
struct OnboardingAddons: View {
    let step: (current: Int, total: Int)
    let next: () -> Void
    @State private var addons: ModelObserver<AddonsModel>

    init(addons: AddonsModel, step: (current: Int, total: Int), next: @escaping () -> Void) {
        _addons = State(wrappedValue: ModelObserver(addons)); self.step = step; self.next = next
    }

    var body: some View {
        let model = addons.model
        GuidePage(title: Text("De dónde salen las versiones"),
                  message: Text("Los complementos son buscadores: encuentran versiones de cada película y Real-Debrid te las entrega."),
                  step: step, next: next) {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                Text("Ya dejamos listos estos").font(DS.TextRecipe.eyebrow.font).foregroundStyle(DS.textMuted).textCase(.uppercase)
                ForEach(model.items) { addon in
                    Toggle(isOn: Binding(get: { addon.enabled }, set: { on in Task { await model.setEnabled(addon.id, on) } })) {
                        let what = AddonsModel.summary(addon)
                        AddonLabel(name: addon.name, usesDebrid: what.usesDebrid, subtitles: what.subtitles, imported: what.imported)
                    }
                    .padding(DS.Space.s3).background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
                Text("Puedes cambiarlos cuando quieras en Ajustes › Complementos.").font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            }
        }
        .task { await model.prepare() }
    }
}
