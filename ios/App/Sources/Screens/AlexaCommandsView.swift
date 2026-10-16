import SwiftUI
import UIKit

/// «Qué le puedes decir a Alexa» (Ajustes): todas las frases que entiende tu consola, por tema, con cómo pedírselo.
/// La lista es la misma que usa Orbital (alexa/commands.json, copiada en Resources/AlexaCommands.json): una prueba de
/// Orbital comprueba que cada frase llega de verdad a un comando. Las frases van en español (la skill es de México).
struct AlexaCommandsView: View {
    @State private var query = ""
    private let guide = AlexaGuide.load()

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    ForEach(guide.how) { PhraseRow(phrase: $0) }
                    Text("Si Alexa dice que no puede, empieza con «pídele a mi consola que…»: sin eso, Alexa intenta hacerlo ella sola.")
                        .font(DS.font(.xs)).foregroundStyle(DS.textFaint)
                } header: { Text("Cómo pedírselo") }
                .listRowBackground(DS.fill)
            }
            ForEach(filtered) { group in
                Section {
                    ForEach(group.commands) { PhraseRow(phrase: $0) }
                } header: { Label { Text(verbatim: group.title) } icon: { Image(systemName: group.icon) } }
                .listRowBackground(DS.fill)
            }
        }
        .scrollContentBackground(.hidden).background(TintedBackground())
        .searchable(text: $query, prompt: Text("Buscar una frase"))
        .navigationTitle("Qué le puedes decir a Alexa").navigationBarTitleDisplayMode(.inline)
    }

    private var filtered: [AlexaGuide.Group] {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return guide.groups }
        return guide.groups.compactMap { g in
            let hits = g.commands.filter { ($0.say + " " + $0.note).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(q) }
            return hits.isEmpty ? nil : AlexaGuide.Group(title: g.title, icon: g.icon, commands: hits)
        }
    }
}

/// Una frase («pon el canal ADN 40») y para qué sirve. Mantener pulsado la copia.
private struct PhraseRow: View {
    let phrase: AlexaGuide.Phrase

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: "«\(phrase.say)»").font(DS.font(.md, weight: .semibold)).foregroundStyle(DS.text)
            if !phrase.note.isEmpty { Text(verbatim: phrase.note).font(DS.font(.sm)).foregroundStyle(DS.textMuted) }
        }
        .padding(.vertical, DS.Space.s1)
        .accessibilityElement(children: .combine)
        .contextMenu { Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = phrase.say } }
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
