import SwiftUI
import OrbitalCore
import OrbitalModels

/// Un filtro como mosaico: su dibujo arriba, el nombre y lo elegido. Con algo elegido, borde blanco (lo elegido siempre en
/// blanco); abierto, borde más grueso y fondo más claro. Género lleva de fondo el arte de los géneros elegidos. `mini`: la
/// versión chica de la puerta de Buscar.
struct FilterTile: View {
    let page: FilterPage
    let context: FilterContext
    var mini = false
    var open = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sin ningún filtro puesto, los mosaicos van sin renglón de valor y más bajos (Fernando, 2 nov 2026, K5: seis
    /// «Cualquiera» iguales no decían nada). Con uno puesto, todos crecen juntos (el renglón parejo) y solo el puesto dice su
    /// valor; los demás no repiten «Cualquiera».
    static func compact(_ context: FilterContext) -> Bool { FilterPage.allCases.allSatisfy { FilterText.value($0, context) == nil } }

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        let value = FilterText.value(page, context)
        let on = value != nil
        let compact = Self.compact(context)
        let shape = RoundedRectangle(cornerRadius: mini ? DS.Radius.md : DS.Radius.lg, style: .continuous)
        let art = page == .genre ? Tmdb.filterGenres.filter { context.filter.genres.contains($0.slug) }.prefix(DS.Filter.genreMosaicMax).map { FilterCatalog.genreImage($0.slug) } : []
        Button(action: action) {
            // Centrado (Fernando, 31 oct 2026): el dibujo, el nombre y lo elegido al centro del mosaico.
            VStack(spacing: mini ? DS.Space.s1 / 2 : DS.Space.s1) {
                if art.isEmpty { FilterArt(page: page, context: context, mini: mini) } else { Spacer(minLength: 0) }
                // Sobre el arte de los géneros el texto va en papel (se lee igual en claro y en oscuro).
                page.title.recipe(mini ? .badge : .label, color: art.isEmpty ? DS.text : DS.paper).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
                if page == .rating, value != nil {
                    // De dónde sale el número de arriba (el logo de TMDB o el de Letterboxd) y, con las dos, las estrellas.
                    let f = context.filter, stars = f.format == .series ? nil : f.minLetterboxd
                    HStack(spacing: DS.Space.s1) {
                        if f.minRating != nil {
                            Image("rating-tmdb").resizable().scaledToFit().frame(height: DS.Filter.tmdbMark).accessibilityLabel(Text(verbatim: "TMDB"))
                        } else { LetterboxdMark() }
                        if f.minRating != nil, let stars { Text(verbatim: "· ★" + RatingLevels.short(stars)).recipe(.caption, color: DS.Letterboxd.leaf).monospacedDigit() } else { Text("o más").recipe(.caption, color: DS.text) }
                    }
                } else if let value {
                    value.recipe(.caption, color: !art.isEmpty ? DS.paper : DS.text).lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: DS.Motion.leaveScale, anchor: .top)))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, mini ? DS.Space.s2 : DS.Space.s2)
            .padding(.vertical, mini ? DS.Space.s2 : DS.Space.s2)
            .frame(maxWidth: .infinity, minHeight: compact ? (mini ? DS.Filter.miniTileCompact : DS.Filter.tileCompact) : (mini ? DS.Filter.miniTileHeight : DS.Filter.tileHeight))
            .background {
                ZStack {
                    open || mini ? DS.surfaceRaised : DS.surface
                    if !art.isEmpty {
                        GenreMosaic(images: art)
                        ArtVeil(strength: .deep)
                    }
                }
                .animation(DS.Motion.fade, value: art)
            }
            .clipShape(shape)
            .dsSelectionRing(on || open, in: shape)
            .overlay(alignment: .topTrailing) {
                if on { Circle().fill(page.hue).frame(width: DS.Filter.dot, height: DS.Filter.dot).padding(mini ? DS.Space.s2 : DS.Space.s2).accessibilityHidden(true) }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(value ?? Text("Cualquiera"))   // VoiceOver sí lo dice: lo que se quitó es solo lo que se ve
        // El valor entra con el resorte de la app y el mosaico crece suave (sin movimiento con Reducir movimiento).
        .animation(DS.Motion.smooth(reduceMotion) ?? DS.Motion.fade, value: on)
        .animation(DS.Motion.smooth(reduceMotion), value: compact)
    }
}
