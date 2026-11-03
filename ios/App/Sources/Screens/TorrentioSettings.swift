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

    var body: some View {
        let model = torrentio.model
        let options = model.options
        Form {
            Section {
                Text("Torrentio busca las versiones de lo que quieres ver. Aquí decides cuáles te enseña. Lo de abajo ya viene bien; cámbialo solo si algo te molesta.")
                    .recipe(.footnote, color: DS.textMuted)
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
                DSToggleRow("Solo lo que ya está en Real-Debrid",
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
            if model.probe != .idle {
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
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(Text(verbatim: "Torrentio")).navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .confirmationDialog("¿Volver a lo recomendado?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Volver a lo recomendado", role: .destructive) { model.resetToRecommended() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Tus idiomas, calidades y demás opciones vuelven a como vienen con Orbital.") }
        .sheet(isPresented: $explaining) { DebridExplainer(topic: .torrentio) { explaining = false }.presentationDetents([.medium, .large]) }
        .task { if model.probe == .idle || model.probe == .unreachable { model.scheduleProbe(now: true) } }   // al regresar de una subpágina no se vuelve a probar lo mismo
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("torrentio-settings")
    }

    /// T2: idiomas primero, en orden. El orden también es el plan B del reproductor (R6). Subir y bajar con el menú de cada
    /// uno, el arrastre o VoiceOver.
    @ViewBuilder private func languages(_ model: TorrentioSettingsModel, _ options: AddonOptions) -> some View {
        let ui = env.services.appSettings.uiLanguage
        Section {
            ForEach(Array(options.languages.enumerated()), id: \.element) { index, key in
                HStack(spacing: DS.Space.s3) {
                    Text(verbatim: "\(index + 1)").font(DS.TextRecipe.footnote.font.monospacedDigit()).foregroundStyle(DS.textMuted)
                        .frame(width: DS.SettingsLook.rowIcon)
                    TorrentioWords.language(key, uiLanguage: ui).foregroundStyle(DS.text)
                    Spacer(minLength: DS.Space.s2)
                    Menu {
                        if index > 0 { Button("Subir", systemImage: "arrow.up") { move(model, key, by: -1) } }
                        if index < options.languages.count - 1 { Button("Bajar", systemImage: "arrow.down") { move(model, key, by: 1) } }
                        Button("Quitar", systemImage: "minus.circle", role: .destructive) { model.change { $0.languages.removeAll { $0 == key } } }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(DS.textMuted).frame(minWidth: DS.Size.touchTarget)
                    }
                    .accessibilityLabel(Text("Opciones"))
                }
                .accessibilityElement(children: .combine)
                .accessibilityActions {
                    if index > 0 { Button("Subir") { move(model, key, by: -1) } }
                    if index < options.languages.count - 1 { Button("Bajar") { move(model, key, by: 1) } }
                    Button("Quitar") { model.change { $0.languages.removeAll { $0 == key } } }   // lo mismo que el menú y el deslizar
                }
                .swipeActions { Button("Quitar", role: .destructive) { model.change { $0.languages.removeAll { $0 == key } } }.tint(DS.danger) }
            }
            .onMove { from, to in model.change { $0.languages.move(fromOffsets: from, toOffset: to) } }
            if options.languages.isEmpty {
                Text("Ninguno: las versiones salen sin importar el idioma.").recipe(.footnote, color: DS.textMuted)
            }
            // Con los 41 ya en tu lista no queda qué agregar (antes abría una página vacía).
            if options.languages.count < TorrentioConfig.languages.count {
                NavigationLink { TorrentioLanguagePicker(model: torrentio) } label: {
                    Label("Agregar idioma", systemImage: "plus.circle").foregroundStyle(DS.text)
                }
                .accessibilityIdentifier("torrentio-add-language")
            }
        } header: { Text("Idiomas primero") } footer: {
            Text("Las versiones en estos idiomas salen arriba. Si no hay en el primero, se prueba el siguiente.")
        }
        .listRowBackground(DS.surface)
    }

    private func move(_ model: TorrentioSettingsModel, _ key: String, by step: Int) {
        model.change { o in
            guard let i = o.languages.firstIndex(of: key), o.languages.indices.contains(i + step) else { return }
            o.languages.swapAt(i, i + step)
        }
    }
}

/// Un renglón que lleva a otra página: su nombre y, debajo, cómo está ahora (en gris).
struct TorrentioRowLabel: View {
    let title: Text
    let detail: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title.foregroundStyle(DS.text)
            detail.recipe(.footnote, color: DS.textMuted)
        }
    }
}

/// T2 · «Agregar idioma»: los 41 de Torrentio que todavía no están, con el tuyo arriba.
struct TorrentioLanguagePicker: View {
    let model: ModelObserver<TorrentioSettingsModel>
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let ui = env.services.appSettings.uiLanguage
        let chosen = Set(model.model.options.languages)
        Form {
            Section {
                ForEach(TorrentioConfig.languages.filter { !chosen.contains($0) }, id: \.self) { key in
                    Button { model.model.change { $0.languages.append(key) }; dismiss() } label: {
                        TorrentioWords.language(key, uiLanguage: ui).foregroundStyle(DS.text)
                    }
                }
            } footer: { Text("Se agrega al final de tu lista.") }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Agregar idioma").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
    }
}
