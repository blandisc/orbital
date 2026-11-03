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
        IconBeside(symbol: symbol, color: warn ? DS.warning : DS.textMuted) {
            Text(verbatim: title).recipe(.labelLarge, color: DS.text)
            if let detail { Text(verbatim: detail).recipe(.footnote, color: DS.textMuted).fixedSize(horizontal: false, vertical: true) }
            if let fraction { DSProgress(fraction: fraction).padding(.top, DS.Space.s1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Un ícono a la izquierda y su texto. Con letra de accesibilidad el ícono crece más que su columna y se encimaba con el
/// título: ahí va arriba del texto (como `ParaTiB`).
struct IconBeside<Content: View>: View {
    let symbol: String
    var color: Color = DS.textMuted
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s2))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.s3))
        layout {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(color)
                .frame(width: typeSize.isAccessibilitySize ? nil : DS.SettingsLook.rowIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// La hoja de un pedido (R3, R13, P2-B), la misma en la ficha y en «Tus pedidos»: cómo va, si los avisos están apagados, y
/// sus salidas: probar otra versión (solo cuando ayuda, `DebridRequestWords.suggestsOtherVersion`), abrir la ficha (desde
/// «Tus pedidos»), cancelar el pedido (preguntando antes, con «Seguir esperando») y «¿Qué es esto?». Lo de otra cuenta de
/// Real-Debrid no se cancela ni se cambia desde aquí: solo «Abrir la ficha».
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
    /// «Abrir la ficha» (desde «Tus pedidos»); nil en la ficha misma.
    let openTitle: (() -> Void)?
    /// nil: es de otra cuenta de Real-Debrid y no se cancela desde aquí.
    let cancel: (() -> Void)?
    let explain: () -> Void
    let close: () -> Void
    @State private var confirmingCancel = false

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
                        .dsPrimaryButton(size: .large)
                        .accessibilityIdentifier("debrid-other-version")
                }
                if let openTitle {
                    Button(action: openTitle) { Label("Abrir la ficha", systemImage: "info.circle").frame(maxWidth: .infinity) }
                        .dsSecondaryButton().controlSize(.large)
                        .accessibilityIdentifier("debrid-open-title")
                }
                if cancel != nil {
                    Button(role: .destructive) { confirmingCancel = true } label: { Label("Cancelar pedido", systemImage: "xmark.circle").frame(maxWidth: .infinity) }
                        .dsSecondaryButton().controlSize(.large)
                        .accessibilityIdentifier("debrid-cancel")
                }
                Button(action: explain) { Text("¿Qué es esto?").font(DS.TextRecipe.label.font).frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                    .buttonStyle(.borderless).tint(DS.accent)
                    .accessibilityIdentifier("debrid-explain")
            }
        }
        .dsSheetContent()
        .confirmationDialog(Text("¿Cancelar el pedido?"), isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancelar pedido", role: .destructive) { cancel?() }
            // Sin esto iOS pone «Cancelar» junto a «Cancelar pedido»: dos «cancelar» que dicen cosas opuestas.
            Button("Seguir esperando", role: .cancel) {}
        } message: { Text(verbatim: name) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-request-sheet")
    }
}

/// O2 · «¿Qué es esto?»: tres tarjetas cortas donde surge la duda (en la ficha al pedir, en el reproductor al rendirse, en
/// «Tus pedidos»): los complementos buscan, Real-Debrid guarda, pedir es que lo baje. Y lo honesto: con la app cerrada, el
/// aviso puede tardar. Como lo explican Netflix, Plex e Infuse: en el momento, no en un manual.
struct DebridExplainer: View {
    /// De qué se explica: los pedidos (O2), Torrentio (T1), los complementos (C1) o tu cuenta de Real-Debrid (D1).
    enum Topic { case requests, torrentio, addons, realDebrid }
    var topic: Topic = .requests
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                DSSheetHeader(title: topic == .realDebrid ? Text("¿Qué es Real-Debrid?") : Text("¿Qué es esto?"), close: close)
                switch topic {
                case .requests: requests
                case .torrentio: torrentio
                case .addons: addons
                case .realDebrid: realDebrid
                }
            }
            .dsSheetContent()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-explainer")
    }

    @ViewBuilder private var requests: some View {
        card("magnifyingglass", Text("Tus complementos buscan dónde verlo"),
             Text("Preguntan en internet qué versiones hay de lo que elegiste: en qué idioma, de qué calidad y cuánta gente la comparte."))
        card("externaldrive.badge.checkmark", Text("Real-Debrid lo guarda"),
             Text("Es un servicio de pago que guarda películas y series en sus servidores. Lo que ya tiene arranca al instante."))
        card("arrow.down.circle", Text("Pedirlo es que lo baje por ti"),
             Text("Si todavía no lo tiene, se lo pides y lo baja. Tarda según cuánta gente lo comparte: de minutos a días. A veces no lo deja bajar (derechos de autor) y te lo decimos."))
        card("bell", Text("Te avisamos cuando esté"),
             Text("Con la app abierta lo sabes al momento. Con la app cerrada, iOS decide cuándo revisar: el aviso puede tardar un rato."))
    }

    @ViewBuilder private var torrentio: some View {
        card("magnifyingglass", Text("Torrentio es un buscador"),
             Text("Cuando eliges un título, revisa sitios de internet y te trae la lista de versiones que existen: idiomas, calidades, tamaños."))
        card("externaldrive.badge.checkmark", Text("Real-Debrid las sirve"),
             Text("Si ya tiene la versión, arranca en segundos («al instante»). Si no, la puede bajar por ti («por bajar»): de minutos a días."))
        card("slider.horizontal.3", Text("Aquí decides cuáles te enseña"),
             Text("Lo que elijas en esta página decide qué versiones salen en «Versión». Lo de fábrica ya está bien; cámbialo solo si algo te molesta."))
    }

    @ViewBuilder private var addons: some View {
        card("puzzlepiece.extension", Text("Los complementos buscan por ti"),
             Text("Cada uno sabe de algo: versiones de video, subtítulos o listas. Se les pregunta en el orden de la lista."))
        card("tortoise", Text("El que no contesta se salta"),
             Text("Tras dos fallos seguidos ya no se le espera. Se vuelve a probar cada vez más espaciado, hasta cada hora, y regresa solo."))
        card("shippingbox", Text("Vienen con Orbital o de tu Stremio"),
             Text("Torrentio, Comet y OpenSubtitles vienen con Orbital: se prenden y se apagan. Los traídos de tu Stremio también se quitan."))
    }

    @ViewBuilder private var realDebrid: some View {
        card("externaldrive.badge.checkmark", Text("Guarda copias por ti"),
             Text("Es un servicio de pago que guarda películas y series en sus servidores. Lo que ya tiene arranca en segundos."))
        card("arrow.down.circle", Text("Lo que no tiene, lo baja"),
             Text("Se lo pides y lo baja: de minutos a días, según cuánta gente lo comparte."))
        card("creditcard", Text("Cuesta y vence"),
             Text("Se paga por días en real-debrid.com y no se renueva solo. Te avisamos 14 días antes, 3 días antes y el día que vence."))
        card("key", Text("Tu clave"),
             Text("Conecta Orbital con tu cuenta. Vive en el llavero de este aparato y nunca se muestra completa."))
    }

    private func card(_ symbol: String, _ title: Text, _ body: Text) -> some View {
        IconBeside(symbol: symbol) {
            title.recipe(.labelLarge, color: DS.text)
            body.recipe(.secondary, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
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
