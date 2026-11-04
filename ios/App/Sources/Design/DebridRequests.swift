import SwiftUI

// Los pedidos a Real-Debrid (Fase 2): cómo va uno, la hoja de un pedido, «¿Qué es esto?» (O2) y la línea antes de pedir
// permiso de avisos (R10). Las piezas reciben los textos ya en el idioma de la app (`DebridRequestWords`); no leen la app.

/// R13: un pedido en palabras. Su ícono (cada estado el suyo, no solo color), cómo va, el renglón de abajo y, mientras
/// baja, la barra de avance. En la ficha, en «Tus pedidos» y en la hoja de un pedido.
struct DebridRequestStatus: View {
    let symbol: String
    let title: String
    var detail: String?
    /// 0…1 mientras baja; nil si no aplica.
    var fraction: Double?
    /// Un problema (rechazado, sin gente, atorado): el ícono en ámbar.
    var warn = false
    /// Listo (IOS-17): la palomita en verde, como todo lo que ya está.
    var ok = false

    var body: some View {
        IconBeside(symbol: symbol, color: warn ? DS.warning : ok ? DS.success : DS.textMuted) {
            Text(verbatim: title).recipe(.labelLarge, color: DS.text)
            if let detail { Text(verbatim: detail).recipe(.footnote, color: DS.textMuted).fixedSize(horizontal: false, vertical: true) }
            if let fraction { DSProgress(fraction: fraction).padding(.top, DS.Space.s1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Un ícono a la izquierda y su texto. El ícono va en una columna fija y centrado en ella, a la altura del primer renglón
/// (la línea base del título, como `Label` de iOS): antes iba arriba de su caja y cada símbolo, más ancho o más alto, quedaba
/// corrido (Fernando, 3 nov, probando la 1729: «los íconos están descentrados»). Con letra de accesibilidad el ícono crece
/// más que su columna y se encimaba con el título: ahí va arriba del texto (como `ParaTiB`).
struct IconBeside<Content: View>: View {
    let symbol: String
    var color: Color = DS.textMuted
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
                                                  : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DS.Space.s3))
        layout {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(color)
                .frame(width: typeSize.isAccessibilitySize ? nil : DS.SettingsLook.rowIcon, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Dónde, cómo y por qué de un pedido, en dos líneas sin jerga (Fernando, 3 nov, probando la 1729: «está descargando, pero
/// ¿descargando dónde? ¿cómo funciona esto?»): Real-Debrid lo baja en su nube, no en este iPhone (no ocupa espacio), y al
/// terminar arranca al instante. «te aviso» solo si este aparato va a avisar (IOS-8); «y en tu TV» solo con TV. Con
/// `explain`, «¿Qué es esto?» lleva a la explicación animada. En la hoja del pedido, en la ficha mientras baja y antes del
/// primer «Pedir a la nube».
struct DebridWhereLine: View {
    var notifies = true
    var tv = false
    /// RX2-A · arriba ya dice cuánto falta (la hoja del pedido): sin «Suele tardar…», que lo contradecía.
    var paced = false
    var explain: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            IconBeside(symbol: DS.Symbol.cloud) {
                Text("\(DeviceWords.text("La nube es tu Real-Debrid: lo baja por ti, no en este iPhone.", mac: "La nube es tu Real-Debrid: lo baja por ti, no en esta Mac."))\(Text(verbatim: " "))\(tv ? Text("Cuando termine, arranca al instante aquí y en tu TV.") : Text("Cuando termine, arranca al instante aquí."))\(Text(verbatim: paced ? "" : " "))\(paced ? Text(verbatim: "") : notifies ? Text("Suele tardar de minutos a horas; te aviso.") : Text("Suele tardar de minutos a horas."))")
                    .recipe(.footnote).fixedSize(horizontal: false, vertical: true)
            }
            if let explain {
                Button(action: explain) { Text("¿Qué es esto?").font(DS.TextRecipe.label.font).frame(minHeight: DS.Size.touchTarget) }
                    .buttonStyle(.borderless).tint(DS.accent)
                    .padding(.leading, DS.SettingsLook.rowIcon + DS.Space.s3)
                    .accessibilityIdentifier("debrid-where-explain")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-where")
    }
}

/// La hoja de un pedido (R3, R13, P2-B), la misma en la ficha y en «Tus pedidos»: cómo va, si los avisos están apagados, y
/// sus salidas: probar otra versión (solo cuando ayuda, `DebridRequestWords.suggestsOtherVersion`), abrir la ficha (desde
/// «Tus pedidos»), cancelar el pedido (preguntando antes, con «Seguir esperando») y «¿Qué es esto?». IOS-7, como la TV: lo
/// terminado no se cancela, se quita: listo, «Ver ahora» y «Quitar de tu Real-Debrid» (pregunta «¿Quitarlo de tu
/// Real-Debrid?»). IOS-19: lo de otra cuenta de Real-Debrid no se cancela ni se cambia desde aquí, y se dice por qué.
struct DebridRequestSheet: View {
    /// «The Office · T1 E2».
    let name: String
    let status: DebridRequestStatus
    /// «Lo pediste en iPhone · hace 6 min».
    let since: String
    /// Los avisos de la app están apagados: R3 lo dice («Avisos apagados · actívalos»).
    let notificationsOff: Bool
    let turnOnNotifications: () -> Void
    /// «Ver ahora» (listo).
    var watchNow: (() -> Void)?
    /// RX2-A · mientras baja en la nube, la que ya arranca en tus idiomas («Ver Inglés · 1080p, ya arranca») y, junto,
    /// «Esperar a que llegue» (cierra la hoja). nil sin otra al instante: solo cuánto lleva.
    var instead: (title: Text, action: () -> Void)?
    let otherVersion: (() -> Void)?
    /// «Abrir la ficha» (desde «Tus pedidos»); nil en la ficha misma.
    let openTitle: (() -> Void)?
    /// Ya terminó (listo o rechazado): «Quitar de tu Real-Debrid» en vez de «Cancelar pedido».
    var finished = false
    /// Es de otra cuenta de Real-Debrid: se dice por qué no se cancela.
    var otherAccount = false
    /// IOS-9 · «Muchas descargas activas»: su arreglo, tus descargas en real-debrid.com.
    var manageDownloads: URL?
    /// nil: es de otra cuenta de Real-Debrid y no se cancela desde aquí.
    let cancel: (() -> Void)?
    let explain: () -> Void
    let close: () -> Void
    /// Para `DebridWhereLine`: este aparato avisa y hay TV.
    var notifies = true
    var tv = false
    @State private var confirmingCancel = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSheetHeader(title: Text(verbatim: name), subtitle: Text(verbatim: since))
            status.padding(DS.Space.s4).dsCard(.card)
            if !finished { DebridWhereLine(notifies: notifies && !notificationsOff, tv: tv, paced: true) }   // dónde y cómo (3 nov)
            if notificationsOff && !finished {
                Button(action: turnOnNotifications) {
                    Label("Avisos apagados · actívalos", systemImage: "bell.slash").font(DS.TextRecipe.footnote.font)
                }
                .buttonStyle(.borderless).tint(DS.warning)
                .accessibilityIdentifier("debrid-notifications-off")
            }
            if otherAccount {
                Text("Lo pidieron con otra cuenta de Real-Debrid: se cancela desde ahí.").recipe(.footnote, color: DS.textMuted)
                    .accessibilityIdentifier("debrid-other-account")
            }
            VStack(spacing: DS.Space.s2) {
                if let watchNow {
                    Button(action: watchNow) { Label("Ver ahora", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .dsPrimaryButton(size: .large)
                        .accessibilityIdentifier("debrid-watch-now")
                }
                if let instead, !finished {
                    Button(action: instead.action) { Label { instead.title } icon: { Image(systemName: "play.fill") }.frame(maxWidth: .infinity) }
                        .dsPrimaryButton(size: .large)
                        .accessibilityIdentifier("debrid-instead")
                    Button(action: close) { Text("Esperar a que llegue").frame(maxWidth: .infinity) }
                        .dsSecondaryButton().controlSize(.large)
                        .accessibilityIdentifier("debrid-wait")
                }
                if let manageDownloads {
                    Link(destination: manageDownloads) { Label("Abrir tus descargas de Real-Debrid", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }
                        .dsPrimaryButton(size: .large)
                        .accessibilityIdentifier("debrid-manage-downloads")
                }
                if let otherVersion {
                    Button(action: otherVersion) { Label("Probar otra versión", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity) }
                        .dsPrimaryButton(size: .large)
                        .accessibilityIdentifier("debrid-other-version")
                }
                if let openTitle {
                    Button(action: openTitle) { Label("Abrir la ficha", systemImage: "info.circle").frame(maxWidth: .infinity) }
                        .dsSecondaryButton().controlSize(.large)
                        .accessibilityIdentifier("debrid-open-title")
                }
                if cancel != nil {
                    Button(role: .destructive) { confirmingCancel = true } label: {
                        Label(finished ? "Quitar de tu Real-Debrid" : "Cancelar pedido", systemImage: finished ? DS.Symbol.removeRequest : DS.Symbol.cancelRequest).frame(maxWidth: .infinity)
                    }
                    .dsSecondaryButton().controlSize(.large)
                    .accessibilityIdentifier(finished ? "debrid-remove-finished" : "debrid-cancel")
                }
                Button(action: explain) { Text("¿Qué es esto?").font(DS.TextRecipe.label.font).frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                    .buttonStyle(.borderless).tint(DS.accent)
                    .accessibilityIdentifier("debrid-explain")
            }
        }
        // Quien la abre la mide (`fittedSheet`): sin el margen de abajo, que ya pone la barra de inicio (dejaba un hueco al pie;
        // Fernando, 4 nov 2026, la 1774).
        .dsSheetContent(bottom: false)
        .debridCancelConfirmation(isPresented: $confirmingCancel, name: name, finished: finished) { cancel?() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-request-sheet")
    }
}

extension View {
    /// La misma pregunta en la ficha, en la hoja y en la lista (IOS-7): «¿Cancelar el pedido?» con «Seguir esperando» (sin
    /// eso iOS pone «Cancelar» junto a «Cancelar pedido»: dos «cancelar» opuestos) o, si ya terminó, «¿Quitarlo de tu
    /// Real-Debrid?» con «Quitar» y «Cancelar» (como la TV, `debridCancelMenu`).
    func debridCancelConfirmation(isPresented: Binding<Bool>, name: String, finished: Bool, perform: @escaping () -> Void) -> some View {
        confirmationDialog(finished ? Text("¿Quitarlo de tu Real-Debrid?") : Text("¿Cancelar el pedido?"), isPresented: isPresented, titleVisibility: .visible) {
            if finished {
                Button("Quitar", role: .destructive, action: perform)
                Button("Cancelar", role: .cancel) {}
            } else {
                Button("Cancelar pedido", role: .destructive, action: perform)
                Button("Seguir esperando", role: .cancel) {}
            }
        } message: {
            finished ? Text("\(name) se borra de tu cuenta. Para verlo otra vez habría que pedirlo de nuevo.") : Text(verbatim: name)
        }
    }
}

/// R10 · la línea antes de la pregunta de iOS, la primera vez que pides algo: para qué son los avisos (solo eso).
struct DebridNotifyPrompt: View {
    let allow: () -> Void
    let notNow: () -> Void
    /// Hay TV («arranca al instante aquí y en tu TV»).
    var tv = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSheetHeader(title: Text("Para avisarte cuando esté"),
                          subtitle: Text("Orbital te manda un aviso cuando la nube termine. Solo eso: nada de promociones."))
            DebridWhereLine(notifies: false, tv: tv)   // el primer «Pedir a la nube»: dónde y cómo, antes de pedir permiso
            VStack(spacing: DS.Space.s2) {
                Button(action: allow) { Label("Permitir avisos", systemImage: "bell").frame(maxWidth: .infinity) }
                    .dsPrimaryButton(size: .large)
                    .accessibilityIdentifier("debrid-allow-notifications")
                Button(action: notNow) { Text("Ahora no").frame(maxWidth: .infinity) }
                    .dsSecondaryButton().controlSize(.large)
            }
        }
        .dsSheetContent()
    }
}

/// RX3-A (3 nov, alineado con la guía de bienvenida) · «Así funciona», una sola vez: la primera vez que ves una versión «↓ Por
/// pedir» (en «Versión» o en la ficha). Los tres pasos animados, que no ocupa espacio en este aparato y «Entendido». Quién
/// la enseña y cómo recuerda que ya se vio: `DebridFlowIntroHost`.
struct DebridFlowIntro: View {
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSheetHeader(title: Text("Así funciona"),
                          subtitle: Text("La nube es tu Real-Debrid: lo que todavía no tiene, se lo pides y lo baja por ti."))
            DebridFlowStrip()
            IconBeside(symbol: "internaldrive") {
                DeviceWords.text("No ocupa espacio en este iPhone.", mac: "No ocupa espacio en esta Mac.").recipe(.secondary, color: DS.text)
            }
            Button(action: done) { Text("Entendido").frame(maxWidth: .infinity) }
                .dsPrimaryButton(size: .large)
                .accessibilityIdentifier("debrid-flow-intro-done")
        }
        .dsSheetContent()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-flow-intro")
    }
}

extension EnvironmentValues {
    /// R14-B · este aparato avisa también lo que pidió la TV con tu cuenta (`DebridRequestsModel.notifiesTVRequests`).
    @Entry var debridTVNotices = false
}
