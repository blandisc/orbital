import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// CX2-A · tu clave entre tus aparatos Apple, arriba de la página de Real-Debrid. Otra cuenta en la copia compartida: «Tu iPad
/// cambió la clave de Real-Debrid · Usar la nueva / Seguir con la de este iPhone». Nunca cambia sola.
struct DebridSharedPrompt: View {
    @State private var debrid: ModelObserver<DebridModel>
    @Environment(AppEnvironment.self) private var env

    init(debrid: DebridModel) { _debrid = State(wrappedValue: ModelObserver(debrid)) }

    var body: some View {
        let model = debrid.model
        let _ = env.services.track()
        if case .differs(let from, let theirs, let mine) = model.shared {
            Section {
                DSProblem(title: changedTitle(from), detail: detail(theirs, mine), symbol: "key.horizontal") {
                    Button { Task { await model.useShared() } } label: { Text("Usar la nueva").frame(maxWidth: .infinity) }
                        .dsProblemFix(primary: true)
                        .disabled(model.check == .checking)
                        .accessibilityIdentifier("debrid-shared-use")
                    Button { model.keepLocal() } label: { DeviceWords.text("Seguir con la de este iPhone", mac: "Seguir con la de esta Mac").frame(maxWidth: .infinity) }
                        .dsProblemFix(primary: false)
                        .accessibilityIdentifier("debrid-shared-keep")
                }
                .accessibilityIdentifier("debrid-shared-differs")
            }
            .listRowBackground(DS.surface)
        }
    }

    /// IOS-11: «iPad de Fernando cambió la clave…» con el nombre; de una copia de antes, el tipo, salvo que sea el mismo tipo
    /// que este aparato («Tu iPad cambió…» leído en un iPad parecía hablar de sí mismo).
    private func changedTitle(_ from: String) -> Text {
        if let device = DebridModel.deviceWord(from) {
            return from == env.services.platform ? Text("Tu clave de Real-Debrid cambió en otro de tus aparatos Apple")
                                                 : Text("Tu \(device) cambió la clave de Real-Debrid")
        }
        return from.isEmpty ? Text("Tu clave de Real-Debrid cambió en otro de tus aparatos Apple") : Text("\(from) cambió la clave de Real-Debrid")
    }

    /// Se compara la cuenta, no las letras: «La nueva es de la cuenta ana · la de este iPhone, de fer».
    private func detail(_ theirs: DebridStatus, _ mine: DebridStatus?) -> Text {
        let mac = ThisDevice.platform == "mac"   // IOS-12
        guard let mine else {
            return mac ? Text("La nueva es de la cuenta \(theirs.username). La de esta Mac ya no sirve.")
                       : Text("La nueva es de la cuenta \(theirs.username). La de este iPhone ya no sirve.")
        }
        return mac ? Text("La nueva es de la cuenta \(theirs.username) · la de esta Mac, de \(mine.username).")
                   : Text("La nueva es de la cuenta \(theirs.username) · la de este iPhone, de \(mine.username).")
    }
}

/// Sin clave aquí y con una en tus aparatos Apple: «Usar la clave de tus aparatos Apple», debajo de «Pega tu clave» (las dos,
/// siempre; nunca solo una). Solo aparece cuando la clave ya llegó y Real-Debrid la aceptó (TEC-18).
struct DebridSharedOffer: View {
    @State private var debrid: ModelObserver<DebridModel>
    @Environment(AppEnvironment.self) private var env
    /// En la guía va en su tarjeta (fuera de una lista).
    var carded = false

    init(debrid: DebridModel, carded: Bool = false) { _debrid = State(wrappedValue: ModelObserver(debrid)); self.carded = carded }

    var body: some View {
        let model = debrid.model
        let _ = env.services.track()
        if case .offer(_, let account) = model.shared {
            Button { Task { await model.useShared() } } label: {
                TorrentioRowLabel(title: Text("Usar la clave de tus aparatos Apple"), detail: Text("De tu llavero de iCloud · cuenta \(account.username)"), action: true)
            }
            .disabled(model.check == .checking)
            .accessibilityIdentifier("debrid-shared-offer")
            .modifier(OfferCard(on: carded))
        }
    }
}

private struct OfferCard: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.buttonStyle(.plain).padding(DS.Space.s3).dsCard(translucent: true) } else { content }
    }
}
