import SwiftUI
import UIKit
import OrbitalCore

/// Ajustes › Descargas › «Probar la velocidad»: las cuatro medidas de `DownloadSpeedTest`, qué quieren decir y un botón para
/// copiarlas.
struct DownloadSpeedTestView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var test = DownloadSpeedTest()

    var body: some View {
        Form {
            Section {
                ForEach(test.rows) { row in
                    LabeledContent {
                        if row.running { ProgressView() }
                        else if let rate = row.bytesPerSecond { Text(verbatim: DownloadSpeedTest.format(rate)).monospacedDigit().foregroundStyle(DS.text) }
                        else if let failed = row.failed { Text(LocalizedStringKey(failed)).foregroundStyle(DS.warning) }
                        else { Text(verbatim: "—") }
                    } label: { Text(LocalizedStringKey(DownloadSpeedTest.title(row.kind))) }
                }
            } header: {
                if let status = test.status { Text(LocalizedStringKey(status)) } else if let name = test.sourceName { Text(verbatim: name) }
            } footer: {
                Text("Unos segundos cada una, sin guardar nada. Hazla con Wi‑Fi y con la app abierta.")
            }
            .listRowBackground(DS.surface)
            if let problem = test.problem { DSNotice(text: LocalizedStringKey(problem), tone: .warn).listRowBackground(Color.clear) }
            if let verdict { Section { Text(verdict).recipe(.footnote, color: DS.text) } header: { Text("Qué quiere decir") }.listRowBackground(DS.surface) }
            Section {
                Button(test.running ? "Midiendo…" : (test.rows.contains { $0.bytesPerSecond != nil } ? "Probar otra vez" : "Empezar")) {
                    Task { await test.run(services: env.services) }
                }
                .disabled(test.running)
                .accessibilityIdentifier("speed-test-start")
                if !test.running, test.rows.contains(where: { $0.bytesPerSecond != nil }) {
                    Button("Copiar resultados") { UIPasteboard.general.string = test.report; env.notify("Copiado", tone: .success) }
                }
            }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Probar la velocidad").navigationBarTitleDisplayMode(.inline)
    }

    /// Una lectura sencilla de los números (cuál es el tope).
    private var verdict: LocalizedStringKey? {
        func value(_ kind: DownloadSpeedTest.Row.Kind) -> Double? { test.rows.first { $0.kind == kind }?.bytesPerSecond }
        guard !test.running, let internet = value(.internet), let single = value(.single), let eight = value(.eight), let background = value(.background) else { return nil }
        let best = max(single, eight)
        if background < best * 0.6 { return "El tope es la forma en que baja iOS en segundo plano: dentro de la app baja bastante más rápido. Eso se arregla en Orbital." }
        if eight > single * 1.6 { return "Real-Debrid limita cada conexión: con varias a la vez baja mucho más rápido. Eso se arregla en Orbital usando más conexiones." }
        if best < internet * 0.5 { return "Real-Debrid te está dando menos que tu internet: puede ser su servidor de ese momento o la ruta hasta él." }
        return "Real-Debrid y la app ya van a la velocidad de tu internet: el tope es tu conexión."
    }
}
