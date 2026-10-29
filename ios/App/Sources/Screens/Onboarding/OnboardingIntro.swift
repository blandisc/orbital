import SwiftUI

/// 1 · Bienvenida: la marca y una frase. Un solo botón.
struct OnboardingWelcome: View {
    let next: () -> Void

    var body: some View {
        GuidePage(title: Text(verbatim: ""), primary: Text("Empezar"), next: next) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                OrbitalWordmark(size: DS.Size.wordmark, animated: true).foregroundStyle(DS.text)
                Text("Tus películas y series en tu bolsillo.")
                    .font(DS.TextRecipe.title.font).foregroundStyle(DS.text)
            }
            .padding(.top, DS.Space.s10)
        }
    }
}

/// 2 · Cómo funciona: las dos piezas y qué hace cada una. La app es de una sola pieza: nada de la TV.
struct OnboardingHowItWorks: View {
    let step: (current: Int, total: Int)
    let next: () -> Void

    var body: some View {
        GuidePage(title: Text("Cómo funciona"), message: Text("Orbital junta dos piezas. Te ayudamos a conectar cada una."), step: step, next: next) {
            VStack(spacing: DS.Space.s3) {
                GuidePiece(symbol: "bolt.horizontal.circle", tint: DS.ListTint.flame, title: Text(verbatim: "Real-Debrid"),
                           detail: Text("De aquí salen los videos."), tag: Text("Obligatorio"))
                GuidePiece(symbol: "checkmark.seal", tint: DS.ListTint.chart, title: Text(verbatim: "Trakt"),
                           detail: Text("Tu avance en la nube, en todos tus aparatos."), tag: Text("Obligatorio"))
            }
        }
    }
}
