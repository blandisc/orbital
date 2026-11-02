import SwiftUI
import UIKit
import CoreImage
import OrbitalCore
import OrbitalModels

// Las piezas del catálogo de Orbital para iPhone. Una pantalla se arma con estas; si falta una, se agrega aquí.
// Equivalencias con la TV: Chip, Badge, Progress, SectionHead, Card (PosterCard), FeatureTile (HeroCard), Mosaic (`Design/Mosaic.swift` ↔ `foryou-mosaic`), Button, Sheet.


/// Detalles de texto: «Ver todo», la etiqueta en cápsula, los estilos de `Text` y el desvanecido en los bordes.
extension VerticalAlignment {
    /// El centro del título de una sección: ahí se alinea lo de la derecha (aunque arriba haya una línea ámbar).
    private enum SectionTitle: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] } }
    static let sectionTitle = VerticalAlignment(SectionTitle.self)
}

/// «Ver todo ›»: en una cápsula tenue, a la altura del título (la misma en toda la app).
struct SeeAllLabel: View {
    var body: some View { DSCapsuleLabel(title: Text("Ver todo"), symbol: "chevron.forward", symbolFirst: false) }
}

/// La cápsula tenue de lo que va a la derecha de un título de sección («Ver todo ›», «📅 Octubre», «Todo ⌄»).
struct DSCapsuleLabel: View {
    let title: Text
    let symbol: String
    var symbolFirst = true
    /// Elegido (un filtro puesto): en papel, como las opciones en cápsula.
    var selected = false
    /// Todo el ancho que le den (varias en rejilla, todas parejas); si no, lo de su texto.
    var stretch = false
    /// Un glifo a la derecha además del de la izquierda (el ⌄ de un menú en una cápsula con ícono).
    var trailing: String?

    var body: some View {
        HStack(spacing: DS.HeaderControl.iconGap) {
            if symbolFirst { icon(symbol) }
            title.font(DS.TextRecipe.labelLarge.font).lineLimit(1).minimumScaleFactor(DS.Size.statScale)
            if !symbolFirst { icon(symbol) }
            if let trailing { icon(trailing) }
        }
        .foregroundStyle(selected ? DS.onPrimary : DS.text)
        .padding(.horizontal, DS.HeaderControl.padding)
        .frame(maxWidth: stretch ? .infinity : nil)
        .frame(height: DS.HeaderControl.height)
        .background(selected ? DS.primary : DS.fillStrong, in: Capsule())
        .frame(minHeight: DS.Size.touchTarget)   // se ve de 32 pt; se toca en 44
        .contentShape(Rectangle())
        .alignmentGuide(.sectionTitle) { $0[VerticalAlignment.center] }
    }

    private func icon(_ name: String) -> some View { Image(systemName: name).font(DS.TextRecipe.label.font).imageScale(.small) }
}

extension Text {
    /// La bandera de un idioma antes de su nombre («🇲🇽 Latino»), con su espacio; VoiceOver no la lee (dice solo el nombre).
    /// Sin bandera conocida (el árabe, un código raro), nada. Varios idiomas, varias banderas («🇺🇸🇲🇽 Inglés + latino»).
    static func flag(_ codes: [String]) -> Text {
        let flagged = LanguageFlags.flagged("", codes)
        return flagged.isEmpty ? Text(verbatim: "") : Text(verbatim: flagged + " ").accessibilityLabel(Text(verbatim: ""))
    }
    static func flag(_ code: String?) -> Text { flag(code.map { [$0] } ?? []) }

    /// Un texto que ya trae sus banderas al principio («🇲🇽 Latino · 1080p»): igual a la vista, pero VoiceOver no las lee.
    static func flagged(_ string: String) -> Text {
        let rest = LanguageFlags.withoutFlags(string)
        guard rest.count < string.count, string.hasSuffix(rest) else { return Text(verbatim: string) }
        return Text("\(Text(verbatim: String(string.dropLast(rest.count))).accessibilityLabel(Text(verbatim: "")))\(Text(verbatim: rest))")
    }
}

/// Una tira horizontal que no cabe (las temporadas de «Episodios»): en vez de cortarse en seco, se desvanece en la orilla
/// donde hay más. A la izquierda solo cuando ya la recorriste; a la derecha mientras quede algo por ver.
private struct HorizontalEdgeFade: ViewModifier {
    @State private var more = EdgeMore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct EdgeMore: Equatable { var leading = false, trailing = false }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: EdgeMore.self) { g in
                EdgeMore(leading: g.visibleRect.minX > 1, trailing: g.visibleRect.maxX < g.contentSize.width - 1)
            } action: { _, now in
                withAnimation(DS.Motion.base(reduceMotion)) { more = now }
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [more.leading ? .clear : .black, .black], startPoint: .leading, endPoint: .trailing).frame(width: DS.Size.edgeFade)
                    Color.black
                    LinearGradient(colors: [.black, more.trailing ? .clear : .black], startPoint: .leading, endPoint: .trailing).frame(width: DS.Size.edgeFade)
                }
            }
    }
}

extension View {
    /// Desvanece las orillas de un `ScrollView` horizontal que no cabe (ver `HorizontalEdgeFade`).
    func edgeFade() -> some View { modifier(HorizontalEdgeFade()) }
}

/// Un renglón que, si no cabe, de vez en cuando se recorre para leerse completo (como el nombre de la canción en Música):
/// espera, avanza hasta el final, espera y regresa. Si cabe, es un texto normal. Con «Reducir movimiento» no se mueve: se
/// corta con «…».
struct MarqueeText: View {
    let text: Text
    var recipe: DS.TextRecipe = .body
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var full: CGFloat = 0
    @State private var box: CGFloat = 0
    @State private var shift: CGFloat = 0

    private var overflow: CGFloat { max(0, full - box) }

    var body: some View {
        if reduceMotion {
            text.recipe(recipe).lineLimit(1)
        } else {
            text.recipe(recipe).lineLimit(1).fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { full = $0 }
                .offset(x: shift)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { box = $0 }
                .mask {
                    // Mientras no se ve entero, la orilla por donde sigue se desvanece (no un corte seco).
                    LinearGradient(stops: [.init(color: .black.opacity(shift < 0 ? 0 : 1), location: 0),
                                           .init(color: .black, location: overflow > 0 ? DS.Marquee.fade / max(box, 1) : 0),
                                           .init(color: .black, location: overflow > 0 ? 1 - DS.Marquee.fade / max(box, 1) : 1),
                                           .init(color: .black.opacity(overflow > 0 && shift > -overflow ? 0 : 1), location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                }
                .task(id: overflow) { await run() }
        }
    }

    private func run() async {
        shift = 0
        let distance = overflow
        guard distance > 1 else { return }
        let travel = Double(distance) / DS.Marquee.speed
        while !Task.isCancelled {
            try? await Task.sleep(for: DS.Marquee.rest)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Marquee.travel(travel)) { shift = -distance }
            try? await Task.sleep(for: .seconds(travel) + DS.Marquee.hold)
            guard !Task.isCancelled else { return }
            withAnimation(DS.Marquee.travel(travel)) { shift = 0 }
            try? await Task.sleep(for: .seconds(travel))
        }
    }
}
