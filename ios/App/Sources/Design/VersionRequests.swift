import SwiftUI
import OrbitalCore
import OrbitalModels

/// T8-A · «Hay que pedirlas · tardan» (Fernando, 3 nov, probando la 1729: «no encuentro nada que no esté al instante»): las
/// versiones que Real-Debrid aún no tiene, después de las que arrancan al instante. Antes la de al instante tapaba a las demás
/// de su idioma y calidad. Cada una se pide; nunca se reproduce (abrirla saca el video de aviso de Real-Debrid).
struct VersionRequestGroup<Rows: View>: View {
    @ViewBuilder var rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            VStack(alignment: .leading, spacing: DS.Space.s1) {
                DSGroupLabel(title: Text("Hay que pedirlas · tardan"))
                Text("La nube las baja por ti: de minutos a días.").recipe(.footnote)
            }
            .padding(.top, DS.Space.s3)
            rows
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sources-to-request")
    }
}

/// Una versión por pedir: idioma y calidad, tamaño y lo que la distingue (como las demás), y «Pedirlo y avisarme». Ya pedida,
/// su estado («Bajando · 42 %») en lugar del botón: no se pide dos veces. Tocar el nombre abre su tarjeta.
struct VersionRequestRow: View {
    let title: Text
    let option: VersionOption
    /// El pedido de esta versión, si ya existe («Bajando en Real-Debrid · 42 %» con su barra), como en la ficha.
    var status: DebridRequestStatus?
    let request: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    title.recipe(.cardTitle, color: DS.text)
                    Text(verbatim: VersionChip.facts(option)).recipe(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let status {
                status.accessibilityIdentifier("version-request-status")   // la misma pieza que la ficha y «Tus pedidos»
            } else {
                Button(action: request) { Label("Pedir a la nube", systemImage: "arrow.down.circle").frame(maxWidth: .infinity) }
                    .dsSecondaryButton().controlSize(.large)
                    .accessibilityIdentifier("version-request")
            }
        }
        .padding(DS.Space.s3)
        .dsCard(translucent: true)
        .accessibilityElement(children: .contain)
    }
}
