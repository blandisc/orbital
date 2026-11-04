import SwiftUI
import OrbitalCore

/// D4 · «Canjear puntos» en su hoja, no en una pregunta del sistema (Fernando, 3 nov, probando la 1729): qué pasa (tus puntos
/// se vuelven días de Premium), que no se deshace, y el botón para hacerlo. Una confirmación importante va en una hoja propia
/// (regla del sistema). La hoja mide lo que trae (`fittedSheet`). Nunca en las pruebas contra Real-Debrid: solo la demo.
struct DebridRedeemSheet: View {
    /// «1200»: tus puntos, ya escritos en el idioma de la app (`Strings.count`).
    let points: String
    let redeem: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s4) {
            DSSheetHeader(title: Text("¿Canjear tus puntos?"))
            HStack(alignment: .top, spacing: DS.Space.s2) {
                side("gift.fill", DS.ListTint.trophy, Text("\(points) puntos"))
                Image(systemName: "arrow.forward").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.textMuted)
                    .frame(height: DS.Explainer.flowTile).accessibilityHidden(true)
                side("calendar.badge.plus", DS.ListTint.calendar, Text("Días de Premium"))
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Space.s4)
            .dsCard(.card)
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                IconBeside(symbol: "arrow.triangle.2.circlepath") {
                    Text("Real-Debrid cambia todos tus puntos por días de Premium.").recipe(.secondary, color: DS.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                IconBeside(symbol: "exclamationmark.triangle", color: DS.warning) {
                    Text("No se puede deshacer.").recipe(.secondary, color: DS.text)
                }
            }
            VStack(spacing: DS.Space.s2) {
                Button(action: redeem) { Label("Canjear puntos", systemImage: "gift").frame(maxWidth: .infinity) }
                    .dsPrimaryButton(size: .large)
                    .accessibilityIdentifier("debrid-redeem-confirm")
                Button(action: close) { Text("Ahora no").frame(maxWidth: .infinity) }
                    .dsSecondaryButton().controlSize(.large)
            }
        }
        .dsSheetContent(bottom: false)   // a la medida: el margen de la barra de inicio ya separa lo último
        .fittedSheet()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("debrid-redeem-sheet")
    }

    private func side(_ symbol: String, _ tint: Color, _ label: Text) -> some View {
        VStack(spacing: DS.Space.s2) {
            DSIconTile(symbol: symbol, tint: tint, side: DS.Explainer.flowTile)
            label.recipe(.label, color: DS.text).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}
