import SwiftUI
import OrbitalModels
import OrbitalCore


/// «Decide por mí»: la única puerta (DE2, Fernando, 13 nov 2026). Tres pósters en abanico (en Inicio, el dado), «Para cuando
/// no sabes qué ver» y las dos maneras de adentro, «Tres que caben · Una por una». Antes eran dos puertas: el dado de la barra
/// y la tarjeta «¿Qué vemos hoy?».
struct DecideDoor: View {
    /// Sin pósters (Inicio, o sin red): el dado.
    var posters: [String] = []
    /// Sin red y sin pósters: lo dice en vez de prometer opciones.
    var offline = false
    var id = "paraTi-decide"
    /// Más carteles para la tira de la derecha (solo en la Mac, `DS.ParaTiB.stripCount`).
    var more: [String] = []
    /// Su margen a los lados: 0 cuando va como tarjeta dentro de una fila o del panel del tablero (C6).
    var inset: CGFloat?
    let onOpen: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Un renglón junto al abanico; con letra de accesibilidad el texto va debajo, a todo lo ancho, y puede partirse.
    private var oneLine: Int? { typeSize.isAccessibilitySize ? nil : 1 }

    var body: some View {
        // Con letra de accesibilidad, el abanico arriba y el texto debajo: al lado no cabía y ensanchaba toda la página de
        // Explorar (ChaosRegressionUITests, letra máxima).
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4))
                                                  : AnyLayout(HStackLayout(spacing: DS.Space.s4))
        Button(action: onOpen) {
            layout {
                if posters.isEmpty {
                    Image(systemName: DS.Symbol.decide).font(DS.TextRecipe.title.font).foregroundStyle(DS.accent)
                        .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                } else {
                    PosterFan(posters: posters, width: DS.ParaTiB.doorPoster, shift: DS.ParaTiB.doorShift)
                }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    // En el SE, junto al abanico, se cortaba («…no sabes qu…»): se achica un poco en vez de cortarse.
                    Eyebrow(text: Text("Para cuando no sabes qué ver"), reason: true).minimumScaleFactor(DS.Size.statScale)
                    // El dado una sola vez: junto al nombre si hay pósters; si no, ya es el ícono de la izquierda.
                    // Más grande y con su color (Fernando, 17 nov 2026: «Decide por mí, hazlo más vistoso en ambos, un poquito
                    // más grande»): el nombre en tamaño de título y el dado en turquesa.
                    // DM-A (Fernando, 18 nov 2026: «ajuste fino, pero ponle más grande el icono del dado»): el nombre en un
                    // renglón; si no cabe (el SE), se achica tantito en vez de partirse en «Decide / por mí».
                    if posters.isEmpty { Text("Decide por mí").recipe(.title).lineLimit(oneLine).minimumScaleFactor(DS.ParaTiB.doorTitleScale) }
                    else {
                        HStack(spacing: DS.Space.s2) {
                            Image(systemName: DS.Symbol.decide).foregroundStyle(DS.brandMoon).accessibilityHidden(true)
                            Text("Decide por mí").recipe(.title)
                        }
                        .font(DS.TextRecipe.title.font)
                        .lineLimit(oneLine).minimumScaleFactor(DS.ParaTiB.doorTitleScale)
                    }
                    (offline && posters.isEmpty ? Text("Sin conexión por ahora.") : Text("Tres que caben · Una por una"))
                        .recipe(.secondary, color: DS.textMuted)
                        .lineLimit(oneLine).minimumScaleFactor(DS.ParaTiB.doorTitleScale)
                }
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                Spacer(minLength: 0)
                if !more.isEmpty, !typeSize.isAccessibilitySize {
                    DecideStrip(posters: more)
                    Image(systemName: "chevron.right").font(DS.TextRecipe.section.font).foregroundStyle(DS.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)   // DM-A: 16, el mismo aire que el margen de la pantalla (antes 20: le quitaba ancho al nombre)
            .background {
                // Un brillo del color de acento desde el abanico, como el color de «La temporada»: la puerta se ve como puerta.
                Color.clear.dsCard(.card)
                    .overlay(LinearGradient(colors: [DS.accent.opacity(DS.ParaTiB.doorGlow), .clear], startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, inset ?? DS.Space.gutter)
        .accessibilityIdentifier(id)
    }
}

/// La tira de carteles de la puerta de «Decide por mí» en la Mac: de lo que sale en la hoja, cada vez más claros hacia el
/// texto (los de la derecha, nítidos).
/// Muestra solo los que caben (los más nítidos, los de la derecha): en el iPad la tira de ocho aplastaba el título a una letra
/// por renglón (17 nov 2026). El texto de al lado lleva `layoutPriority(1)` y la tira toma lo que sobra.
/// Cuántos caben se cuenta con el ancho libre (cada cartel mide lo mismo), no se prueba: antes un `ViewThatFits` armaba hasta
/// ocho tiras de pósters cada vez que se dibujaba Explorar (revisión de velocidad de la Mac, 22 nov 2026).
struct DecideStrip: View {
    let posters: [String]
    @State private var width: CGFloat = 0

    var body: some View {
        let step = DS.ParaTiB.stripPoster + DS.Space.s2
        let fits = max(0, min(posters.count, Int(((width + DS.Space.s2) / step).rounded(.down))))
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: (DS.ParaTiB.stripPoster / DS.Poster.aspect).rounded(.up))   // el alto de un cartel: no estira la fila
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay(alignment: .trailing) { if fits > 0 { row(Array(posters.suffix(fits))) } }
            .accessibilityHidden(true)
    }

    private func row(_ shown: [String]) -> some View {
        HStack(spacing: DS.Space.s2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, url in
                PosterView(url: url, title: "", decorative: true)
                    .frame(width: DS.ParaTiB.stripPoster)
                    .opacity(DS.ParaTiB.stripFadeFrom + (1 - DS.ParaTiB.stripFadeFrom) * Double(i + 1) / Double(shown.count))
            }
        }
        .fixedSize()
    }
}
