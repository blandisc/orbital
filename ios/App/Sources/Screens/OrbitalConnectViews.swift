import SwiftUI
import OrbitalCore
import OrbitalModels

/// CX7-A · «¿Cómo se llama este aparato?», ya escrito con la sugerencia («iPad de Fernando»), hasta 60 letras: así en la lista
/// de la TV sabes cuál es cuál (iOS ya no le dice a la app el nombre real del aparato).
struct DeviceNameField: View {
    @Binding var name: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("¿Cómo se llama este aparato?").recipe(.footnote, color: DS.textMuted)
            TextField("Nombre", text: Binding(get: { name }, set: { name = String($0.prefix(Services.deviceNameLimit)) }))
                .textInputAutocapitalization(.words).autocorrectionDisabled()
                .accessibilityIdentifier("orbital-device-name")
        }
    }
}

/// CX8-A · «Darle su propia conexión» sin volver a escanear: el nombre, «Confirma en tu TV» mientras la TV pregunta y lo que
/// contestó. Si dice que no o no contesta, en palabras y con «Escanear».
struct OrbitalUpgradeSheet: View {
    let scan: () -> Void
    @State private var upgrade = ModelObserver(OrbitalUpgradeModel(AppEnvironment.shared.services))
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = upgrade.model
        NavigationStack {
            Form {
                switch model.stage {
                case .naming:
                    Section {
                        DeviceNameField(name: Binding(get: { model.name }, set: { model.name = $0 }))
                    } footer: { Text("Tu TV te pregunta en su pantalla. Una vez por aparato.") }
                    .listRowBackground(DS.surface)
                    Section {
                        Button { Task { await model.start() } } label: { Text("Pedírsela a tu TV").frame(maxWidth: .infinity) }
                            .dsPrimaryButton(size: .large)
                            .accessibilityIdentifier("orbital-upgrade-start")
                    }
                    .listRowBackground(Color.clear)
                case .waiting:
                    Section {
                        DSInlineProgress(text: Text("Confirma en tu TV"))
                        Text("Tu TV pregunta en su pantalla «¿Darle su propia conexión a \(model.name)?». Elige «Darle su propia conexión» con el control. La pregunta dura 3 minutos.").recipe(.footnote, color: DS.textMuted)
                        // AU3-A (Fernando, 3 nov): la TV no pausa lo que ves para preguntar; se dice aquí, con la salida de siempre.
                        Text("Si estás viendo algo en la TV, ciérralo para contestar.").recipe(.footnote, color: DS.textMuted)
                            .accessibilityIdentifier("orbital-upgrade-close-video")
                        Button(action: scan) { Label("Escanear en su lugar", systemImage: "qrcode.viewfinder") }
                            .accessibilityIdentifier("orbital-upgrade-scan-instead")
                    }
                    .listRowBackground(DS.surface)
                    .accessibilityIdentifier("orbital-upgrade-waiting")
                case .done:
                    Section {
                        Label { Text("Listo: este iPhone ya tiene su propia conexión") } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success) }
                            .accessibilityIdentifier("orbital-upgrade-done")
                    }
                    .listRowBackground(DS.surface)
                case .denied: answer(Text("Tu TV dijo que no"), Text("Nada cambió. Si fue un error, pídeselo otra vez o escanea su código."), model)
                case .timedOut: answer(Text("Tu TV no contestó a tiempo"), Text("Revisa que esté prendida y pídeselo otra vez, o escanea su código."), model)
                case .failed(let why): answer(Text(verbatim: env.message(why)), nil, model)
                }
            }
            .tint(DS.accent)
            .scrollContentBackground(.hidden).background(Backdrop())
            // Fernando, 3 nov, probando la 1729: la hoja quedaba a media pantalla con un hueco abajo. Mide lo que trae.
            .contentMargins(.bottom, DS.Space.s2, for: .scrollContent)   // el pie de la lista no deja otro hueco
            .fittedScrollSheet()
            .readableListWidth()   // iPad y Mac: en su columna, como toda lista
            .dsInlineTitle("Darle su propia conexión")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.stage == .done ? "Listo" : "Cancelar") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(model.stage == .waiting)
        #if DEBUG
        .task { if Demo.isOn, Demo.cx?.hasPrefix("upgrade") == true { await model.start() } }
        #endif
    }

    private func answer(_ title: Text, _ detail: Text?, _ model: OrbitalUpgradeModel) -> some View {
        Section {
            DSProblem(title: title, detail: detail, symbol: "tv.and.mediabox") {
                Button { model.reset() } label: { Text("Pedírsela otra vez").frame(maxWidth: .infinity) }
                    .dsProblemFix(primary: true)
                Button(action: scan) { Label("Escanear", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                    .dsProblemFix(primary: false)
                    .accessibilityIdentifier("orbital-upgrade-scan")
            }
            .accessibilityIdentifier("orbital-upgrade-answer")
        }
        .listRowBackground(DS.surface)
    }
}
