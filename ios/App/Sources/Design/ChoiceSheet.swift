import SwiftUI

/// Las preguntas y elecciones de la app son tarjetas de la app, no diálogos del sistema (Fernando, 13 nov 2026: «Cuando le
/// picas un episodio ya visto, que créate una tarjeta, que no aparezca esta notificación como del sistema, toda fea»). Regla
/// en `docs/ios-interfaz.md` § «Las preguntas son tarjetas de la app»; la cuida `DesignRulesTests+Dialogs.swift`.
///
/// `ChoiceSheet`: una hoja chica a la medida de lo que trae (`fittedSheet`): arriba qué es (la imagen, el nombre y una línea
/// en gris), la acción principal grande (opcional) y las demás como renglones con ícono (`WatchedOption`, los mismos de
/// «¿Cuándo la viste?»). Sin «Cancelar»: se cierra deslizándola, tocando fuera o con Esc (iPad con teclado).

/// Una acción de la tarjeta: lo que dice, su ícono, una segunda línea si hace falta y su identificador para las pruebas.
struct ChoiceAction: Identifiable {
    let id: String
    let title: Text
    var detail: Text?
    let symbol: String
    let run: () -> Void
}

/// Lo que lleva la tarjeta. `art`: la imagen de lo que se pregunta (la miniatura de un episodio), con su proporción.
struct ChoiceCard {
    let title: Text
    var detail: Text?
    var art: String?
    var artAspect: CGFloat = DS.Poster.stillAspect
    var primary: ChoiceAction?
    var options: [ChoiceAction] = []
    /// El identificador de la hoja entera (las pruebas de interfaz la buscan por él).
    var id = "choice-sheet"
}

struct ChoiceSheet: View {
    let card: ChoiceCard
    /// En el reproductor (13 nov 2026): la misma tarjeta flotando sobre el video, de vidrio como sus paneles, y no una hoja
    /// (en horizontal la hoja de iOS sube a todo el alto y tapa el video). La pone y la quita `PlayerScreen+Preguntas.swift`.
    var floating = false
    /// Lo que pasa al tocar una acción: la cierra y la corre al terminar de cerrarse (`choiceSheet(item:)`).
    let choose: (ChoiceAction) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// El margen de abajo del aparato (la barra de inicio). Sin él (iPhone con botón, la tarjeta del iPad), la tarjeta pone el
    /// suyo, igual al de los lados: si no, el último renglón tocaba la orilla (SE, 13 nov).
    @State private var bottomInset: CGFloat = 0

    init(card: ChoiceCard, floating: Bool = false, choose: @escaping (ChoiceAction) -> Void) {
        self.card = card
        self.floating = floating
        self.choose = choose
    }

    var body: some View {
        if floating {
            content
                .padding(DS.Space.gutter)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DS.PlayerPanel.radius, style: .continuous))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(card.id)
        } else {
            content
                // Al pie solo el margen del iPhone, como «¿Cuándo la viste?» (con el aire de las hojas quedaba un hueco abajo).
                .dsSheetContent(bottom: false)
                .padding(.bottom, bottomInset > 0 ? 0 : DS.Space.gutter)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
                .accessibilityElement(children: .contain)   // cada acción conserva su identificador
                .accessibilityIdentifier(card.id)
                .fittedSheet()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            header
            if let primary = card.primary { primaryButton(primary) }
            if !card.options.isEmpty {
                VStack(spacing: DS.Space.s2) {
                    ForEach(card.options) { option in
                        WatchedOption(symbol: option.symbol, title: option.title, detail: option.detail) { choose(option) }
                            .accessibilityIdentifier(option.id)
                    }
                }
            }
        }
    }

    /// La imagen a la izquierda y el nombre con su línea gris; con letra de accesibilidad, la imagen arriba (no aprieta el texto).
    private var header: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.s3))
        return layout {
            if let art = card.art {
                PosterView(url: art, title: "", aspect: card.artAspect)
                    .frame(width: DS.Poster.episodeThumbWidth, height: DS.Poster.episodeThumbWidth / card.artAspect)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                card.title.recipe(.cardTitle, color: DS.text).fixedSize(horizontal: false, vertical: true)
                if let detail = card.detail { detail.recipe(.secondary, color: DS.textMuted) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// La principal: el botón sólido de la app a todo lo ancho, del alto de «Ver» en la ficha, con su detalle («🇲🇽 Latino»)
    /// en el mismo renglón. Antes el detalle iba debajo y el botón salía muy alto (Fernando, 13 nov 2026: «estaba muy grande
    /// el botón de ver otra vez»). Solo si no cabe en un renglón (letra grande, SE) el detalle baja.
    private func primaryButton(_ action: ChoiceAction) -> some View {
        let name = Label { action.title } icon: { Image(systemName: action.symbol) }.font(DS.TextRecipe.cardTitle.font)
        return Button { choose(action) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.s2) {
                    name
                    if let detail = action.detail { detail.font(DS.TextRecipe.secondary.font) }
                }
                .lineLimit(1)
                VStack(spacing: DS.Space.s1) {
                    name
                    if let detail = action.detail { detail.font(DS.TextRecipe.footnote.font) }
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: DS.TitleAction.primaryHeight - DS.Space.s3 * 2)
        }
        .dsSolidPrimaryButton()
        .accessibilityIdentifier(action.id)
    }
}

extension View {
    /// Presenta la tarjeta de `item` (`ChoiceSheet`). Una acción cierra la hoja y corre cuando ya se cerró: así lo que abre
    /// (el reproductor, «Versión») no choca con la hoja que se va.
    func choiceSheet<Item: Identifiable>(item: Binding<Item?>, card: @escaping (Item) -> ChoiceCard) -> some View {
        modifier(ChoicePresenter(item: item, card: card))
    }
}

private struct ChoicePresenter<Item: Identifiable>: ViewModifier {
    @Binding var item: Item?
    let card: (Item) -> ChoiceCard
    @State private var pending: (() -> Void)?

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: { let run = pending; pending = nil; run?() }) { current in
            ChoiceSheet(card: card(current)) { action in pending = action.run; item = nil }
        }
    }
}
