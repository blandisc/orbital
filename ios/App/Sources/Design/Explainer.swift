import SwiftUI
import OrbitalCore

// «¿Qué es esto?» (O2, T1, C1, D1): las hojas que explican donde surge la duda. Fernando, 3 nov, probando la 1729: «le falta
// espacio, se corta el texto abajo», «hazlo más gráfico, con algo animado» y «los íconos están descentrados; más grandes y con
// color». Una sola pieza para las cuatro: tarjetas con su cuadro de color (`DSExplainerCard`) y, en Real-Debrid y los pedidos,
// los tres pasos animados (`DebridFlowStrip`). La hoja mide lo que trae y, si no cabe, se desplaza (`fittedScrollSheet`).

/// El cuadro de color de una idea: el símbolo centrado en su color (de `DS.ListTint`, como los íconos de las listas) sobre
/// ese mismo color tenue. Crece con la letra.
struct DSIconTile: View {
    let symbol: String
    let tint: Color
    var side: CGFloat = DS.Explainer.tile
    @ScaledMetric(relativeTo: .title2) private var scale: CGFloat = 1

    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(tint.opacity(DS.Explainer.tileFill))
            .frame(width: side * min(scale, DS.Explainer.maxScale), height: side * min(scale, DS.Explainer.maxScale))
            .overlay {
                Image(systemName: symbol).font(DS.TextRecipe.section.font).symbolRenderingMode(.hierarchical).foregroundStyle(tint)
            }
            .accessibilityHidden(true)
    }
}

/// Una idea de «¿Qué es esto?»: su cuadro de color a la izquierda, centrado con el texto, el título y una explicación corta.
/// Con letra de accesibilidad el cuadro va arriba (no aprieta el texto en una columna angosta).
struct DSExplainerCard: View {
    let symbol: String
    let tint: Color
    let title: Text
    let detail: Text
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s3))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.s4))
        layout {
            DSIconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                title.recipe(.cardTitle, color: DS.text)
                detail.recipe(.secondary, color: DS.textMuted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Space.s4)
        .dsCard(.card)
        .accessibilityElement(children: .combine)
    }
}

/// «Tú lo pides → Real-Debrid lo baja → Arranca al instante»: tres pasos que se encienden uno tras otro, en bucle. Con
/// «Reducir movimiento», los tres quietos y encendidos. El color es el de cada paso, nunca el turquesa (no es la voz).
struct DebridFlowStrip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var step = 0

    private let steps: [(symbol: String, tint: Color, label: LocalizedStringKey)] = [
        ("hand.tap.fill", DS.ListTint.library, "Tú lo pides"),
        ("arrow.down.circle.fill", DS.ListTint.calendar, "Real-Debrid lo baja"),
        ("play.fill", DS.ListTint.flame, "Arranca al instante"),
    ]

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s3))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.s1))
        layout {
            ForEach(steps.indices, id: \.self) { i in
                if i > 0 && !typeSize.isAccessibilitySize {
                    Image(systemName: "chevron.forward").font(DS.TextRecipe.label.font)
                        .foregroundStyle(lit(i) ? DS.text : DS.textFaint)
                        .frame(height: DS.Explainer.flowTile).accessibilityHidden(true)
                }
                node(i)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Space.s4)
        .dsCard(.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Tú lo pides, Real-Debrid lo baja y arranca al instante"))
        .accessibilityIdentifier("debrid-flow")
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: DS.Explainer.step)
                withAnimation(DS.Motion.spring(reduceMotion)) { step = (step + 1) % steps.count }
            }
        }
    }

    /// Encendido: el paso de ahora y los de antes (lo pedido ya está pedido); con «Reducir movimiento», todos.
    private func lit(_ i: Int) -> Bool { reduceMotion || i <= step }

    @ViewBuilder private func node(_ i: Int) -> some View {
        let item = steps[i]
        let layout = typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(spacing: DS.Space.s3)) : AnyLayout(VStackLayout(spacing: DS.Space.s2))
        layout {
            DSIconTile(symbol: item.symbol, tint: lit(i) ? item.tint : DS.textFaint, side: DS.Explainer.flowTile)
                .scaleEffect(!reduceMotion && i == step ? 1 : DS.Explainer.restScale)
                .symbolEffect(.bounce, value: reduceMotion ? 0 : (i == step ? step : -1))
            Text(item.label).recipe(.label, color: lit(i) ? DS.text : DS.textMuted)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity)
    }
}

/// O2 · «¿Qué es esto?»: tarjetas cortas donde surge la duda (en la ficha al pedir, en el reproductor al rendirse, en
/// «Tus pedidos»): los complementos buscan, Real-Debrid guarda, pedir es que lo baje. Y lo honesto: con la app cerrada, el
/// aviso puede tardar. Como lo explican Netflix, Plex e Infuse: en el momento, no en un manual. Se mide sola
/// (`fittedScrollSheet`): quien la abre no le pone alturas.
struct DebridExplainer: View {
    /// De qué se explica: los pedidos (O2), Torrentio (T1), los complementos (C1) o tu cuenta de Real-Debrid (D1).
    enum Topic { case requests, torrentio, addons, realDebrid }
    var topic: Topic = .requests
    let close: () -> Void
    /// R14-B · este aparato también avisa lo que pidió la TV (solo el iPhone; lo pone la app con `debridTVNotices`).
    @Environment(\.debridTVNotices) private var tvNotices

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                DSSheetHeader(title: topic == .realDebrid ? Text("¿Qué es Real-Debrid?") : Text("¿Qué es esto?"), close: close)
                    .padding(.bottom, DS.Space.s1)
                switch topic {
                case .requests: DebridFlowStrip(); requests
                case .torrentio: torrentio
                case .addons: addons
                case .realDebrid: DebridFlowStrip(); realDebrid
                }
            }
            .dsSheetContent()
        }
        .scrollBounceBehavior(.basedOnSize)
        .fittedScrollSheet()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-explainer")
    }

    @ViewBuilder private var requests: some View {
        card("magnifyingglass", DS.ListTint.library, Text("Tus complementos buscan dónde verlo"),
             Text("Preguntan en internet qué versiones hay de lo que elegiste: en qué idioma, de qué calidad y cuánta gente la comparte."))
        card("externaldrive.fill.badge.checkmark", DS.ListTint.series, Text("Real-Debrid lo guarda"),
             Text("Es un servicio de pago que guarda películas y series en sus servidores. Lo que ya tiene arranca al instante."))
        card("arrow.down.circle.fill", DS.ListTint.calendar, Text("Pedirlo es que lo baje por ti"),
             Text("Si todavía no lo tiene, se lo pides y lo baja. Tarda según cuánta gente lo comparte: de minutos a días. A veces no lo deja bajar (derechos de autor) y te lo decimos."))
        card("bell.fill", DS.ListTint.trend, Text("Te avisamos cuando esté"),
             Text("Con la app abierta lo sabes al momento. Con la app cerrada, iOS decide cuándo revisar: el aviso puede tardar un rato."))
        // R14-B: lo que pides en la TV también avisa aquí, cuando la app puede mirar (solo en el iPhone).
        if tvNotices {
            card("tv.fill", DS.ListTint.spark, Text("También lo que pides en la TV"),
                 Text("Si lo pediste en la TV con tu misma cuenta, este iPhone te avisa cuando lo note: al abrir la app o cuando iOS lo deja revisar, a veces minutos o una hora después."))
        }
    }

    @ViewBuilder private var torrentio: some View {
        card("magnifyingglass", DS.ListTint.library, Text("Torrentio es un buscador"),
             Text("Cuando eliges un título, revisa sitios de internet y te trae la lista de versiones que existen: idiomas, calidades, tamaños."))
        card("externaldrive.fill.badge.checkmark", DS.ListTint.series, Text("Real-Debrid las sirve"),
             Text("Si ya tiene la versión, arranca en segundos («al instante»). Si no, la puede bajar por ti («por bajar»): de minutos a días."))
        card("slider.horizontal.3", DS.ListTint.spark, Text("Aquí decides cuáles te enseña"),
             Text("Lo que elijas en esta página decide qué versiones salen en «Versión». Lo de fábrica ya está bien; cámbialo solo si algo te molesta."))
    }

    @ViewBuilder private var addons: some View {
        card("puzzlepiece.extension.fill", DS.ListTint.addon, Text("Los complementos buscan por ti"),
             Text("Cada uno sabe de algo: versiones de video, subtítulos o listas. Se les pregunta en el orden de la lista."))
        card("tortoise.fill", DS.ListTint.flame, Text("El que no contesta se salta"),
             Text("Tras dos fallos seguidos ya no se le espera. Se vuelve a probar cada vez más espaciado, hasta cada hora, y regresa solo."))
        card("shippingbox.fill", DS.ListTint.trophy, Text("Vienen con Orbital o de tu Stremio"),
             Text("Torrentio y Comet vienen con Orbital: se prenden y se apagan. Los traídos de tu Stremio también se quitan. Los subtítulos de internet ya vienen con Orbital: están en Ajustes › Idioma y subtítulos."))
    }

    @ViewBuilder private var realDebrid: some View {
        card("externaldrive.fill.badge.checkmark", DS.ListTint.series, Text("Guarda copias por ti"),
             Text("Es un servicio de pago que guarda películas y series en sus servidores. Lo que ya tiene arranca en segundos."))
        card("arrow.down.circle.fill", DS.ListTint.calendar, Text("Lo que no tiene, lo baja"),
             Text("Se lo pides y lo baja: de minutos a días, según cuánta gente lo comparte."))
        card("creditcard.fill", DS.ListTint.bookmark, Text("Cuesta y vence"),
             Text("Se paga por días en real-debrid.com y no se renueva solo. Te avisamos 14 días antes, 3 días antes y el día que vence."))
        card("key.fill", DS.ListTint.trophy, Text("Tu clave"),
             Text("Conecta Orbital con tu cuenta. Vive en el llavero de este aparato y nunca se muestra completa."))
    }

    private func card(_ symbol: String, _ tint: Color, _ title: Text, _ body: Text) -> some View {
        DSExplainerCard(symbol: symbol, tint: tint, title: title, detail: body)
    }
}
