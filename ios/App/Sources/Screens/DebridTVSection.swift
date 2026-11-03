import SwiftUI
import OrbitalCore
import OrbitalModels

/// K1 · Ajustes › Cuentas › Real-Debrid › «Tu TV»: «Pasar a la TV» (tu clave de aquí a la TV, preguntando antes) y «Usar la de
/// la TV» (la de la TV aquí, comprobada como una pegada). Solo con la llave de este aparato y una TV que reparte llaves
/// (`DebridModel.canShareWithTV`); en Plus o sin TV no aparece. La clave nunca se enseña: solo sus últimas letras.
struct DebridTVSection: View {
    @State private var debrid: ModelObserver<DebridModel>
    @State private var confirmPass = false
    @State private var confirmUse = false
    @Environment(AppEnvironment.self) private var env

    init(debrid: DebridModel) { _debrid = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = debrid.model
        let _ = env.services.track()
        if model.canShareWithTV {
            Section {
                if model.hasToken {
                    Button { confirmPass = true } label: {
                        TorrentioRowLabel(title: Text("Pasar a la TV"), detail: Text("Tu TV usará la clave de este iPhone"))
                    }
                    .disabled(model.tvShare == .working)
                    .accessibilityIdentifier("debrid-pass-to-tv")
                }
                Button { if model.hasToken { confirmUse = true } else { Task { await model.useTVKey() } } } label: {
                    TorrentioRowLabel(title: Text("Usar la de la TV"), detail: Text("Este iPhone usará la clave de tu TV"))
                }
                .disabled(model.tvShare == .working)
                .accessibilityIdentifier("debrid-use-tv")
                result(model)
            } header: { Text("Tu TV") } footer: { Text("Real-Debrid revisa la clave antes de guardarla. Nunca se muestra completa.") }
            .listRowBackground(DS.surface)
            .onAppear { model.resetTVShare() }
            .confirmationDialog("Tu TV usará esta clave", isPresented: $confirmPass, titleVisibility: .visible) {
                Button("Pasar a la TV") { Task { await model.passToTV() } }
                Button("Cancelar", role: .cancel) {}
            } message: { Text("Termina en ••••\(tail(model)). Si Real-Debrid no la reconoce, tu TV se queda con la que tenía.") }
            .confirmationDialog("Este iPhone usará la clave de tu TV", isPresented: $confirmUse, titleVisibility: .visible) {
                Button("Usar la de la TV") { Task { await model.useTVKey() } }
                Button("Cancelar", role: .cancel) {}
            } message: { Text("Reemplaza la de este iPhone si Real-Debrid la acepta con Premium.") }
        }
    }

    private func tail(_ model: DebridModel) -> String { model.keyTail ?? "····" }

    @ViewBuilder private func result(_ model: DebridModel) -> some View {
        switch model.tvShare {
        case .idle: EmptyView()
        case .working: DSInlineProgress(text: Text("Hablando con tu TV…"))
        case .passed(let tv):
            DSNotice(text: tv.premium ? "Tu TV ya usa tu clave · termina en \(tv.tail) · Premium" : "Tu TV ya usa tu clave · termina en \(tv.tail)", tone: .success)
                .accessibilityIdentifier("debrid-tv-result")
        case .used: DSNotice(text: "Listo: este iPhone ya usa la clave de tu TV", tone: .success).accessibilityIdentifier("debrid-tv-result")
        case .failed(let why): DSNotice(verbatim: env.message(why), tone: .warn).accessibilityIdentifier("debrid-tv-result")
        }
    }
}
