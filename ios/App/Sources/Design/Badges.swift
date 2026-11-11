import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Etiquetas pequeñas: fichas, insignias, el logo de plataforma, la barra de avance y el encabezado de sección.
/// Un dato corto: «2,1 GB», «HDR», «Al instante» (`good`) o «34 GB» (`warn`). Una línea, nunca se parte.
struct DSChip: View {
    enum Tone { case normal, good, warn }
    let label: Text
    var tone: Tone = .normal

    init(text: LocalizedStringKey, tone: Tone = .normal) { label = Text(text); self.tone = tone }
    /// Texto ya armado (nombres, tamaños): no se traduce.
    init(verbatim: String, tone: Tone = .normal) { label = Text(verbatim: verbatim); self.tone = tone }

    var body: some View {
        label.font(DS.TextRecipe.caption.font).lineLimit(1).fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.tag, style: .continuous))   // ds-exception: una placa chica (DS.Radius.tag), no una caja
    }

    private var color: Color { switch tone { case .normal: DS.textMuted; case .good: DS.good; case .warn: DS.warning } }
}

/// Etiqueta que llama la atención sobre el arte: «Recomendada», «En tu lista» (sin mayúsculas). `.fresh`: lo que ya se
/// puede ver hoy (la marca «Hoy» de «Lo nuevo de lo tuyo»): el punto turquesa del logo y el texto en turquesa, sin cápsula
/// (`DS.fresh`, 2 nov 2026: antes una cápsula verde). «Nuevo» sobre un póster es `DSNewDot`; bajo él, `DSFreshMark`.
struct DSBadge: View {
    enum Tone { case onArt, fresh }
    let text: LocalizedStringKey
    var tone: Tone = .onArt
    /// Un ícono antes del texto (el calendario de «Domingo»: cuándo sale), para que la placa diga qué es sin una frase que se
    /// corte en un póster angosto («Sale el do…»; Fernando, 2 nov 2026, F2).
    var symbol: String? = nil
    var body: some View {
        switch tone {
        case .onArt:
            HStack(spacing: DS.Space.s1) {
                if let symbol { Image(systemName: symbol).accessibilityHidden(true) }
                Text(text)
            }
            .font(DS.TextRecipe.badge.font).lineLimit(1).foregroundStyle(DS.paper)   // sobre la placa oscura del arte, en los dos modos
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        case .fresh:
            DSFreshMark(text: text, tone: .strong)
        }
    }
}

/// Lo nuevo o lo de hoy: el punto turquesa del logo de Orbital y su palabra («Hoy», «Nuevo»). La firma de la app para lo
/// reciente, la misma en toda la app (Fernando, 2 nov 2026, B4 y D3). `strong`: la palabra en turquesa («Hoy» en la línea de
/// tiempo); `quiet`: en gris, bajo un póster («Nuevo» en el Top 10).
struct DSFreshMark: View {
    enum Tone { case strong, quiet }
    let text: LocalizedStringKey
    var tone: Tone = .quiet
    var body: some View {
        HStack(spacing: DS.Space.s1) {
            Circle().fill(DS.fresh).frame(width: DS.HomeTimeline.dot, height: DS.HomeTimeline.dot)
            Text(text).recipe(tone == .strong ? .label : .footnote, color: tone == .strong ? DS.fresh : DS.textMuted).lineLimit(1)
        }
    }
}

/// Una marca de una sola idea en la esquina de un póster (en tu watchlist): el ícono sobre la placa oscura, con su nombre para VoiceOver.
struct DSIconBadge: View {
    let symbol: String
    let label: LocalizedStringKey
    var body: some View {
        Image(systemName: symbol).font(DS.TextRecipe.badge.font).foregroundStyle(DS.paper)
            .padding(DS.Space.s1 + DS.Space.s1 / 2)
            .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .accessibilityLabel(Text(label))
    }
}

/// El puesto en un Top 10 (chart de Netflix, JustWatch…): una sola pieza, número grande sobre una placa oscura,
/// con el mismo radio que la portada que acompaña (esquina superior izquierda).
struct DSRankBadge: View {
    let rank: Int
    var body: some View {
        Text(verbatim: "\(rank)").font(DS.TextRecipe.section.font).foregroundStyle(DS.paper).lineLimit(1)   // sobre la placa oscura, en los dos modos
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
            .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .accessibilityLabel(Text("Puesto \(rank)"))
    }
}

/// El logo de una plataforma (Netflix, Disney+…) en un chip o un encabezado: siempre la misma altura, venga el
/// logo cuadrado o apaisado, para que la tira no «baile».
struct DSPlatformLogo: View {
    let url: String?

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                RemoteImage(url: u, maxPoints: DS.Image.platformLogo) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFit() } else { Color.clear }
                }
            } else { Color.clear }
        }
        .frame(height: DS.Size.platformLogo)
    }
}

/// Cuánto llevas de un video.
struct DSProgress: View {
    let fraction: Double
    /// El grueso: el de siempre o el doble para lo que vas viendo en una lista de capítulos (Fernando, 2 nov 2026, O1).
    var height: CGFloat = DS.Space.s1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DS.track)
                // Sin avance no se dibuja (una forma de ancho cero, dentro del vidrio y girada en 3D en el carrusel, cerraba la app).
                if fraction > 0 { Rectangle().fill(DS.accent).frame(width: max(DS.Size.hairline, geo.size.width * min(1, fraction))) }   // el acento es avance
            }
        }
        .frame(height: height).clipShape(Capsule())
        // Al volver del reproductor, la barra corre hasta donde te quedaste (confirma que se guardó).
        .animation(DS.Motion.smooth(reduceMotion), value: fraction)
        .accessibilityLabel(Text("Avance")).accessibilityValue(Text("\(Int(fraction * 100)) %"))
    }
}

/// El encabezado de toda sección de la app (dirección «Editorial»), en dos niveles y nada más (Fernando, 31 oct 2026,
/// opción A: la misma regla en toda la app):
/// - `.section`: agrupa varias cosas («Plataformas», «Premios», «Día por día»). El rótulo: ícono gris (si lo trae), el
///   nombre en letra normal y una línea fina hasta la orilla (`DSChapterLabel`, el mismo de `DSChapterHead`). Sin porqué.
/// - `.subsection`: una fila o un estante («En tendencia», «Seguir viendo», «Tus 5 estrellas»). Título blanco mediano; su
///   porqué arriba en turquesa (`eyebrow`, o `meta`) solo cuando ayuda.
/// «Ver todo» es una flecha pegada al título (todo el encabezado abre la lista); a la derecha, si acaso, un dato (cuántos, cuánto pesa), nunca una frase; lo que explica va
/// en el cuerpo, no bajo el título. Sin íconos: el color lo pone el arte de abajo. `DesignTests` revisa las dos reglas.
struct DSSectionHead: View {
    enum Level { case section, subsection }
    let title: Text
    var trailing: Text?
    var action: (() -> Void)?
    /// Cuántos hay (en gris), en listas que son herramienta (Descargas); en un escaparate, mejor «Ver todo».
    var count: Int?
    /// Abre la lista completa: «Ver todo».
    var chevron = false
    /// La línea gris de abajo.
    var meta: Text?
    /// De dónde viene (tus complementos, tu Orbital, Rotten Tomatoes): su sello junto al título. Trakt ya no lleva sello: el
    /// círculo rojo se leía como una palomita de «hecho» y competía con los pósters; lo dice el porqué turquesa («Recomendadas
    /// por Trakt») (Fernando, 2 nov 2026, B2/C2/E2).
    var source: ListSource?
    /// El porqué, en una línea turquesa arriba del título («Lo que dejaste pendiente»), como en una revista (solo subsecciones).
    var eyebrow: Text?
    var level: Level = .subsection
    /// El ícono del rótulo de una sección (gris).
    var symbol: String?
    /// Una fila de descubrir en una pantalla que mezcla lo tuyo con lo que descubres (Inicio): el título un paso más chico
    /// (`sectionQuiet`), para que lo tuyo pese más (Fernando, 2 nov 2026, C5).
    var quiet = false

    init(title: Text, trailing: Text? = nil, action: (() -> Void)? = nil, count: Int? = nil, chevron: Bool = false, meta: Text? = nil, source: ListSource? = nil, eyebrow: Text? = nil,
         level: Level = .subsection, symbol: String? = nil, quiet: Bool = false) {
        self.title = title; self.trailing = trailing; self.action = action; self.count = count; self.chevron = chevron; self.meta = meta
        self.source = source == .trakt ? nil : source
        self.eyebrow = eyebrow; self.level = level; self.symbol = symbol; self.quiet = quiet
    }

    init(title: LocalizedStringKey, trailing: LocalizedStringKey? = nil, action: (() -> Void)? = nil, count: Int? = nil, chevron: Bool = false, meta: Text? = nil, source: ListSource? = nil, eyebrow: Text? = nil,
         level: Level = .subsection, symbol: String? = nil, quiet: Bool = false) {
        self.init(title: Text(title), trailing: trailing.map { Text($0) }, action: action, count: count, chevron: chevron, meta: meta, source: source, eyebrow: eyebrow,
                  level: level, symbol: symbol, quiet: quiet)
    }

    var body: some View {
        // Sin texto a la derecha, la acción es de todo el encabezado (el «Ver todo» de Buscar): antes solo se conectaba
        // con `trailing` y la cápsula «Ver todo» no hacía nada al tocarla.
        if trailing == nil, let action { Button(action: action) { content }.buttonStyle(.plain) } else { content }
    }

    @ViewBuilder private var content: some View {
        if level == .section { chapter } else { head }
    }

    /// Una sección: el rótulo con su línea y, a la derecha, el dato o «Ver todo».
    private var chapter: some View {
        HStack(spacing: DS.Space.s2) {
            DSChapterLabel(label: title, symbol: symbol)
            if let trailing {
                if let action { Button(action: action) { trailing }.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted) }
                else { trailing.font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted).lineLimit(1) }
            }
            if chevron { seeAllChevron }
            else if let count { Text(verbatim: "\(count)").recipe(.footnote, color: DS.textMuted) }
        }
        .textCase(nil)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var sectionTitle: some View { sectionTitle(chevron: chevron) }

    private func sectionTitle(chevron: Bool) -> some View {
        (chevron ? title.withTitleChevron() : title).recipe(level == .section ? .title : quiet ? .sectionQuiet : .section).multilineTextAlignment(.leading)
            .accessibilityLabel(title).accessibilityHint(self.chevron ? Text("Ver todo") : Text(verbatim: ""))
            // El centro que se ve (la mitad de las mayúsculas sobre la línea base), no el de la caja del texto:
            // así lo de la derecha no queda alto.
            .alignmentGuide(.sectionTitle) { $0[.firstTextBaseline] - UIFont.preferredFont(forTextStyle: level == .section ? .title1 : quiet ? .title3 : .title2).capHeight / 2 }
    }

    /// «Ver todo»: la flecha va pegada al título y todo el encabezado abre la lista (Fernando, 2 nov 2026: sin la cápsula
    /// de texto a la derecha, como en Música y la App Store).
    private var seeAllChevron: some View { DSTitleChevron() }

    /// El título, con la flecha de «Ver todo» al final de su texto si abre la lista completa.
    private func titleLine(_ lines: Int, chevron: Bool? = nil) -> some View { sectionTitle(chevron: chevron ?? self.chevron).lineLimit(lines) }

    private var head: some View {
        // Lo de la derecha («Ver todo», el número) va a la altura del título, no de la línea ámbar de arriba.
        HStack(alignment: .sectionTitle, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Un solo lugar para el porqué de una sección en toda la app: arriba del título, en ámbar (como una revista).
                // Antes unas lo ponían arriba en ámbar y otras abajo en gris.
                if level == .subsection, let line = eyebrow ?? meta { line.recipe(.eyebrow, color: DS.eyebrow).lineLimit(2).multilineTextAlignment(.leading) }
                // El título nunca se parte a media palabra por el sello («Aproba-das por…»). Un ícono (el jitomate) cabe
                // siempre al lado; un sello con nombre, si no caben en un renglón, cede y baja bajo el título.
                if let source, source.isIcon {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        // La flecha de «Ver todo» va después del jitomate, no entre el título y él (Fernando, 3 nov 2026).
                        titleLine(2, chevron: false)
                        SourceBadge(source: source).alignmentGuide(.firstTextBaseline) { $0[.bottom] - DS.Size.markOvershoot }   // el jitomate, centrado con las mayúsculas
                        if chevron { Text(Image(systemName: "chevron.forward")).recipe(quiet ? .sectionQuiet : .section, color: DS.textMuted).accessibilityHidden(true) }
                    }
                } else { ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        titleLine(1)
                        if let source { SourceBadge(source: source) }
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        titleLine(2)
                        if let source { SourceBadge(source: source) }
                    }
                } }
                if level == .subsection, eyebrow != nil, let meta { meta.recipe(.footnote).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: DS.Space.s2)
            if let trailing {
                if let action { Button(action: action) { trailing }.font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted) }
                else { trailing.font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted) }
            }
            if !chevron, let count { Text(verbatim: "\(count)").recipe(.secondary, color: DS.textMuted) }
        }
        .textCase(nil)   // también como encabezado de una lista (Descargas): sin las mayúsculas del sistema
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
