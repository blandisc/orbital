import SwiftUI

/// La muestra viva de Ajustes › Idiomas (IP-C, Fernando, 24 nov 2026: «una pequeña animación que cambie cada vez que tocas
/// español o English… un póster falso que cambie de título»). Con la app: una barra de pestañas de juguete cuyas palabras
/// cambian una tras otra. Con los títulos: un póster de mentira que da una vuelta y sale con el nombre y la sinopsis en el
/// idioma nuevo. Con «Reducir movimiento», solo cambia el texto.
struct LanguagePreview: View {
    enum Kind { case app, poster }
    let kind: Kind
    /// «es» o «en».
    let language: String
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var spin: Double = 0

    var body: some View {
        Group {
            switch kind {
            case .app: tabs
            case .poster: poster
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Space.s2)
        .accessibilityHidden(true)   // es adorno: lo elegido ya lo dicen los mosaicos
        .onChange(of: language) {
            withAnimation(DS.Motion.spring(reduce)) { spin += reduce ? 0 : 360 }
        }
    }

    private var english: Bool { language == "en" }

    /// La barra de pestañas de juguete: cada palabra cambia un poco después que la anterior.
    private var tabs: some View {
        let words = english ? ["Home", "Explore", "Search"] : ["Inicio", "Explorar", "Buscar"]
        let symbols = ["house.fill", "sparkles", "magnifyingglass"]
        return HStack(spacing: DS.Space.s2) {
            ForEach(0..<3, id: \.self) { i in
                VStack(spacing: DS.Space.s1) {
                    Image(systemName: symbols[i]).font(DS.TextRecipe.cardTitle.font)
                        .foregroundStyle(i == 0 ? DS.text : DS.textMuted)
                        .frame(height: DS.SettingsLook.rowIcon)   // los tres a la misma altura: las palabras quedan alineadas
                        .symbolEffect(.bounce, value: reduce ? "" : language)
                    Text(verbatim: words[i]).recipe(.badge, color: i == 0 ? DS.text : DS.textMuted)
                        .id(words[i])
                        .transition(.blurReplace)
                        .animation(DS.Motion.spring(reduce)?.delay(Double(i) * DS.LanguagePreview.step), value: language)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, DS.Space.s2)
        .background(Capsule().fill(DS.hairline))
    }

    /// El póster de mentira: da una vuelta y sale con su nombre en el idioma nuevo.
    private var poster: some View {
        HStack(spacing: DS.Space.s4) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .fill(LinearGradient(colors: [DS.ListTint.calendar, DS.ListTint.series], startPoint: .top, endPoint: .bottom))
                Image(systemName: "wind").font(DS.TextRecipe.title.font).foregroundStyle(DS.text.opacity(DS.Opacity.faint))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(verbatim: english ? "Spirited Away" : "El viaje de Chihiro")
                    .recipe(.badge, color: DS.text).lineLimit(2).minimumScaleFactor(DS.Size.statScale)
                    .padding(DS.Space.s1)
                    .id(language).transition(.blurReplace)
            }
            .frame(width: DS.LanguagePreview.posterWidth, height: DS.LanguagePreview.posterWidth * DS.LanguagePreview.posterTall)
            .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                Text(verbatim: english ? "Spirited Away" : "El viaje de Chihiro").recipe(.cardTitle, color: DS.text)
                    .id("t" + language).transition(.blurReplace)
                Text(verbatim: english ? "A girl wanders into a world of spirits and must find her way home."
                                       : "Una niña entra a un mundo de espíritus y tiene que encontrar cómo volver.")
                    .recipe(.footnote, color: DS.textMuted).lineLimit(3)
                    .id("s" + language).transition(.blurReplace)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(DS.Motion.spring(reduce), value: language)
    }
}
