import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes › «Idiomas y subtítulos» (N4-A, Fernando, 4 nov: «que sea fácil configurar los subtítulos y los idiomas»): arriba
/// y juntos, los mismos cuatro que la TV en Ajustes › Ver: Tus idiomas, Subtítulos, Buscar subtítulos en internet y Letra de
/// los subtítulos. El idioma de la app va aparte («Idioma de la app»).
extension SettingsView {
    @ViewBuilder func languagesSection(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            NavigationLink { YourLanguagesView(settings: settings) } label: {
                SettingsRow(title: "Tus idiomas", symbol: "globe", tint: DS.ListTint.chart, value: Text(verbatim: YourLanguagesView.summary(s.yourLanguages, s.uiLanguage)))
            }
            .accessibilityIdentifier("settings-languages")
            NavigationLink { page("Subtítulos") { subtitles(model) } } label: {
                SettingsRow(title: "Subtítulos", symbol: "captions.bubble", tint: DS.ListTint.library, value: subtitlesValue(s))
            }
            .accessibilityIdentifier("settings-subtitles")
            DSToggleRow("Buscar subtítulos en internet", detail: "Si el video no los trae en tu idioma, se buscan en OpenSubtitles.",
                        isOn: Binding(get: { s.internetSubtitles }, set: { v in model.update { $0.internetSubtitles = v } }))
                .accessibilityIdentifier("settings-internet-subtitles")
            NavigationLink { page("Letra de los subtítulos") { lettering(model) } } label: {
                SettingsRow(title: "Letra de los subtítulos", symbol: "textformat.size", tint: DS.ListTint.spark, value: sizeName(s.subtitleSize))
            }
            .accessibilityIdentifier("settings-subtitle-letter")
        } header: { Text("Idiomas y subtítulos") }
        .listRowBackground(DS.surface)
    }

    private func subtitlesValue(_ s: AppSettings) -> Text {
        if s.subtitles.isEmpty { return Text("Apagados") }
        return s.subtitles == "en" ? Text(verbatim: "English") : Text("Español")
    }

    private func sizeName(_ size: String) -> Text {
        switch size { case "small": Text("Chico"); case "large": Text("Grande"); default: Text("Mediano") }
    }

    /// «Idioma de la app»: el de los menús y las fichas (el del audio está en «Tus idiomas»).
    @ViewBuilder func appLanguage(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            Picker("Idioma de la app y de las fichas", selection: Binding(get: { s.uiLanguage }, set: { v in model.update { $0.uiLanguage = v } })) {
                Text("Español").tag("es"); Text("English").tag("en")
            }
        } footer: { Text("El audio de las películas y series se elige en Tus idiomas.") }
        .listRowBackground(DS.surface)
    }

    /// Subtítulos: cuáles salen solos y cuándo.
    @ViewBuilder func subtitles(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            Picker("Idioma de siempre", selection: Binding(get: { s.subtitles }, set: { v in model.update { $0.subtitles = v } })) { languageOptions; Text("Apagados").tag("") }
            Toggle("Solo subtítulos forzados", isOn: Binding(get: { s.onlyForcedSubtitles }, set: { v in model.update { $0.onlyForcedSubtitles = v } }))
            Toggle("Mostrarlos al regresar 10 s", isOn: Binding(get: { s.subtitlesOnSkipBack }, set: { v in model.update { $0.subtitlesOnSkipBack = v } }))
            Toggle("Carteles en tu idioma si el audio es otro", isOn: Binding(get: { s.forcedForForeignAudio }, set: { v in model.update { $0.forcedForForeignAudio = v } }))
        } footer: {
            Text("El idioma, la versión y el ajuste de tiempo se recuerdan solos para cada serie o película.")
        }
        .listRowBackground(DS.surface)
        Section {
            NavigationLink { RememberedTitlesView() } label: { Text("Lo que recuerda cada título") }
                .accessibilityIdentifier("settings-remembered")
        }
        .listRowBackground(DS.surface)
    }

    /// Letra de los subtítulos: cómo se ven, con su vista previa.
    @ViewBuilder func lettering(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            SubtitlePreview(look: SubtitleLook(settings: s)).listRowInsets(EdgeInsets(top: DS.Space.s3, leading: DS.Space.s4, bottom: DS.Space.s3, trailing: DS.Space.s4))
            Picker("Tamaño", selection: Binding(get: { s.subtitleSize }, set: { v in model.update { $0.subtitleSize = v } })) {
                Text("Chico").tag("small"); Text("Mediano").tag("medium"); Text("Grande").tag("large")
            }
            Picker("Fondo", selection: Binding(get: { s.subtitleBackground }, set: { v in model.update { $0.subtitleBackground = v } })) {
                Text("Contorno").tag("outline"); Text("Caja oscura").tag("box"); Text("Translúcido").tag("translucent")
            }
            .disabled(s.subtitleSystemStyle)
            Picker("Posición", selection: Binding(get: { s.subtitlePosition }, set: { v in model.update { $0.subtitlePosition = v } })) {
                Text("Normal").tag("normal"); Text("Más arriba").tag("raised")
            }
            Toggle("Usar el estilo del iPhone", isOn: Binding(get: { s.subtitleSystemStyle }, set: { v in model.update { $0.subtitleSystemStyle = v } }))
        } footer: {
            Text("El estilo del iPhone se cambia en Ajustes › Accesibilidad › Subtítulos.")
        }
        .listRowBackground(DS.surface)
    }
}
