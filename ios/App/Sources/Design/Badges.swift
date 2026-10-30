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
            .background(DS.fill, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private var color: Color { switch tone { case .normal: DS.textMuted; case .good: DS.good; case .warn: DS.warning } }
}

/// Un dato ya armado (nombres, tamaños): no se traduce.
struct DSChipText: View {
    let text: String
    var tone: DSChip.Tone = .normal
    var body: some View { DSChip(verbatim: text, tone: tone) }
}

/// Etiqueta que llama la atención sobre el arte: «Recomendada», «En tu lista» (sin mayúsculas). `.fresh`: lo que ya se
/// puede ver hoy («Nuevo», la marca «HOY» de «Lo nuevo de lo tuyo»), una cápsula verde.
struct DSBadge: View {
    enum Tone { case onArt, fresh }
    let text: LocalizedStringKey
    var tone: Tone = .onArt
    var body: some View {
        switch tone {
        case .onArt:
            Text(text).font(DS.TextRecipe.caption.font.weight(.semibold)).lineLimit(1).foregroundStyle(DS.paper)   // sobre la placa oscura del arte, en los dos modos
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
        case .fresh:
            Text(text).font(DS.TextRecipe.caption.font.weight(.heavy)).lineLimit(1).foregroundStyle(DS.onPrimary)
                .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
                .background(DS.success, in: Capsule())
        }
    }
}

/// Una marca de una sola idea en la esquina de un póster (en tu watchlist): el ícono sobre la placa oscura, con su nombre para VoiceOver.
struct DSIconBadge: View {
    let symbol: String
    let label: LocalizedStringKey
    var body: some View {
        Image(systemName: symbol).font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.paper)
            .padding(DS.Space.s1 + DS.Space.s1 / 2)
            .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
            .accessibilityLabel(Text(label))
    }
}

/// El puesto en un Top 10 (chart de Netflix, JustWatch…): una sola pieza, número grande sobre una placa oscura,
/// con el mismo radio que la portada que acompaña (esquina superior izquierda).
struct DSRankBadge: View {
    let rank: Int
    var body: some View {
        Text(verbatim: "\(rank)").font(DS.TextRecipe.section.font.weight(.bold)).foregroundStyle(DS.paper).lineLimit(1)   // sobre la placa oscura, en los dos modos
            .padding(.horizontal, DS.Space.s2).padding(.vertical, DS.Space.s1)
            .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.md))
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
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(DS.track)
                // Sin avance no se dibuja (una forma de ancho cero, dentro del vidrio y girada en 3D en el carrusel, cerraba la app).
                if fraction > 0 { Rectangle().fill(DS.accent).frame(width: max(DS.Size.hairline, geo.size.width * min(1, fraction))) }   // el acento es avance
            }
        }
        .frame(height: DS.Space.s1).clipShape(Capsule())
        .accessibilityLabel(Text("Avance")).accessibilityValue(Text("\(Int(fraction * 100)) %"))
    }
}

/// El encabezado de toda sección de la app (dirección «Editorial»): el título grande, a la derecha «Ver todo» si abre la
/// lista completa (o un dato corto), y debajo una línea gris solo cuando ayuda a decidir. Sin íconos: el color lo pone el
/// arte de abajo. Una sola pieza: todas las secciones se ven igual.
struct DSSectionHead: View {
    let title: Text
    var trailing: Text?
    var action: (() -> Void)?
    /// Cuántos hay (en gris), en listas que son herramienta (Descargas); en un escaparate, mejor «Ver todo».
    var count: Int?
    /// Abre la lista completa: «Ver todo».
    var chevron = false
    /// La línea gris de abajo.
    var meta: Text?
    /// De dónde viene (Trakt, tus complementos, tu Orbital): su sello junto al título.
    var source: ListSource?
    /// El porqué, en una línea ámbar arriba del título («Lo que dejaste pendiente»), como en una revista.
    var eyebrow: Text?
    /// `.group`: el título de un grupo de secciones (Para ti: «Ahora», «Plataformas», «Premios»…), más grande y con su frase
    /// gris a la derecha (`trailing`).
    var size: Size = .section
    enum Size { case section, group }

    init(title: Text, trailing: Text? = nil, action: (() -> Void)? = nil, count: Int? = nil, chevron: Bool = false, meta: Text? = nil, source: ListSource? = nil, eyebrow: Text? = nil,
         size: Size = .section) {
        self.title = title; self.trailing = trailing; self.action = action; self.count = count; self.chevron = chevron; self.meta = meta; self.source = source
        self.eyebrow = eyebrow; self.size = size
    }

    init(title: LocalizedStringKey, trailing: LocalizedStringKey? = nil, action: (() -> Void)? = nil, count: Int? = nil, chevron: Bool = false, meta: Text? = nil, source: ListSource? = nil, eyebrow: Text? = nil) {
        self.init(title: Text(title), trailing: trailing.map { Text($0) }, action: action, count: count, chevron: chevron, meta: meta, source: source, eyebrow: eyebrow)
    }

    var body: some View {
        // Sin texto a la derecha, la acción es de todo el encabezado (el «Ver todo» de Buscar): antes solo se conectaba
        // con `trailing` y la cápsula «Ver todo» no hacía nada al tocarla.
        if trailing == nil, let action { Button(action: action) { head }.buttonStyle(.plain) } else { head }
    }

    private var sectionTitle: some View {
        title.recipe(size == .group ? .title : .section).multilineTextAlignment(.leading)
            // El centro que se ve (la mitad de las mayúsculas sobre la línea base), no el de la caja del texto:
            // así lo de la derecha no queda alto.
            .alignmentGuide(.sectionTitle) { $0[.firstTextBaseline] - UIFont.preferredFont(forTextStyle: size == .group ? .title1 : .title2).capHeight / 2 }
    }

    private var head: some View {
        // Lo de la derecha («Ver todo», el número) va a la altura del título, no de la línea ámbar de arriba.
        HStack(alignment: .sectionTitle, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                // Un solo lugar para el porqué de una sección en toda la app: arriba del título, en ámbar (como una revista).
                // Antes unas lo ponían arriba en ámbar y otras abajo en gris.
                if let line = eyebrow ?? meta { line.recipe(.eyebrow, color: DS.eyebrow).lineLimit(2).multilineTextAlignment(.leading) }
                // El título nunca se parte a media palabra por el sello («Aproba-das por…»). Un ícono (el jitomate) cabe
                // siempre al lado; un sello con nombre, si no caben en un renglón, cede y baja bajo el título.
                if let source, source.isIcon {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        sectionTitle.lineLimit(2)
                        SourceBadge(source: source).alignmentGuide(.firstTextBaseline) { $0[.bottom] }   // el jitomate se para en la línea del título
                    }
                } else { ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s2) {
                        sectionTitle.lineLimit(1)
                        if let source { SourceBadge(source: source) }
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        sectionTitle.lineLimit(2)
                        if let source { SourceBadge(source: source) }
                    }
                } }
                if eyebrow != nil, let meta { meta.recipe(.footnote).lineLimit(2).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: DS.Space.s2)
            if let trailing {
                if let action { Button(action: action) { trailing }.font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted) }
                else { trailing.font(DS.TextRecipe.secondary.font).foregroundStyle(DS.textMuted) }
            }
            if chevron { SeeAllLabel() }
            else if let count { Text(verbatim: "\(count)").recipe(.secondary, color: DS.textMuted) }
        }
        .textCase(nil)   // también como encabezado de una lista (Descargas): sin las mayúsculas del sistema
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
