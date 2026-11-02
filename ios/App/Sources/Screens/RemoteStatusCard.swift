import SwiftUI
import OrbitalCore
import OrbitalModels

/// El control de la TV cuando no hay nada que controlar todavía: tu Orbital ya no reconoce este iPhone, no contesta (o el
/// iPhone no tiene internet), se está conectando o está en reposo. Lo que se ve en la TV lo pinta `RemoteSheet`.
struct RemoteStatusCard: View {
    /// Por el observador (no el modelo suelto): así esta tarjeta se vuelve a pintar cuando la TV cambia.
    var tvNow: ModelObserver<TVNowModel>
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = tvNow.model
        if model.tokenProblem {
            // La TV ya no reconoce este iPhone (cambió su token): sin esto el control quedaba muerto sin decir por qué.
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                Label("Tu Orbital ya no reconoce este iPhone", systemImage: "lock.trianglebadge.exclamationmark").recipe(.cardTitle)
                Text("Vuelve a conectarlos: en tu TV abre Ajustes › iPhone y escanea el código.").recipe(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.unreachable && !model.answered || model.unreachable && model.now == nil {
            // Apagada u otra red: lo dice y deja reintentar (antes «Conectando…» se quedaba girando para siempre).
            VStack(alignment: .leading, spacing: DS.Space.s3) {
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    // Sin internet en el iPhone no es la consola (antes la culpaba a ella).
                    if env.isOnline {
                        Label("Tu Orbital no contesta", systemImage: "tv.slash").recipe(.cardTitle)
                        Text("Revisa que la consola esté prendida y en la misma red que tu iPhone.").recipe(.footnote)
                    } else {
                        Label("Tu iPhone no tiene internet", systemImage: "wifi.slash").recipe(.cardTitle)
                        Text("Conéctalo al Wi-Fi de tu casa para controlar la TV.").recipe(.footnote)
                    }
                }
                Button { Task { await model.retryNow() } } label: { Text("Reintentar").font(DS.TextRecipe.label.font) }
                    .dsSecondaryButton().controlSize(.large)
                .accessibilityIdentifier("remote-retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if !model.answered {
            // La TV todavía no contesta (recién abierta la app): no se dice «nada sonando» antes de saberlo.
            HStack(spacing: DS.Space.s3) {
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).fill(DS.fill)
                    .frame(width: DS.Size.thumbSmall, height: DS.Size.thumbSmall / DS.Poster.aspect)
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    Text("Conectando con tu Orbital…").recipe(.cardTitle)
                    ProgressView().controlSize(.small)   // ds-exception: la tarjeta de la TV en espera; la ruedita ocupa el lugar de lo que suena
                }
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: DS.Space.s2) {
                OrbitalMark(size: DS.Size.markSmall).foregroundStyle(DS.text)
                Text("Tu Orbital").recipe(.section)
            }
        }
    }
}
