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
        List {
            if query.isEmpty {
                Section {
                    HowRow(symbol: "mic.fill", title: Text("En el control"),
                           detail: Text("Toca «En la TV», estira la hoja hacia arriba y toca el micrófono. Habla con calma: cuando terminas, se detiene solo y te contesta en voz alta."))
                    HowRow(symbol: "waveform", title: Text("Con Siri"),
                           detail: Text("Di «Oye Siri, habla con Orbital» y, cuando pregunte, la orden. Para lo de siempre, directo: «Oye Siri, pausa Orbital» o «Oye Siri, reanuda Orbital»."))
                    HowRow(symbol: "homepod.fill", title: Text("Con Alexa"),
                           detail: Text("Empieza con «Alexa, pídele a mi consola que…»: sin eso, Alexa intenta hacerlo ella sola."))
                } header: { Text("Dónde hablarle") } footer: {
                    Text("Las frases de abajo funcionan igual en los tres: las entiende tu Orbital.")
                }
                .listRowBackground(DS.surface)
                Section {
                    ForEach(Self.phoneOnly, id: \.say) { PhraseRow(say: $0.say, note: $0.note) }
                } header: { Label("Solo en el iPhone", systemImage: "iphone") } footer: {
                    Text("Descargar funciona aunque estés fuera de casa; lo demás necesita tu Orbital encendida.")
                }
                .listRowBackground(DS.surface)
            }
            ForEach(filtered) { group in
                Section {
                    ForEach(group.commands) { PhraseRow(say: $0.say, note: Text(verbatim: $0.note), noteEmpty: $0.note.isEmpty) }
                } header: { Label { Text(verbatim: group.title) } icon: { Image(systemName: group.icon) } }
                .listRowBackground(DS.surface)
            }
            if query.isEmpty {
                Section {
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
                } header: { Text("Si no funciona") }
                .listRowBackground(DS.surface)
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .searchable(text: $query, prompt: Text("Buscar una frase"))
        .navigationTitle("Lo que puedes decir").navigationBarTitleDisplayMode(.inline)
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

/// Una frase («pon el canal ADN 40») y para qué sirve. Mantener pulsado la copia.
private struct PhraseRow: View {
    let say: String
    let note: Text
    var noteEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: "«\(say)»").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
            if !noteEmpty { note.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement(children: .combine)
        .contextMenu { Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = say } }
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
