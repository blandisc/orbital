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
                Text("La nube las baja por ti: suele tardar de minutos a horas.").recipe(.footnote)
            }
            .padding(.top, DS.Space.s3)
            rows
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sources-to-request")
    }
}

/// Una versión por pedir: idioma y calidad, tamaño y lo que la distingue (como las demás), y «Pedirlo y avisarme». Ya pedida,
/// su estado («Bajando en la nube · 42 %») en lugar del botón: no se pide dos veces. Tocar el nombre abre su tarjeta.
struct VersionRequestRow: View {
    let title: Text
    let option: VersionOption
    /// El pedido de esta versión, si ya existe («Bajando en Real-Debrid · 42 %» con su barra), como en la ficha.
    var status: DebridRequestStatus?
    let request: () -> Void
    let open: () -> Void
    @Environment(\.locale) private var locale   // el idioma de la app («2,9 GB»)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    title.recipe(.cardTitle, color: DS.text)
                    Text(verbatim: VersionText.facts(option, locale: locale)).recipe(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let status {
                status.accessibilityIdentifier("version-request-status")   // la misma pieza que la ficha y «Tus pedidos»
            } else {
                Button(action: request) { Label("Pedir a la nube", systemImage: DS.Symbol.cloud).frame(maxWidth: .infinity) }
                    .dsSecondaryButton().dsControlSize(.large)
                    .accessibilityIdentifier("version-request")
            }
        }
        .padding(DS.Space.s3)
        .dsCard(translucent: true)
        .accessibilityElement(children: .contain)
    }
}

/// «Hay latino, pero hay que pedirlo a la nube» (Fernando, 12 nov, Los Simpson T11E2: «me salen puros episodios en inglés»):
/// tu idioma existe, pero ninguna de las que arrancan al instante lo trae. Arriba de la lista, con la nube y «Pedir a la nube»
/// (la misma acción de «Hay que pedirlas»); ya pedida, cómo va. Solo cuando pasa: si tu idioma arranca ya, no sale.
struct VersionYoursAside: View {
    /// «🇲🇽 latino», ya con su bandera.
    let language: Text
    let option: VersionOption
    var status: DebridRequestStatus?
    let request: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s3) {
            IconBeside(symbol: DS.Symbol.cloud, color: DS.accent) {
                Text("Hay \(language), pero hay que pedirlo a la nube").recipe(.labelLarge, color: DS.text).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: VersionText.facts(option, locale: locale)).recipe(.caption)
            }
            if let status {
                status.accessibilityIdentifier("sources-yours-status")
            } else {
                Button(action: request) { Label("Pedir a la nube", systemImage: DS.Symbol.cloud).frame(maxWidth: .infinity) }
                    .dsSecondaryButton().dsControlSize(.large)
                    .accessibilityIdentifier("sources-yours-request")
            }
        }
        .padding(DS.Space.s3)
        .dsCard(translucent: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sources-yours-aside")
    }
}

/// LN2 · «Hay latino, pero Real-Debrid no lo dejó bajar» (Fernando, 18 nov, Los Simpson T37E3): tu idioma existía, pero la
/// única que lo trae la rechazó Real-Debrid. Hermana de `VersionYoursAside`, en su lugar y con el triángulo de «no lo dejó
/// bajar»; sin «Pedir a la nube», porque pedirla otra vez falla igual. La TV dice lo mismo en la nota de la ficha.
struct VersionYoursRefused: View {
    /// «🇲🇽 latino», ya con su bandera.
    let language: Text

    var body: some View {
        IconBeside(symbol: DebridRequestWords.Icon.refused, color: DS.warning) {
            Text("Hay \(language), pero Real-Debrid no lo dejó bajar").recipe(.labelLarge, color: DS.text).fixedSize(horizontal: false, vertical: true)   // edición: un rechazo solo existe con pedidos a la nube (Real-Debrid)
            Text("Prueba otra versión").recipe(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s3)
        .dsCard(translucent: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sources-yours-refused")
    }
}
