import SwiftUI

/// La marca de un idioma en Ajustes › Idiomas (IM-A, Fernando, 24 nov 2026: «otra forma de no poner el emoji de las banderas,
/// se ve muy genérico»): sus letras («ES», «EN», «LAT», «JA») en un círculo de su color, como las placas de la app. El
/// idioma original es un globo. El color sale del idioma, así el mismo siempre se ve igual.
struct LanguageMark: View {
    let code: String
    var large = false

    var body: some View {
        let side = large ? DS.LanguageMarkLook.large : DS.SettingsLook.rowIcon
        let tint = Self.tint(code)
        ZStack {
            Circle().fill(tint.opacity(DS.LanguageMarkLook.wash))
            Circle().strokeBorder(tint.opacity(DS.LanguageMarkLook.ring), lineWidth: DS.Stroke.regular)
            if code == "original" {
                Image(systemName: "globe").font((large ? DS.TextRecipe.section : DS.TextRecipe.label).font).foregroundStyle(tint)
            } else {
                Text(verbatim: Self.letters(code)).font((large ? DS.TextRecipe.labelLarge : DS.TextRecipe.badge).font)
                    .foregroundStyle(tint).minimumScaleFactor(DS.Size.statScale).lineLimit(1)
                    .padding(.horizontal, DS.Space.s1)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    /// «es-419» → «LAT», «es-ES» → «CAS», «pt-BR» → «BR», «en» → «EN».
    static func letters(_ code: String) -> String {
        switch code.lowercased() {
        case "es-419", "es-mx": return "LAT"
        case "es-es": return "CAS"
        case "pt-br": return "BR"
        default: return String(code.split(separator: "-").first ?? Substring(code)).uppercased()
        }
    }

    /// El color de un idioma: fijo para los nuestros y, para los demás, uno de la paleta según sus letras.
    static func tint(_ code: String) -> Color {
        let palette = [DS.ListTint.library, DS.ListTint.bookmark, DS.ListTint.spark, DS.ListTint.flame, DS.ListTint.list, DS.ListTint.addon]
        switch code.lowercased() {
        case "original": return DS.ListTint.calendar
        case "es", "es-419", "es-mx": return DS.ListTint.trend
        case "es-es": return DS.ListTint.watching
        case "en": return DS.ListTint.series
        default: return palette[letters(code).unicodeScalars.reduce(0) { $0 + Int($1.value) } % palette.count]
        }
    }
}
