import SwiftUI
import OrbitalCore
import OrbitalModels

/// Los controles de «Decide por mí»: un solo renglón debajo de las pestañas, el mismo en las dos, con «Todo · Películas ·
/// Series» a la izquierda y un solo botón «Filtros» a la derecha (`DSFiltersButton`, Fernando, 13 nov 2026: en lugar de los
/// cuatro íconos), que abre la hoja de filtros (`DecideFilters`: duración, ánimo, calificación y lo de afinar, por
/// secciones; en «Una por una» solo las que le aplican). Lo puesto se dice en una línea debajo («1 h · Ligero · 7+»), cada
/// parte con el color de su sección; al tocarla ofrece quitarlo o cambiarlo. Si no hay nada puesto, la línea no existe.
/// Regla en `docs/ios-interfaz.md` § «Una hoja, un renglón de controles».
struct DecideControls: View {
    let model: DecideModel
    /// «Una por una»: el tiempo y el ánimo no aplican al mazo.
    let deck: Bool
    let openFilters: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var words: DecideWords { DecideWords(language: env.services.appSettings.uiLanguage) }
    private var language: String { env.services.appSettings.uiLanguage }

    var body: some View {
        let m = model
        let parts = words.setParts(m, deck: deck)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            // Siempre en un renglón: la pastilla del tipo y el círculo de «Filtros» son de tamaño fijo (hasta xxxLarge) y caben
            // juntos aun en un SE con letra grande; sin `ViewThatFits` (regla «ViewThatFits no se anida ni vive bajo
            // alineación por línea base»: medir dos veces la pastilla congelaba la hoja).
            HStack(spacing: DS.Space.s3) {
                kind(m)
                Spacer(minLength: 0)
                DSFiltersButton(count: setCount(m), action: openFilters).accessibilityIdentifier("decide-filters")
            }
            // Entra bajando un poco desde los íconos y se va igual; con «Reducir movimiento», solo se funde.
            if !parts.isEmpty { setLine(m, parts).transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -DS.Space.s2))) }
        }
        .animation(DS.Motion.grow(reduceMotion) ?? DS.Motion.fade, value: parts)
    }

    /// Una parte de la línea de lo puesto: el ícono en el tinte de su filtro (el mismo del círculo de arriba) y su texto.
    private struct SetItem: Identifiable { let id: String; let symbol: String; let tint: Color; let text: String }

    /// Lo puesto por filtro, en el orden de los íconos: el tiempo, el ánimo, la calificación y lo de «Afinar» junto.
    private func setItems(_ m: DecideModel) -> [SetItem] {
        var items: [SetItem] = []
        if !deck, let t = m.shownTime { items.append(SetItem(id: "time", symbol: DS.Symbol.filterTime, tint: DS.DecideLive.time, text: words.timeName(t))) }
        if !deck, let mood = m.mood {
            items.append(SetItem(id: "mood", symbol: words.moodSymbol(mood), tint: DS.DecideLive.mood, text: Strings.tr(words.moodLabel(mood), language: language)))
        }
        if m.minRating > 0 || m.minLetterboxd > 0 {
            items.append(SetItem(id: "rating", symbol: DS.Symbol.filterRating, tint: DS.DecideLive.rating, text: words.ratingTitle(m)))
        }
        let refine = words.refineParts(m)
        if !refine.isEmpty { items.append(SetItem(id: "refine", symbol: DS.Symbol.refine, tint: DS.DecideLive.refine, text: refine.joined(separator: ", "))) }
        return items
    }

    private func kind(_ m: DecideModel) -> some View {
        // Cambiar de tipo no vuelve a barajar: regresan los tres que ya veías con ese tipo (`switchKind`); uno nuevo se baraja
        // una vez. El cambio es inmediato, dentro de la animación de la pastilla.
        DSKindFilter(kind: Binding(get: { m.kind ?? "" }, set: { new in
            if !m.switchKind(new.isEmpty ? nil : new) { Task { await m.applyKeepingKinds() } }
        }))
            .fixedSize()
            .accessibilityIdentifier("decide-kind")
    }

    /// Cuántos filtros hay puestos (el tipo no: se ve en su pastilla). El mismo número en las dos pestañas: es el mismo botón
    /// y la misma hoja (Fernando, 13 nov 2026).
    private func setCount(_ m: DecideModel) -> Int { m.activeFilters - (m.kind == nil ? 0 : 1) }

    /// «1 h · Ligero · 7+ · Comedia»: lo puesto, en una línea. Tocarla ofrece «Cambiar filtros» (la hoja), «Quitar …» por
    /// filtro y «Quitar filtros».
    private func setLine(_ m: DecideModel, _ parts: [String]) -> some View {
        Menu {
            Button("Cambiar filtros", systemImage: DS.Symbol.refine, action: openFilters)
            Divider()
            if !deck, let t = m.shownTime {
                Button(String(format: Strings.tr("Quitar %@", language: language), words.timeName(t)), systemImage: DS.Symbol.filterTime) { Task { await m.chooseTime(nil) } }
            }
            if !deck, let mood = m.mood {
                Button(String(format: Strings.tr("Quitar %@", language: language), Strings.tr(words.moodLabel(mood), language: language)), systemImage: words.moodSymbol(mood)) {
                    m.mood = nil; Task { await m.apply() }
                }
            }
            if m.minRating > 0 || m.minLetterboxd > 0 {
                Button(String(format: Strings.tr("Quitar %@", language: language), words.ratingTitle(m)), systemImage: DS.Symbol.filterRating) {
                    m.minRating = 0; m.minLetterboxd = 0; Task { await m.apply() }
                }
            }
            if m.moreFilters > 0 {
                Button(String(format: Strings.tr("Quitar %@", language: language), words.refineParts(m).joined(separator: ", ")), systemImage: DS.Symbol.refine) {
                    Task { await m.clearMoreFilters() }
                }
            }
            Divider()
            Button("Quitar filtros", systemImage: "xmark", role: .destructive) {
                m.clearFilters()
                Task { await m.apply() }
            }
        } label: {
            HStack(spacing: DS.Space.s3) {
                ForEach(setItems(m)) { item in
                    HStack(spacing: DS.Space.s1) {
                        Image(systemName: item.symbol).font(DS.TextRecipe.label.font).foregroundStyle(item.tint)
                        Text(verbatim: item.text).recipe(.footnote, color: DS.textMuted).lineLimit(1)
                    }
                    .transition(reduceMotion ? .opacity : .scale(scale: DS.KindPill.enterScale, anchor: .leading).combined(with: .opacity))
                }
                Image(systemName: "chevron.down").font(DS.TextRecipe.badge.font).foregroundStyle(DS.textMuted)
            }
            .frame(minHeight: DS.Size.touchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Filtros puestos"))
        .accessibilityValue(Text(verbatim: parts.joined(separator: ", ")))
        .accessibilityIdentifier("decide-set")
    }
}
