import SwiftUI
import OrbitalCore
import OrbitalAddons
import OrbitalModels

/// T3 · «Calidades que no quieres»: una palomita por calidad, cada una con lo que es en una línea. Lo que escondas no sale
/// en «Versión». La prueba con un título (T9) avisa si escondiste de más.
struct TorrentioQualities: View {
    let model: ModelObserver<TorrentioSettingsModel>

    var body: some View {
        let torrentio = model.model
        let hidden = Set(torrentio.options.excludedQualities)
        Form {
            Section {
                ForEach(TorrentioWords.qualities, id: \.self) { key in
                    let words = TorrentioWords.quality(key)
                    Button {
                        torrentio.change { o in
                            if o.excludedQualities.contains(key) { o.excludedQualities.removeAll { $0 == key } } else { o.excludedQualities.append(key) }
                        }
                    } label: {
                        CheckLine(title: words.name, detail: words.detail, checked: hidden.contains(key))
                    }
                    .accessibilityIdentifier("torrentio-quality-\(key)")
                }
            } header: { Text("Esconder") } footer: { Text("Si marcas de más, la prueba con un título te avisa.") }
            .listRowBackground(DS.surface)
            if torrentio.probe != .idle {
                Section { TorrentioProbeRow(probe: torrentio.probe, sample: TorrentioProbe.sample.name) { torrentio.apply($0) } }
                    .listRowBackground(DS.surface)
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Calidades").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
        .sensoryFeedback(.selection, trigger: hidden)
    }
}

/// Un renglón de elegir (de un grupo o varios): nombre, su explicación en gris y la palomita a la derecha si está.
struct CheckLine: View {
    let title: Text
    let detail: Text
    let checked: Bool

    var body: some View {
        HStack(spacing: DS.Space.s3) {
            VStack(alignment: .leading, spacing: 0) {
                title.foregroundStyle(DS.text)
                detail.recipe(.footnote, color: DS.textMuted)
            }
            Spacer(minLength: DS.Space.s2)
            if checked { Image(systemName: "checkmark").foregroundStyle(DS.accent).accessibilityHidden(true) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// T1 · «Más opciones» (cerrado por omisión): orden (T4), cuántas de cada calidad (T5), tamaño máximo (T6) y sitios (T7).
struct TorrentioMoreOptions: View {
    let model: ModelObserver<TorrentioSettingsModel>
    static let movieSizes = ["2GB", "5GB", "10GB", "20GB"]
    static let episodeSizes = ["500MB", "1GB", "2GB", "5GB"]

    var body: some View {
        let torrentio = model.model
        let options = torrentio.options
        let sizes = TorrentioConfig.sizes(options.sizeFilter)
        Form {
            Section {
                ForEach(TorrentioConfig.sorts, id: \.self) { key in
                    let words = TorrentioWords.sort(key)
                    Button { torrentio.change { $0.sort = key == TorrentioConfig.sorts[0] ? nil : key } } label: {
                        CheckLine(title: words.name, detail: words.detail, checked: (options.sort ?? TorrentioConfig.sorts[0]) == key)
                    }
                }
            } header: { Text("Orden de la lista") }
            .listRowBackground(DS.surface)
            Section {
                ForEach(limits(options.limit), id: \.self) { value in
                    let words = TorrentioWords.limit(value)
                    Button { torrentio.change { $0.limit = value } } label: { CheckLine(title: words.name, detail: words.detail, checked: options.limit == value) }
                }
            } header: { Text("Cuántas por calidad") }
            .listRowBackground(DS.surface)
            Section {
                sizePicker(Text("Películas"), current: sizes.movies, choices: Self.movieSizes) { value in
                    torrentio.change { $0.sizeFilter = TorrentioConfig.sizeFilter(movies: value, episodes: TorrentioConfig.sizes($0.sizeFilter).episodes) }
                }
                sizePicker(Text("Episodios"), current: sizes.episodes, choices: Self.episodeSizes) { value in
                    torrentio.change { $0.sizeFilter = TorrentioConfig.sizeFilter(movies: TorrentioConfig.sizes($0.sizeFilter).movies, episodes: value) }
                }
            } header: { Text("Tamaño máximo") } footer: { Text("Sin límite, salvo que tu internet sea lento o veas con datos.") }
            .listRowBackground(DS.surface)
            Section {
                NavigationLink { TorrentioProviders(model: model) } label: {
                    TorrentioRowLabel(title: Text("Sitios donde busca"),
                                      detail: options.providers.isEmpty ? Text("Los \(TorrentioConfig.providers.count) prendidos · apaga uno si da basura")
                                                                        : Text("\(options.providers.count) de \(TorrentioConfig.providers.count) prendidos"))
                }
                .accessibilityIdentifier("torrentio-providers")
            }
            .listRowBackground(DS.surface)
            if torrentio.probe != .idle {
                Section { TorrentioProbeRow(probe: torrentio.probe, sample: TorrentioProbe.sample.name) { torrentio.apply($0) } }
                    .listRowBackground(DS.surface)
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Más opciones").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
    }

    /// Todas, hasta 5 y hasta 2; si traías otro número de tu Stremio, también, para no perderlo de vista.
    private func limits(_ current: Int?) -> [Int?] {
        var out: [Int?] = [nil, 5, 2]
        if let current, ![5, 2].contains(current) { out.append(current) }
        return out
    }

    private func sizePicker(_ title: Text, current: String?, choices: [String], set: @escaping (String?) -> Void) -> some View {
        Picker(selection: Binding(get: { current ?? "" }, set: { set($0.isEmpty ? nil : $0) })) {
            Text("Sin límite").tag("")
            ForEach(choices + (current.map { choices.contains($0) ? [] : [$0] } ?? []), id: \.self) { TorrentioWords.size($0).tag($0) }
        } label: { title.foregroundStyle(DS.text) }
        .pickerStyle(.menu)
    }
}

/// T7 · los 25 sitios de Torrentio, cada uno con su interruptor (todos prendidos por omisión). Siempre queda al menos uno.
struct TorrentioProviders: View {
    let model: ModelObserver<TorrentioSettingsModel>

    var body: some View {
        let torrentio = model.model
        let on = Set(torrentio.options.providers.isEmpty ? TorrentioConfig.providers : torrentio.options.providers)
        Form {
            Section {
                ForEach(TorrentioConfig.providers, id: \.self) { key in
                    Toggle(isOn: Binding(get: { on.contains(key) }, set: { want in
                        var next = on
                        if want { next.insert(key) } else { next.remove(key) }
                        guard !next.isEmpty else { return }
                        // En el orden de Torrentio; los 25 prendidos es lo mismo que no decir ninguno.
                        let ordered = TorrentioConfig.providers.filter(next.contains)
                        torrentio.change { $0.providers = ordered.count == TorrentioConfig.providers.count ? [] : ordered }
                    })) { Text(verbatim: TorrentioConfig.providerNames[key] ?? key).foregroundStyle(DS.text) }
                }
            } footer: { Text("Casi nunca hace falta: apaga uno solo si da versiones que no sirven.") }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("Sitios donde busca").navigationBarTitleDisplayMode(.inline)
        .readableListWidth()
    }
}
