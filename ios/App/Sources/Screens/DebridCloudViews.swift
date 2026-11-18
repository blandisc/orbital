import SwiftUI
import OrbitalAddons
import OrbitalModels

/// DN1 · «Tu nube» (Fernando, 18 nov 2026: «que pueda funcionar con TorBox, AllDebrid y Real-Debrid. Solamente esos tres»).
/// Las mismas palabras que la TV (`debridChooseMenu` y `debridCloudsMenu` en `menus-cloud.js`): sin nube, primero cuál de
/// las tres o dónde sacar una, y nunca «Real-Debrid» solo antes de elegir; con nube, las tres con «La que usas», «Clave
/// guardada» o «Sin clave». Lo usan la guía (en su hoja) y Ajustes › Cuentas.

/// Sin nube todavía: «Ya tengo cuenta» (conectar la que tienes) y «Todavía no tengo» (su página de planes).
struct DebridCloudChooser: View {
    @State private var observer: ModelObserver<DebridModel>
    @State private var explaining = false

    init(debrid: DebridModel) { _observer = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = observer.model
        Section {
            ForEach(DebridService.allCases) { cloud in
                Button { model.target = cloud } label: {
                    HStack(spacing: DS.Space.s3) {
                        DSCloudMark(cloud: cloud)
                        TorrentioRowLabel(title: Text(verbatim: cloud.name), detail: Text("Conectar con tu clave · \(cloud.keyPlace)"))   // no-es-título: el nombre de la nube
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cloud-connect-\(cloud.rawValue)")
            }
        } header: { Text("Ya tengo cuenta") } footer: {
            Text("Para que los videos arranquen al instante, Orbital usa un servicio de pago que guarda películas y series: tu nube. Sirve cualquiera de estos tres.")
        }
        .listRowBackground(DS.surface)
        Section {
            ForEach(DebridService.allCases) { cloud in
                Link(destination: cloud.signupURL) {
                    HStack(spacing: DS.Space.s3) {
                        DSCloudMark(cloud: cloud)
                        TorrentioRowLabel(title: Text("Ver \(cloud.name)"), detail: Text(verbatim: cloud.site))   // no-es-título: el nombre de la nube
                        Spacer(minLength: DS.Space.s2)
                        Image(systemName: "arrow.up.right").foregroundStyle(DS.textMuted).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("cloud-signup-\(cloud.rawValue)")
            }
        } header: { Text("Todavía no tengo") } footer: { Text("Se paga en su página. Cuando tengas tu clave, vuelve aquí.") }
        .listRowBackground(DS.surface)
        Section {
            Button { explaining = true } label: { Text("¿Qué es esto?").foregroundStyle(DS.text) }
                .accessibilityIdentifier("cloud-explain")
        }
        .listRowBackground(DS.surface)
        .sheet(isPresented: $explaining) { DebridCloudsExplainer() }
    }
}

/// Con nube: las tres, cuál usas y cuáles ya tienen clave. Tocar otra con clave cambia ya; sin clave, pide conectarla.
struct DebridCloudList: View {
    @State private var observer: ModelObserver<DebridModel>
    @State private var explaining = false

    init(debrid: DebridModel) { _observer = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = observer.model
        Section {
            ForEach(DebridService.allCases) { cloud in
                Button { Task { await model.use(cloud) } } label: {
                    HStack(spacing: DS.Space.s3) {
                        DSCloudMark(cloud: cloud)
                        Text(verbatim: cloud.name).foregroundStyle(DS.text)   // no-es-título: el nombre de la nube
                        Spacer(minLength: DS.Space.s2)
                        Text(Self.value(cloud, model)).foregroundStyle(cloud == model.service ? DS.success : DS.textMuted)
                        if cloud == model.service { Image(systemName: "checkmark").foregroundStyle(DS.success).accessibilityHidden(true) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(cloud == model.service)
                .accessibilityAddTraits(cloud == model.service ? .isSelected : [])
                .accessibilityIdentifier("cloud-\(cloud.rawValue)")
            }
            Button { explaining = true } label: { Text("¿Qué es esto?").foregroundStyle(DS.text) }
                .accessibilityIdentifier("cloud-explain")
        } header: { Text("Tu nube") } footer: {
            Text("Es la que hace que los videos arranquen al instante. Orbital funciona con estas tres; tú pagas la que elijas en su página.")
        }
        .listRowBackground(DS.surface)
        .sheet(isPresented: $explaining) { DebridCloudsExplainer() }
    }

    static func value(_ cloud: DebridService, _ model: DebridModel) -> LocalizedStringKey {
        cloud == model.service ? "La que usas" : model.hasKey(cloud) ? "Clave guardada" : "Sin clave"
    }
}

/// «¿Qué es esto?» de «Tu nube»: los cuatro puntos de la TV (`DEBRID_EXPLAIN.clouds`). No recomienda ninguna.
struct DebridCloudsExplainer: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s3) {   // ds-exception: hoja de tarjetas, como DebridExplainer
                DSSheetHeader(title: Text("¿Qué es esto?")).padding(.bottom, DS.Space.s1)
                DSExplainerCard(symbol: "icloud.fill", tint: DS.ListTint.series, title: Text("Las tres hacen lo mismo"),
                                detail: Text("Guardan películas y series en sus servidores: lo que ya tienen arranca al instante y lo que no, se lo pides y lo bajan."))
                DSExplainerCard(symbol: "line.3.horizontal.decrease", tint: DS.ListTint.calendar, title: Text("Cada una deja bajar cosas distintas"),
                                detail: Text("A veces una no deja bajar algo que otra sí. Si te pasa seguido, prueba otra."))
                DSExplainerCard(symbol: "creditcard.fill", tint: DS.ListTint.bookmark, title: Text("Cada una se paga en su página"),
                                detail: Text("Real-Debrid en real-debrid.com, TorBox en torbox.app y AllDebrid en alldebrid.com. Orbital no cobra nada."))   // edición: solo con instantStreams (la hoja vive en Cuentas › Tu nube)
                DSExplainerCard(symbol: DS.Symbol.cloudFill, tint: DS.ListTint.trophy, title: Text("Lo que pediste se queda en su nube"),
                                detail: Text("Si te cambias, lo que pediste en la otra sigue allá: lo ves si vuelves a ella."))
            }
            .dsSheetContent()
        }
        .scrollBounceBehavior(.basedOnSize)
        .fittedScrollSheet()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cloud-explainer")
    }
}

/// La hoja «Tu nube» de la guía: la misma página de Ajustes › Cuentas (elegir, conectar), con «Listo» para cerrar.
struct DebridCloudSheet: View {
    let debrid: DebridModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DebridAccountView(debrid: debrid)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.accessibilityIdentifier("cloud-sheet-done") } }
        }
    }
}
