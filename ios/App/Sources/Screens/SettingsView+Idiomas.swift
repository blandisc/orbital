import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes › «Idiomas» (ID-A, Fernando, 22 nov 2026: «consolidar los idiomas en un solo lugar… el idioma que quieres en el
/// contenido, el idioma del app y el idioma de los metadatos»): un solo renglón en la lista y, adentro, la app, los títulos y
/// sinopsis, el audio en orden, los subtítulos y el país. Igual en iPhone, iPad y Mac (ahí, a la derecha de la barra).
extension SettingsView {
    @ViewBuilder func languagesSection(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            SettingsLink(.languages) { destination(.languages, model) } label: {
                SettingsRow(title: "Idiomas", symbol: "globe", tint: DS.ListTint.chart, value: languagesValue(s))
            }
            .accessibilityIdentifier("settings-languages")
        }
        .listRowBackground(DS.surface)
    }

    /// «Español · Latino, original +2»: el de la app y, después, el audio.
    private func languagesValue(_ s: AppSettings) -> Text {
        let app = s.uiLanguage == "en" ? "English" : "Español"
        return Text(verbatim: app + " · " + YourLanguagesView.summary(s.yourLanguages, s.uiLanguage))
    }

    /// La página «Idiomas»: cada idioma por su lado. Con dos opciones, botones a la vista (no otra pantalla con una lista).
    @ViewBuilder func languagesPage(_ model: SettingsModel) -> some View {
        let s = model.settings
        // Los dos idiomas de Orbital en una tarjeta: cada renglón dice qué cambia y lleva su selector a la derecha.
        Section {
            SettingsChoiceRow(title: "La app", detail: "Menús, botones y avisos", options: languageChoices,
                              selection: Binding(get: { s.uiLanguage }, set: { v in model.update { $0.uiLanguage = v } }))
                .accessibilityIdentifier("languages-app")
            SettingsChoiceRow(title: "Títulos y sinopsis", detail: "Cómo se llaman las películas y series y de qué tratan", options: languageChoices,
                              selection: Binding(get: { s.titleLanguage }, set: { v in model.update { $0.metadataLanguage = v } }))
                .accessibilityIdentifier("languages-titles")
        } header: { Text("Lo que lees") }
        .listRowBackground(DS.surface)
        YourLanguagesView(settings: settings, embedded: true)
        Section {
            PaneLink(Text("Subtítulos")) { page("Subtítulos") { subtitles(model) } } label: {
                SettingsRow(title: "Cuáles salen", symbol: "captions.bubble", tint: DS.ListTint.library, value: subtitlesValue(s))
            }
            .accessibilityIdentifier("settings-subtitles")
            DSToggleRow("Buscar subtítulos en internet", detail: "Si el video no los trae en tu idioma, se buscan en OpenSubtitles.",
                        symbol: "text.magnifyingglass", tint: DS.ListTint.list, isOn: Binding(get: { s.internetSubtitles }, set: { v in model.update { $0.internetSubtitles = v } }))
                .accessibilityIdentifier("settings-internet-subtitles")
            PaneLink(Text("Letra de los subtítulos")) { page("Letra de los subtítulos") { lettering(model) } } label: {
                SettingsRow(title: "Letra", symbol: "textformat.size", tint: DS.ListTint.spark, value: sizeName(s.subtitleSize))
            }
            .accessibilityIdentifier("settings-subtitle-letter")
        } header: { Text("Subtítulos") } footer: { Text("Van aparte del audio: puedes oírla en inglés y leerla en español.") }
        .listRowBackground(DS.surface)
        Section {
            Picker("País", selection: Binding(get: { s.region }, set: { v in model.update { $0.region = v; $0.regionChosen = true } })) {
                ForEach(["MX", "US", "ES", "AR", "CO", "CL", "PE"], id: \.self) { Text(verbatim: env.uiLocale.localizedString(forRegionCode: $0) ?? $0).tag($0) }
            }
            .accessibilityIdentifier("languages-region")
        } footer: { Text("Para lo popular en Netflix, Disney+ y HBO Max de tu país.") }   // sin encabezado: el renglón ya dice «País»
        .listRowBackground(DS.surface)
    }

    /// Cada idioma con su propio nombre (así lo encuentra quien no lee el otro).
    private var languageChoices: [DSSelector<String>.Option] {
        [.init(id: "es", title: Text(verbatim: "Español")), .init(id: "en", title: Text(verbatim: "English"))]
    }

    private func subtitlesValue(_ s: AppSettings) -> Text {
        if s.subtitles.isEmpty { return Text("Apagados") }
        return s.subtitles == "en" ? Text(verbatim: "English") : Text("Español")
    }

    private func sizeName(_ size: String) -> Text {
        // Los mismos cuatro nombres que la TV (PT19): «Normal», no «Mediano».
        switch size { case "small": Text("Pequeño"); case "large": Text("Grande"); case "xlarge": Text("Muy grande"); default: Text("Normal") }
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
            PaneLink(Text("Lo que recuerda cada título")) { RememberedTitlesView() } label: { Text("Lo que recuerda cada título") }
                .accessibilityIdentifier("settings-remembered")
        }
        .listRowBackground(DS.surface)
    }

    /// Letra de los subtítulos: cómo se ven, con su vista previa.
    @ViewBuilder func lettering(_ model: SettingsModel) -> some View {
        let s = model.settings
        Section {
            SubtitlePreview(look: SubtitleLook(settings: s)).listRowInsets(EdgeInsets(top: DS.Space.s2, leading: DS.Space.s4, bottom: DS.Space.s2, trailing: DS.Space.s4))
            Picker("Tamaño", selection: Binding(get: { s.subtitleSize }, set: { v in model.update { $0.subtitleSize = v } })) {
                ForEach(AppSettings.subtitleSizes, id: \.self) { sizeName($0).tag($0) }
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
