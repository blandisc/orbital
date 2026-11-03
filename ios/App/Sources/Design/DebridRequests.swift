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

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(warn ? DS.warning : DS.textMuted)
                .frame(width: DS.SettingsLook.rowIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: title).recipe(.labelLarge, color: DS.text)
                if let detail { Text(verbatim: detail).recipe(.footnote, color: DS.textMuted).fixedSize(horizontal: false, vertical: true) }
                if let fraction { DSProgress(fraction: fraction).padding(.top, DS.Space.s1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// La hoja de un pedido desde la ficha (R3, R13): cómo va, si los avisos están apagados, y sus salidas: probar otra
/// versión, cancelar el pedido y «¿Qué es esto?».
struct DebridRequestSheet: View {
    /// «The Office · T1 E2».
    let name: String
    let status: DebridRequestStatus
    /// «Lo pediste en iPhone · hace 6 min».
    let since: String
    /// Los avisos de la app están apagados: R3 lo dice («Avisos apagados · actívalos»).
    let notificationsOff: Bool
    let turnOnNotifications: () -> Void
    let otherVersion: (() -> Void)?
    let cancel: () -> Void
    let explain: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSheetHeader(title: Text(verbatim: name), subtitle: Text(verbatim: since), close: close)
            status.padding(DS.Space.s4).dsCard(.card)
            if notificationsOff {
                Button(action: turnOnNotifications) {
                    Label("Avisos apagados · actívalos", systemImage: "bell.slash").font(DS.TextRecipe.footnote.font)
                }
                .buttonStyle(.borderless).tint(DS.warning)
                .accessibilityIdentifier("debrid-notifications-off")
            }
            VStack(spacing: DS.Space.s2) {
                if let otherVersion {
                    Button(action: otherVersion) { Label("Probar otra versión", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity) }
                        .dsSecondaryButton().controlSize(.large)
                }
                Button(role: .destructive, action: cancel) { Label("Cancelar pedido", systemImage: "xmark.circle").frame(maxWidth: .infinity) }
                    .dsSecondaryButton().controlSize(.large)
                    .accessibilityIdentifier("debrid-cancel")
                Button(action: explain) { Text("¿Qué es esto?").font(DS.TextRecipe.label.font).frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                    .buttonStyle(.borderless).tint(DS.accent)
                    .accessibilityIdentifier("debrid-explain")
            }
        }
        .dsSheetContent()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-request-sheet")
    }
}

/// O2 · «¿Qué es esto?»: tres tarjetas cortas donde surge la duda (en la ficha al pedir, en el reproductor al rendirse, en
/// «Tus pedidos»): los complementos buscan, Real-Debrid guarda, pedir es que lo baje. Y lo honesto: con la app cerrada, el
/// aviso puede tardar. Como lo explican Netflix, Plex e Infuse: en el momento, no en un manual.
struct DebridExplainer: View {
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSSheetHeader(title: Text("¿Qué es esto?"), close: close)
                card("magnifyingglass", Text("Tus complementos buscan dónde verlo"),
                     Text("Preguntan en internet qué versiones hay de lo que elegiste: en qué idioma, de qué calidad y cuánta gente la comparte."))
                card("externaldrive.badge.checkmark", Text("Real-Debrid lo guarda"),
                     Text("Es un servicio de pago que guarda películas y series en sus servidores. Lo que ya tiene arranca al instante."))
                card("arrow.down.circle", Text("Pedirlo es que lo baje por ti"),
                     Text("Si todavía no lo tiene, se lo pides y lo baja. Tarda según cuánta gente lo comparte: de minutos a días. A veces no lo deja bajar (derechos de autor) y te lo decimos."))
                card("bell", Text("Te avisamos cuando esté"),
                     Text("Con la app abierta lo sabes al momento. Con la app cerrada, iOS decide cuándo revisar: el aviso puede tardar un rato."))
            }
            .dsSheetContent()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-explainer")
    }

    private func card(_ symbol: String, _ title: Text, _ body: Text) -> some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.textMuted)
                .frame(width: DS.SettingsLook.rowIcon).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                title.recipe(.labelLarge, color: DS.text)
                body.recipe(.secondary, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.s4).dsCard(.card)
    }
}

/// R10 · la línea antes de la pregunta de iOS, la primera vez que pides algo: para qué son los avisos (solo eso).
struct DebridNotifyPrompt: View {
    let allow: () -> Void
    let notNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSheetHeader(title: Text("Para avisarte cuando esté"),
                          subtitle: Text("Orbital te manda un aviso cuando Real-Debrid termine. Solo eso: nada de promociones."))
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
