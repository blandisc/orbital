import SwiftUI
import UIKit
import OrbitalCore
import OrbitalAddons

/// Ajustes › Descargas › «Probar la velocidad»: las cuatro medidas de `DownloadSpeedTest`, qué quieren decir y un botón para
/// copiarlas.
struct DownloadSpeedTestView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var test = DownloadSpeedTest()

    var body: some View {
        Form {
            Section {
                ForEach(test.rows) { row in
                    LabeledContent {
                        if row.running { DSInlineProgress(text: Text("Midiendo…")) }
                        else if let rate = row.bytesPerSecond { Text(verbatim: DownloadSpeedTest.format(rate)).monospacedDigit().foregroundStyle(DS.text) }
                        else if let failed = row.failed { Text(failed, cloud: test.cloud, locale: env.uiLocale).foregroundStyle(DS.warning) }
                        else { Text(verbatim: "—") }
                    } label: { Text(DownloadSpeedTest.title(row.kind), cloud: test.cloud, locale: env.uiLocale) }
                }
            } header: {
                if let status = test.status { Text(status, cloud: test.cloud, locale: env.uiLocale) } else if let name = test.sourceName { Text(verbatim: name) }
            } footer: {
                Text("Unos segundos cada una, sin guardar nada. Hazla con Wi‑Fi y con la app abierta.")
            }
            .listRowBackground(DS.surface)
            if let problem = test.problem { DSNotice(verbatim: test.cloud.spoken(Strings.tr(problem, language: env.language)), tone: .warn).listRowBackground(Color.clear) }
            if let verdict = test.verdict { Section { Text(verdict, cloud: test.cloud, locale: env.uiLocale).recipe(.footnote, color: DS.text) } header: { Text("Qué quiere decir") }.listRowBackground(DS.surface) }
            Section {
                Button(test.running ? "Midiendo…" : (test.rows.contains { $0.bytesPerSecond != nil } ? "Probar otra vez" : "Empezar")) {
                    Task { await test.run(services: env.services) }
                }
                .disabled(test.running)
                .accessibilityIdentifier("speed-test-start")
                if !test.running, test.rows.contains(where: { $0.bytesPerSecond != nil }) {
                    Button("Copiar resultados") { UIPasteboard.general.string = test.report }
                }
            }
            .listRowBackground(DS.surface)
        }
        .readableListWidth()   // iPad y Mac: al centro, no estirada a todo lo ancho
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .dsInlineTitle("Probar la velocidad")
    }
}
