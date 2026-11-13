import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// Ajustes › Complementos › Torrentio › Configurar (T1): arriba qué es, luego lo que de verdad se cambia (idiomas, calidades,
/// «solo lo que ya está») y lo raro guardado en «Más opciones». Cada opción dice qué hace en una línea. Cada cambio arma la
/// misma dirección que la página de Torrentio, con tu clave sin que la veas, y se prueba solo con un título (T9).
struct TorrentioSettings: View {
    @Environment(AppEnvironment.self) private var env
    @State private var torrentio = ModelObserver(TorrentioSettingsModel(AppEnvironment.shared.services))
    @State private var explaining = false
    @State private var confirmReset = false
    /// «Tus idiomas» (N4-A), para cambiarlos desde aquí sin otra lista.
    @State private var yourSettings = ModelObserver(SettingsModel(AppEnvironment.shared.services))
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let model = torrentio.model
        let options = model.options
        Form {
            // P3-B: si con tus filtros no verías nada, se dice arriba (donde se ve) con su arreglo; si todo va bien, nada cambia.
            if case .result(.nothing(let fixes)) = model.probe {
                Section {
                    TorrentioNothingProblem(sample: TorrentioProbe.sample.name, fixes: fixes) { fix in model.apply(fix) }
                }
                .listRowBackground(DS.surface)
            }
            Section {
                // IOS-15: con letra de accesibilidad el párrafo ocupaba la pantalla entera; ahí basta «¿Qué es esto?», que lo explica.
                if !typeSize.isAccessibilitySize {
                    Text("Torrentio busca las versiones de lo que quieres ver. Aquí decides cuáles te enseña. Lo de abajo ya viene bien; cámbialo solo si algo te molesta.")
                        .recipe(.footnote, color: DS.textMuted)
                }
                Button { explaining = true } label: { Label("¿Qué es esto?", systemImage: "questionmark.circle") }
                    .accessibilityIdentifier("torrentio-explain")
            }
            .listRowBackground(DS.surface)
            languages(model, options)
            Section {
                NavigationLink { TorrentioQualities(model: torrentio) } label: {
                    TorrentioRowLabel(title: Text("Calidades que no quieres"), detail: TorrentioWords.hidden(options.excludedQualities))
                }
                .accessibilityIdentifier("torrentio-qualities")
                // T8-A: apagado, también salen las que se pueden pedir (y se piden desde «Versión», R4).
                DSToggleRow("Solo lo que ya está en la nube",
                            detail: options.debridOptions.contains("nodownloadlinks") ? "Prendido: solo ves lo que arranca al instante" : "Apagado: también ves lo que se puede pedir",
                            isOn: Binding(get: { options.debridOptions.contains("nodownloadlinks") }, set: { on in
                                model.change { o in
                                    o.debridOptions.removeAll { $0 == "nodownloadlinks" }
                                    if on { o.debridOptions.append("nodownloadlinks") }
                                }
                            }))
                .accessibilityIdentifier("torrentio-only-instant")
                NavigationLink { TorrentioMoreOptions(model: torrentio) } label: {
                    TorrentioRowLabel(title: Text("Más opciones"), detail: Text("Orden, cuántas, tamaño y sitios"))
                }
                .accessibilityIdentifier("torrentio-more")
            } header: { Text("Lo básico") }
            .listRowBackground(DS.surface)
            // T9: se prueba sola al cambiar algo; si no quedaría nada, el arreglo está aquí mismo.
            if model.probe != .idle, !model.probe.isNothing {
                Section {
                    TorrentioProbeRow(probe: model.probe, sample: TorrentioProbe.sample.name) { fix in model.apply(fix) }
                } footer: {
                    if !model.hasKey { Text("Sin tu clave de Real-Debrid no se sabe cuáles arrancan al instante.") }
                }
                .listRowBackground(DS.surface)
                .accessibilityIdentifier("torrentio-probe")
            }
            Section {
                Button("Volver a lo recomendado") { confirmReset = true }
                    .disabled(model.isRecommended)
                    .accessibilityIdentifier("torrentio-reset")
            } footer: { Text("Deja todo como viene con Orbital. Lo que traía tu Torrentio y la app no conoce se queda.") }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)
        .animation(DS.Motion.base(reduceMotion), value: model.probe.isNothing)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: "Torrentio")).navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .confirmationDialog("¿Volver a lo recomendado?", isPresented: $confirmReset, titleVisibility: .visible) {   // ds-exception: confirmación de borrar tus ajustes (sí o no)
            Button("Volver a lo recomendado", role: .destructive) { model.resetToRecommended() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Tus idiomas, calidades y demás opciones vuelven a como vienen con Orbital.") }
        .sheet(isPresented: $explaining) { DebridExplainer(topic: .torrentio) }
        .task { await model.syncWithTV(); env.announceAddonClash() }   // S3: tus opciones y las de tu TV, juntas
        .task { if model.probe == .idle || model.probe == .unreachable { model.scheduleProbe(now: true) } }   // al regresar de una subpágina no se vuelve a probar lo mismo
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("torrentio-settings")
    }

    /// T2 → N4-A (Fernando, 4 nov): los «Idiomas primero» de Torrentio son «Tus idiomas» de Ajustes, en su orden (sin
    /// «Idioma original», que Torrentio no conoce). Aquí no hay otra lista que compita: se dice cuáles y se cambian allá.
    @ViewBuilder private func languages(_ model: TorrentioSettingsModel, _ options: AddonOptions) -> some View {
        let mine = yourSettings.model.settings
        let names = Text(verbatim: mine.yourLanguages.map { YourLanguagesView.name($0, mine.uiLanguage) }.joined(separator: ", "))
        Section {
            NavigationLink { YourLanguagesView(settings: yourSettings) } label: {
                TorrentioRowLabel(title: Text("Se usan tus idiomas · Cambiar"), detail: names, action: true)
            }
            .accessibilityIdentifier("torrentio-your-languages")
        } header: { Text("Idiomas primero") } footer: {
            Text("Las versiones en tus idiomas salen arriba, en tu orden. Se cambian en Ajustes › Tus idiomas.")
        }
        .listRowBackground(DS.surface)
    }
}

extension TorrentioSettingsModel.Probe {
    /// La prueba dio 0 versiones con tus filtros (P3-B: el aviso sube arriba de la página).
    var isNothing: Bool { if case .result(.nothing) = self { true } else { false } }
}

/// Un renglón que lleva a otra página: su nombre y, debajo, cómo está ahora (en gris).
struct TorrentioRowLabel: View {
    let title: Text
    let detail: Text
    /// IOS-17 · un renglón que se toca y hace algo (no lleva a otra página): su título en el color de lo interactivo.
    var action = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title.foregroundStyle(action ? DS.accent : DS.text)
            detail.recipe(.footnote, color: DS.textMuted)
        }
    }
}
