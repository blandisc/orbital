import SwiftUI

/// 1 · Bienvenida: la marca y una frase. Un solo botón.
struct OnboardingWelcome: View {
    let next: () -> Void

    var body: some View {
        GuidePage(title: Text(verbatim: ""), primary: Text("Empezar"), next: next) {
            VStack(alignment: .leading, spacing: DS.Space.s4) {
                OrbitalWordmark(size: DS.Size.wordmark, animated: true).foregroundStyle(DS.text)
                Text("Tus películas y series, en tu bolsillo y en tu TV.")
                    .font(DS.TextRecipe.title.font).foregroundStyle(DS.text)
            }
            .padding(.top, DS.Space.s10)
        }
    }
}

/// 2 · Cómo funciona: las tres piezas, qué hace cada una y cuáles son obligatorias.
struct OnboardingHowItWorks: View {
    let step: (current: Int, total: Int)
    /// En la Mac la app no se conecta con tu Orbital: la pieza de la TV no sale.
    let showsTV: Bool
    let next: () -> Void

    var body: some View {
        GuidePage(title: Text("Cómo funciona"), message: Text("Orbital junta tres piezas. Te ayudamos a conectar cada una."), step: step, next: next) {
            VStack(spacing: DS.Space.s3) {
                GuidePiece(symbol: "bolt.horizontal.circle", tint: DS.ListTint.flame, title: Text(verbatim: "Real-Debrid"),
                           detail: Text("De aquí salen los videos."), tag: Text("Obligatorio"))
                GuidePiece(symbol: "checkmark.seal", tint: DS.ListTint.chart, title: Text(verbatim: "Trakt"),
                           detail: Text("Tu avance en la nube, en todos tus aparatos."), tag: Text("Obligatorio"))
                if showsTV {
                    GuidePiece(symbol: "tv", tint: DS.ListTint.series, title: Text("Tu Orbital en la TV"),
                               detail: Text("Manda lo que ves a la pantalla grande y usa el iPhone de control."), tag: Text("Opcional"))
                }
            }
        }
    }
}
