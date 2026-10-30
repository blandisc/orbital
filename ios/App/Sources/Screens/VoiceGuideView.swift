import SwiftUI
import UIKit

/// «Lo que puedes decir» (Ajustes › Voz, y el «?» junto al micrófono del control), de arriba a abajo: «Ahora» (las tres
/// frases de este momento, si las hay), «Lo esencial» (las frases de `core` que faltan, en tarjetas de dos en dos), dónde
/// hablarle (el micrófono, Siri, Alexa) y un renglón que abre todas las frases por tema, cómo pedirlo, lo que solo hace el
/// iPhone y qué hacer si no funciona. La búsqueda busca en todo. Las frases de la consola son las mismas para los tres
/// (`voice.py`), así que la lista es la de Alexa (alexa/commands.json, copiada en Resources/AlexaCommands.json): una prueba
/// de Orbital comprueba que cada frase llega de verdad a un comando. Las frases van en español (la consola habla español).
///
/// `hints`: las frases del momento (`/api/voice/hints`); sin ellas no sale «Ahora». `nowTitle`: lo que se ve en la TV
/// («Ahora, viendo The Office»). `onSay`: tocar una frase la manda (quien abre la guía la manda a la tele y la cierra); sin
/// él (desde Ajustes) tocar solo la resalta. Mantener pulsada una frase enseña qué hace.
struct VoiceGuideView: View {
    let hints: [String]
    let nowTitle: String?
    let onSay: ((String) -> Void)?

    @State private var query = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    private let guide = AlexaGuide.load()

    /// A mano: con propiedades privadas, el inicializador automático sería privado y no se vería desde el control ni Ajustes.
    init(hints: [String] = [], nowTitle: String? = nil, onSay: ((String) -> Void)? = nil) {
        self.hints = hints; self.nowTitle = nowTitle; self.onSay = onSay
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                if query.isEmpty {
                    if !nowPhrases.isEmpty { now }
                    essentials
                    whereToSpeak
                    NavigationLink { VoiceTopicsView(guide: guide, onSay: onSay) } label: { moreRow }
                        .buttonStyle(.plain).pointerHover(.lift)
                } else {
                    VoiceGuideResults(guide: guide, query: query, onSay: onSay)
                }
            }
            .frame(maxWidth: DS.TitleAction.readableWidth, alignment: .leading)   // en el iPad, a un ancho de lectura
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s4).padding(.bottom, DS.Space.s14)
        }
        .tint(DS.accent)
        .background(Backdrop())
        .searchable(text: $query, prompt: Text("Buscar una frase"))
        .navigationTitle("Lo que puedes decir").navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Ahora

    /// Las frases del momento, con su nota si es de las esenciales (las de la tele siempre lo son).
    private var nowPhrases: [AlexaGuide.Phrase] {
        hints.map { say in guide.core.first { VoiceGuideText.same($0.say, say) } ?? AlexaGuide.Phrase(say: say, note: "") }
    }

    private var nowHeader: Text {
        if let nowTitle, !nowTitle.isEmpty { Text("Ahora, viendo \(nowTitle)") } else { Text("Ahora") }
    }

    private var now: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            nowHeader.recipe(.eyebrow, color: DS.eyebrow).lineLimit(2)
            .accessibilityAddTraits(.isHeader)
            cardRow(nowPhrases) { PhraseCard(phrase: $0, style: .now, onSay: onSay) }
        }
    }

    // MARK: Lo esencial

    /// Las de `core` que no salieron ya en «Ahora».
    private var essentialPhrases: [AlexaGuide.Phrase] {
        guide.core.filter { phrase in !hints.contains { VoiceGuideText.same($0, phrase.say) } }
    }

    private var essentials: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text("Lo esencial"), level: .section)
            // De dos en dos; si quedan impares, la última va a lo ancho. Con letra muy grande, una por renglón.
            let items = essentialPhrases
            let perRow = typeSize.isAccessibilitySize ? 1 : 2
            VStack(spacing: DS.Space.s2) {
                ForEach(Array(stride(from: 0, to: items.count, by: perRow)), id: \.self) { start in
                    cardRow(Array(items[start..<min(start + perRow, items.count)])) { PhraseCard(phrase: $0, style: .essential, onSay: onSay) }
                }
            }
            (onSay == nil ? Text("Mantén una para ver qué hace") : Text("Toca una para mandarla a la tele · mantén para ver qué hace"))
                .recipe(.footnote)
        }
    }

    // MARK: Dónde hablarle

    private var whereToSpeak: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: Text("Dónde hablarle"), level: .section)
            let tiles = [
                WhereTile(symbol: "mic.fill", tint: DS.ListTint.spark, title: Text("Aquí"), detail: Text("Toca el micrófono del control")),
                WhereTile(symbol: "waveform", tint: DS.ListTint.bookmark, title: Text("Siri"), detail: Text("«Oye Siri, pausa en Orbital»")),
                WhereTile(symbol: "homepod.fill", tint: DS.ListTint.library, title: Text("Alexa"), detail: Text("«Alexa, pídele a mi consola…»")),
            ]
            cardRow(Array(tiles.indices)) { tiles[$0] }
        }
    }

    // MARK: Más frases

    private var moreRow: some View {
        HStack(spacing: DS.Space.s3) {
            Image(systemName: "text.bubble").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.accent).frame(width: DS.Size.iconColumn)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text("Más frases, por tema").recipe(.cardTitle)
                Text("\(guide.phraseCount) frases · cómo pedirlo · si no funciona").recipe(.footnote)
            }
            Spacer(minLength: DS.Space.s2)
            Image(systemName: "chevron.forward").font(DS.TextRecipe.footnote.font.weight(.semibold)).foregroundStyle(DS.textFaint)
        }
        .padding(DS.Space.s4).frame(minHeight: DS.Size.touchTarget)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
    }

    /// Unas tarjetas en fila, todas del mismo alto (crecen con la letra, no se cortan). Con letra muy grande, una debajo de otra.
    private func cardRow<Item: Hashable, Card: View>(_ items: [Item], @ViewBuilder card: @escaping (Item) -> Card) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: DS.Space.s2))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: DS.Space.s2))
        return layout {
            ForEach(items, id: \.self) { card($0).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Todas las frases: los temas para saltar, cómo pedirlo, lo que solo hace el iPhone, cada tema y qué hacer si no funciona.
private struct VoiceTopicsView: View {
    let guide: AlexaGuide
    let onSay: ((String) -> Void)?

    @State private var query = ""
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Editorial.sectionGap) {
                    if query.isEmpty {
                        // Los temas, para saltar sin bajar todo.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Space.s2) {
                                topicChip("Cómo pedirlo", id: "how", proxy: proxy)
                                topicChip("Solo en el iPhone", id: "phone", proxy: proxy)
                                ForEach(guide.groups) { g in topicChip(g.title, id: g.id, proxy: proxy, verbatim: true) }
                                topicChip("Si no funciona", id: "help", proxy: proxy)
                            }
                        }
                        .padding(.horizontal, -DS.Space.gutter).contentMargins(.horizontal, DS.Space.gutter, for: .scrollContent)
                        // Cómo decirlo: empezar con Alexa, la rutina para prender todo, y que se puede hablar con naturalidad.
                        VoiceTopic(title: Text("Cómo pedirlo"), meta: Text("No hace falta decirlo exacto.")) {
                            ForEach(guide.how) { PhraseRow(say: $0.say, note: Text(verbatim: $0.note)) }
                        }
                        .id("how")
                        VoiceTopic(title: Text("Solo en el iPhone"), meta: Text("Descargar funciona aunque estés fuera de casa.")) {
                            ForEach(VoiceGuideResults.phoneOnly, id: \.say) { PhraseRow(say: $0.say, note: $0.note) }
                        }
                        .id("phone")
                        ForEach(guide.groups) { group in
                            VoiceTopic(title: Text(verbatim: group.title)) {
                                ForEach(group.commands) {
                                    PhraseRow(say: $0.say, note: Text(verbatim: $0.note), noteEmpty: $0.note.isEmpty, onSay: onSay)
                                }
                            }
                            .id(group.id)
                        }
                        help.id("help")
                    } else {
                        VoiceGuideResults(guide: guide, query: query, onSay: onSay)
                    }
                }
                .frame(maxWidth: DS.TitleAction.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DS.Space.gutter).padding(.vertical, DS.Space.s4).padding(.bottom, DS.Space.s14)
            }
        }
        .tint(DS.accent)
        .background(Backdrop())
        .searchable(text: $query, prompt: Text("Buscar una frase"))
        .navigationTitle("Más frases, por tema").navigationBarTitleDisplayMode(.inline)
    }

    private var help: some View {
        VoiceTopic(title: Text("Si no funciona")) {
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
    }

    private func topicChip(_ title: String, id: String, proxy: ScrollViewProxy, verbatim: Bool = false) -> some View {
        Button { withAnimation(DS.Motion.base(reduceMotion)) { proxy.scrollTo(id, anchor: .top) } } label: {
            (verbatim ? Text(verbatim: title) : Text(LocalizedStringKey(title))).lineLimit(1)
        }
        .dsSecondaryButton().controlSize(.small)
    }
}

/// Lo que encontró la búsqueda, en todo: las frases de cada tema (tocables), cómo pedirlo y lo que solo hace el iPhone.
private struct VoiceGuideResults: View {
    let guide: AlexaGuide
    let query: String
    let onSay: ((String) -> Void)?

    /// Lo que atiende el iPhone sin preguntarle a la consola (`VoiceRouter`): descargar, seguir aquí, las teclas y el inglés.
    static let phoneOnly: [(say: String, note: Text)] = [
        ("descárgalo", Text("Descarga en el iPhone lo que se ve en la TV.")),
        ("descarga Dune", Text("Busca la película y la descarga. Una serie, desde su ficha.")),
        ("síguela en mi iPhone", Text("Sigue aquí lo que se ve en la TV, donde iba.")),
        ("atrás · arriba · aceptar · menú", Text("Las teclas del mando, dichas solas.")),
        ("play The Office · pause · next episode", Text("Lo básico también en inglés.")),
    ]

    var body: some View {
        let groups = filteredGroups
        let how = guide.how.filter(matches)
        let phone = Self.phoneOnly.filter { VoiceGuideText.contains($0.say, query) }
        if groups.isEmpty, how.isEmpty, phone.isEmpty {
            ContentUnavailableView.search(text: query)
        }
        ForEach(groups) { group in
            VoiceTopic(title: Text(verbatim: group.title)) {
                ForEach(group.commands) { PhraseRow(say: $0.say, note: Text(verbatim: $0.note), noteEmpty: $0.note.isEmpty, onSay: onSay) }
            }
        }
        if !how.isEmpty {
            VoiceTopic(title: Text("Cómo pedirlo")) { ForEach(how) { PhraseRow(say: $0.say, note: Text(verbatim: $0.note)) } }
        }
        if !phone.isEmpty {
            VoiceTopic(title: Text("Solo en el iPhone")) { ForEach(phone, id: \.say) { PhraseRow(say: $0.say, note: $0.note) } }
        }
    }

    private func matches(_ phrase: AlexaGuide.Phrase) -> Bool { VoiceGuideText.contains(phrase.say + " " + phrase.note, query) }

    private var filteredGroups: [AlexaGuide.Group] {
        guide.groups.compactMap { g in
            let hits = g.commands.filter(matches)
            return hits.isEmpty ? nil : AlexaGuide.Group(title: g.title, icon: g.icon, commands: hits)
        }
    }
}

/// Comparar frases sin acentos ni mayúsculas («subtítulos» = «Subtitulos»).
private enum VoiceGuideText {
    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
    }
    static func same(_ a: String, _ b: String) -> Bool { fold(a) == fold(b) }
    static func contains(_ text: String, _ query: String) -> Bool {
        let q = fold(query)
        return q.isEmpty || fold(text).contains(q)
    }

    /// El símbolo de una frase: el primero cuyo pedazo aparece en ella (en orden: «pon subtítulos» es de subtítulos, no de
    /// «pon …»). Uno por omisión para las que no se parecen a ninguno.
    private static let symbols: [(piece: String, symbol: String)] = [
        ("pausa", "pause.fill"), ("siguiente", "forward.end.fill"), ("intro", "forward.fill"), ("subtitul", "captions.bubble"),
        ("audio", "waveform"), ("silencio", "speaker.slash.fill"), ("volumen", "speaker.wave.2.fill"),
        ("canal", "antenna.radiowaves.left.and.right"), ("sigue viendo", "play.circle"), ("sale hoy", "calendar"),
        ("cierra", "xmark.circle"), ("apaga", "power"), ("prende", "power"), ("abre", "gamecontroller"), ("pon ", "play.fill"),
    ]
    static func symbol(for say: String) -> String {
        let said = fold(say)
        return symbols.first { said.contains($0.piece) }?.symbol ?? "quote.bubble"
    }
}

/// Un tema: su encabezado (el de toda la app) y sus frases en una tarjeta.
private struct VoiceTopic<Content: View>: View {
    let title: Text
    /// Lo que explica el tema («No hace falta decirlo exacto.»): va en el cuerpo, bajo el título.
    var meta: Text? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            DSSectionHead(title: title, level: .section)
            if let meta { meta.recipe(.footnote, color: DS.textMuted) }
            VStack(alignment: .leading, spacing: DS.Space.s3) { content }
                .padding(DS.Space.s4).frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        }
    }
}

/// Una frase en tarjeta, tocable: en «Ahora» (tinte verde agua, sin nota) o en «Lo esencial» (la frase en el acento y su
/// nota en una línea). Tocarla la manda (`onSay`); mantenerla enseña la nota completa, mandarla y copiarla.
private struct PhraseCard: View {
    enum Style { case now, essential }
    let phrase: AlexaGuide.Phrase
    let style: Style
    let onSay: ((String) -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button { onSay?(phrase.say) } label: { label }
            .buttonStyle(.plain)   // se atenúa al tocarla: el resaltado
            .pointerHover(.lift)
            .contextMenu {
                if !phrase.note.isEmpty { Text(verbatim: phrase.note) }
                if let onSay { Button("Mandar a la tele", systemImage: "tv") { onSay(phrase.say) } }
                Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = phrase.say }
            }
            .accessibilityLabel(Text(verbatim: "«\(phrase.say)»"))
            .accessibilityHint(Text(verbatim: phrase.note))
    }

    private var tint: Color { style == .now ? DS.ListTint.calendar : DS.accent }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous) }

    private var label: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            Image(systemName: VoiceGuideText.symbol(for: phrase.say)).font(DS.TextRecipe.cardTitle.font).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(verbatim: "«\(phrase.say)»").font(DS.TextRecipe.secondary.font.weight(.semibold))
                .foregroundStyle(style == .now ? DS.text : DS.accent)
                .fixedSize(horizontal: false, vertical: true)
            if style == .essential, !phrase.note.isEmpty {
                // Una línea; con letra muy grande, completa (la tarjeta crece).
                Text(verbatim: phrase.note).recipe(.footnote).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(minHeight: DS.Size.touchTarget)
        .background(style == .now ? DS.ListTint.calendar.opacity(DS.VoiceGuide.starterFill) : DS.surface, in: shape)
        .contentShape(shape)
    }
}

/// Dónde hablarle, en chico: el ícono en su color, el nombre y cómo empezar.
private struct WhereTile: View {
    let symbol: String
    let tint: Color
    let title: Text
    let detail: Text

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(tint).accessibilityHidden(true)
            title.recipe(.cardTitle).fontWeight(.semibold)
            detail.recipe(.footnote).fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.s3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
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

/// Una frase («pon el canal ADN 40») en su globo, y para qué sirve debajo. Con `onSay`, tocarla la manda a la tele;
/// mantener pulsado la copia.
private struct PhraseRow: View {
    let say: String
    let note: Text
    var noteEmpty = false
    var onSay: ((String) -> Void)? = nil

    var body: some View {
        Group {
            if let onSay {
                Button { onSay(say) } label: { content.frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("La manda a la tele"))
            } else {
                content
            }
        }
        .contextMenu {
            if let onSay { Button("Mandar a la tele", systemImage: "tv") { onSay(say) } }
            Button("Copiar", systemImage: "doc.on.doc") { UIPasteboard.general.string = say }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text(verbatim: "«\(say)»").font(DS.TextRecipe.secondary.font.weight(.semibold)).foregroundStyle(DS.text)
                .padding(.horizontal, DS.Space.s3).padding(.vertical, DS.Space.s2)
                .background(DS.fill, in: UnevenRoundedRectangle(topLeadingRadius: DS.Radius.lg, bottomLeadingRadius: DS.Space.s1,
                                                                 bottomTrailingRadius: DS.Radius.lg, topTrailingRadius: DS.Radius.lg, style: .continuous))
            if !noteEmpty { note.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).padding(.leading, DS.Space.s1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// La lista de frases (Resources/AlexaCommands.json): las esenciales (`core`), cómo pedirlo y todas por tema.
struct AlexaGuide: Decodable {
    struct Phrase: Decodable, Identifiable, Hashable { let say: String; let note: String; var id: String { say } }
    struct Group: Decodable, Identifiable { let title: String; let icon: String; let commands: [Phrase]; var id: String { title } }
    let core: [Phrase]
    let how: [Phrase]
    let groups: [Group]

    /// Cuántas frases distintas hay en los temas (alguna se repite en dos).
    var phraseCount: Int { Set(groups.flatMap { $0.commands.map(\.say) }).count }

    static func load() -> AlexaGuide {
        guard let url = Bundle.main.url(forResource: "AlexaCommands", withExtension: "json"), let data = try? Data(contentsOf: url),
              let guide = try? JSONDecoder().decode(AlexaGuide.self, from: data) else { return AlexaGuide(core: [], how: [], groups: []) }
        return guide
    }
}
