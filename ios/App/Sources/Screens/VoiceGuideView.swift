import SwiftUI
import UIKit

/// «Lo que puedes decir» (Ajustes › Voz, y el «?» junto al micrófono del control): dónde hablarle a tu Orbital (el
/// micrófono del control, Siri, Alexa), lo que solo hace el iPhone, todas las frases que entiende tu consola por tema y qué
/// hacer si no funciona. Las frases de la consola son las mismas para los tres (`voice.py`), así que la lista es la de
/// Alexa (alexa/commands.json, copiada en Resources/AlexaCommands.json): una prueba de Orbital comprueba que cada frase llega
/// de verdad a un comando. Las frases van en español (la consola habla español).
struct VoiceGuideView: View {
    @State private var query = ""
    @Environment(\.openURL) private var openURL
    private let guide = AlexaGuide.load()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                    if query.isEmpty {
                        // Dónde hablarle: tres tarjetas, cada una con la frase para empezar en su globo.
                        VStack(alignment: .leading, spacing: DS.Space.s3) {
                            DSSectionHead(title: "Dónde hablarle", meta: Text("Las frases de abajo funcionan igual en los tres."))
                            WhereCard(symbol: "mic.fill", tint: DS.ListTint.spark, title: Text("En el control"), starter: "pon The Office",
                                      detail: Text("Estira el control hacia arriba y toca «Dile a Orbital». Se detiene solo cuando terminas."))
                            WhereCard(symbol: "waveform", tint: DS.ListTint.bookmark, title: Text("Con Siri"), starter: "Oye Siri, habla con Orbital",
                                      detail: Text("Y cuando pregunte, la orden. Directo: «Oye Siri, pausa Orbital»."))
                            WhereCard(symbol: "homepod.fill", tint: DS.ListTint.library, title: Text("Con Alexa"), starter: "Alexa, pídele a Orbital que…",
                                      detail: Text("Sin «pídele a Orbital», Alexa intenta hacerlo ella sola."))
                        }
                        // Los temas, para saltar sin bajar todo.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Space.s2) {
                                topicChip("Solo en el iPhone", id: "phone", proxy: proxy)
                                ForEach(guide.groups) { g in topicChip(g.title, id: g.id, proxy: proxy, verbatim: true) }
                                topicChip("Si no funciona", id: "help", proxy: proxy)
                            }
                        }
                        .padding(.horizontal, -DS.Space.gutter).contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                        topic(Text("Solo en el iPhone"), meta: Text("Descargar funciona aunque estés fuera de casa.")) {
                            ForEach(Self.phoneOnly, id: \.say) { PhraseRow(say: $0.say, note: $0.note) }
                        }
                        .id("phone")
                    }
                    ForEach(filtered) { group in
                        topic(Text(verbatim: group.title)) {
                            ForEach(group.commands) { PhraseRow(say: $0.say, note: Text(verbatim: $0.note), noteEmpty: $0.note.isEmpty) }
                        }
                        .id(group.id)
                    }
                    if query.isEmpty {
                        topic(Text("Si no funciona")) {
                            HowRow(symbol: "text.bubble", title: Text("Revisa lo que entendió"),
                                   detail: Text("Bajo la respuesta sale «Entendí: …». Si el nombre salió mal, dilo más despacio o búscalo con «Escribir»."))
                            HowRow(symbol: "rectangle.stack", title: Text("Cuando hay varias"),
                                   detail: Text("Si dices «pon Dune» y hay más de una, salen bajo el micrófono con su póster: toca la que es."))
                            HowRow(symbol: "wifi", title: Text("Si contesta que no encuentra tu Orbital"),
                                   detail: Text("El iPhone tiene que estar en la misma red que la consola (o con Tailscale), y Orbital abierta en la TV."))
                            HowRow(symbol: "mic.slash", title: Text("Si no te escucha"),
                                   detail: Text("Permite el micrófono y el reconocimiento de voz para Orbital."))
                            Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                                Label("Abrir los permisos de Orbital", systemImage: "gear")
                            }
                            .buttonStyle(.glass)
                        }
                        .id("help")
                    }
                }
                .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s4).padding(.bottom, DS.Space.s14)
            }
        }
        .tint(DS.accent)
        .background(Backdrop())
        .searchable(text: $query, prompt: Text("Buscar una frase"))
        .navigationTitle("Lo que puedes decir").navigationBarTitleDisplayMode(.inline)
    }

    /// Un tema: su encabezado (el de toda la app) y sus frases en una tarjeta.
    private func topic<Content: View>(_ title: Text, meta: Text? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title, meta: meta)
            VStack(alignment: .leading, spacing: DS.Space.s3) { content() }
                .padding(DS.Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
    }

    private func topicChip(_ title: String, id: String, proxy: ScrollViewProxy, verbatim: Bool = false) -> some View {
        Button { withAnimation { proxy.scrollTo(id, anchor: .top) } } label: {
            (verbatim ? Text(verbatim: title) : Text(LocalizedStringKey(title))).lineLimit(1)
        }
        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
    }

    /// Lo que atiende el iPhone sin preguntarle a la consola (`VoiceRouter`): descargar, seguir aquí, las teclas y el inglés.
    private static let phoneOnly: [(say: String, note: Text)] = [
        ("descárgalo", Text("Descarga en el iPhone lo que se ve en la TV.")),
        ("descarga Dune", Text("Busca la película y la descarga. Una serie, desde su ficha.")),
        ("síguela en mi iPhone", Text("Sigue aquí lo que se ve en la TV, donde iba.")),
        ("atrás · arriba · aceptar · menú", Text("Las teclas del mando, dichas solas.")),
        ("play The Office · pause · next episode", Text("Lo básico también en inglés.")),
    ]

    private var filtered: [AlexaGuide.Group] {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return guide.groups }
        return guide.groups.compactMap { g in
            let hits = g.commands.filter { ($0.say + " " + $0.note).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q) }
            return hits.isEmpty ? nil : AlexaGuide.Group(title: g.title, icon: g.icon, commands: hits)
        }
    }
}

/// Un lugar o un consejo de la guía: su símbolo, el nombre y cómo.
private struct HowRow: View {
    let symbol: String
    let title: Text
    let detail: Text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Image(systemName: symbol).font(DS.TextRecipe.secondary.font).foregroundStyle(DS.accent)
                .frame(width: DS.Size.iconColumn)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                title.font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
                detail.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
            }
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement(children: .combine)
    }
}

/// Una frase («pon el canal ADN 40») en su globo, y para qué sirve debajo. Mantener pulsado la copia.
private struct PhraseRow: View {
    let say: String
    let note: Text
    var noteEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: "«\(say)»").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
                .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
                .background(DS.fill, in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.lg, bottomLeadingRadius: DS.Space.s1,
                                                                 bottomTrailingRadius: DS.Radius.lg, topTrailingRadius: DS.Radius.lg, style: .continuous))
            if !noteEmpty { note.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).padding(.leading, DS.Space.s1) }
        }
        .accessibilityElement(children: .combine)
        .contextMenu { Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = say } }
    }
}

/// Dónde hablarle: el ícono en su color, el nombre, la frase para empezar en su globo y cómo.
private struct WhereCard: View {
    let symbol: String
    let tint: Color
    let title: Text
    let starter: String
    let detail: Text

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.s3) {
            Image(systemName: symbol).font(DS.TextRecipe.section.font).foregroundStyle(tint).frame(width: DS.Size.iconColumn * 3 / 2)
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                title.recipe(.cardTitle).fontWeight(.semibold)
                Text(verbatim: "«\(starter)»").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.text)
                    .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s1)
                    .background(tint.opacity(DS.VoiceGuide.starterFill), in: Capsule())
                detail.recipe(.footnote)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.s4)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// La lista de frases (Resources/AlexaCommands.json).
struct AlexaGuide: Decodable {
    struct Phrase: Decodable, Identifiable { let say: String; let note: String; var id: String { say } }
    struct Group: Decodable, Identifiable { let title: String; let icon: String; let commands: [Phrase]; var id: String { title } }
    let how: [Phrase]
    let groups: [Group]

    static func load() -> AlexaGuide {
        guard let url = Bundle.main.url(forResource: "AlexaCommands", withExtension: "json"), let data = try? Data(contentsOf: url),
              let guide = try? JSONDecoder().decode(AlexaGuide.self, from: data) else { return AlexaGuide(how: [], groups: []) }
        return guide
    }
}
