import SwiftUI
import OrbitalModels

/// Ajustes › Cuentas (maqueta 11): cada cuenta con su papel dicho en el título. Tu nube (Real-Debrid, TorBox o AllDebrid,
/// DN1: de ahí salen los videos),
/// Trakt · principal (lo tuyo entre aparatos), OneDrive, Letterboxd, OpenSubtitles y las claves de Explorar (TMDB), en el orden
/// de Ajustes › Cuentas de la TV (PA1-A, 23 nov 2026: OneDrive y la clave de TMDB ya no tienen renglón aparte). Tu Orbital
/// vive aparte, en «En este aparato».
extension SettingsView {
    /// Lo que dice el renglón «Cuentas»: cuánto le queda a tu nube, o que falta.
    var debridValue: Text {
        guard let status = debrid.model.status else { return Text("Falta tu nube") }
        // IOS-17: «143 días» no dice de qué; «TorBox · 143 días».
        let value = DebridModel.summary(status, now: Date()).state == .free ? Text("Cuenta gratuita") : DebridWords.short(status)
        return Text("\(Text(verbatim: debrid.model.service.name)) · \(value)")
    }

    /// «N cosas no se pudieron guardar en Trakt» (revisión del 11 nov 2026): solo si hay algo; abre qué fue, cuándo y por qué.
    @ViewBuilder var traktDiscardsRow: some View {
        let count: Int = discards.model.count
        if count > 0 {
            PaneLink(Text("No llegó a Trakt")) { TraktDiscardsView(model: discards.model) } label: {
                if count == 1 {
                    SettingsRow(title: "1 cosa no se pudo guardar en Trakt", symbol: "exclamationmark.icloud", tint: DS.warning)
                } else {
                    SettingsRow(title: "\(count) cosas no se pudieron guardar en Trakt", symbol: "exclamationmark.icloud", tint: DS.warning)
                }
            }
            .accessibilityIdentifier("settings-trakt-discards")
        }
    }

    @ViewBuilder func accounts(_ model: SettingsModel) -> some View {
        if env.services.settingsEntries.realDebrid { debridSection }   // D1-B: Orbital (App Store) no trae Real-Debrid
        Section {
            // La sesión de Trakt siempre es la de este iPhone (la de la consola ya no se presta): se abre, se ve y se desconecta aquí.
            PaneLink(Text(verbatim: "Trakt")) { page("Trakt") { traktSection(model) } } label: {
                SettingsRow(title: "Trakt", symbol: "checkmark.seal", tint: DS.ListTint.chart, value: traktValue(model))
            }
            traktDiscardsRow
        } header: { Text("Trakt · principal") } footer: { Text("Guarda dónde te quedaste, lo que viste y Mi lista, para todos tus aparatos.") }
        .listRowBackground(DS.surface)
        .onAppear { discards.model.reload() }   // la cola pudo descartar algo mientras tanto
        // Tus películas y series de OneDrive como una fuente más (como en la TV, que la tiene en Cuentas).
        Section {
            PaneLink(Text(verbatim: "OneDrive")) { OneDriveSettings() } label: {
                SettingsRow(title: "OneDrive", symbol: "folder", tint: DS.ListTint.library,
                            value: env.services.oneDrive.linked ? Text("Conectado") : Text("Sin conectar"))
            }
            .accessibilityIdentifier("settings-onedrive")
        } header: { Text("OneDrive · tus archivos") } footer: { Text("Tus películas y series de OneDrive salen junto a lo demás.") }
        .listRowBackground(DS.surface)
        Section {
            PaneLink(Text(verbatim: "Letterboxd")) { LetterboxdSettings() } label: {
                SettingsRow(title: "Letterboxd", symbol: "star.bubble", tint: DS.Letterboxd.leaf, value: letterboxdValue)
            }
        } header: { Text("Letterboxd · tus reseñas") } footer: { Text("Solo se lee: tus reseñas salen en Lo que ves y en cada ficha, y tus listas en Explorar.") }
        .listRowBackground(DS.surface)
        if AppEnvironment.shared.openSubtitles.available {
            Section {
                PaneLink(Text(verbatim: "OpenSubtitles")) { OpenSubtitlesSettings() } label: {
                    SettingsRow(title: "OpenSubtitles", symbol: "captions.bubble", tint: DS.ListTint.series, value: openSubtitlesValue)
                }
                .accessibilityIdentifier("settings-opensubtitles")
            } header: { Text("OpenSubtitles · subtítulos") } footer: { Text("Más subtítulos y de tu copia exacta.") }
            .listRowBackground(DS.surface)
        }
        exploreKeys(model)
    }

    /// «Claves de Explorar» (así le dice la TV): la de TMDB, antes en Avanzado.
    @ViewBuilder private func exploreKeys(_ model: SettingsModel) -> some View {
        Section {
            // Con su ícono en la columna de los íconos, como los demás renglones: solo con el texto guía, tenue, no se veía
            // como un campo (26 nov 2026).
            Label {
                SecureField(LocalizedStringKey(model.hasTMDBKey ? "Clave de TMDB guardada" : "Clave de TMDB"), text: $tmdbKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("settings-tmdb-key")
            } icon: {
                Image(systemName: "key").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.ListTint.addon).frame(width: DS.SettingsLook.rowIcon)
            }
            // Solo espacios no es una clave: «Guardar» con eso borraba la tuya sin avisar (revisión del 28 nov 2026).
            if !tmdbKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Button("Guardar clave de TMDB") { model.setTMDBKey(tmdbKey); tmdbKey = "" } }
            // Una clave tuya equivocada dejaba sin fichas en español ni Explorar, sin regreso: se quita y vuelve la incluida.
            else if model.hasTMDBKey { Button("Quitar mi clave", role: .destructive) { model.setTMDBKey("") } }
        } header: { Text("Claves de Explorar") } footer: {
            env.services.usesBuiltInTMDBKey
                ? Text("Ya viene incluida: fichas y sinopsis en español, temporadas y lo popular en Netflix, Disney+ y HBO Max. Pon la tuya solo si quieres.")
                : Text("TMDB pone las fichas en español y busca lo popular en Netflix, Disney+ y HBO Max.")
        }
        .listRowBackground(DS.surface)
    }

    private var openSubtitlesValue: Text {
        let model = AppEnvironment.shared.openSubtitles
        let _ = model.track()
        return model.account.map { Text(verbatim: $0.username) } ?? Text("No conectado")
    }

    private var letterboxdValue: Text {
        let model = AppEnvironment.shared.letterboxd
        let _ = model.track()
        if let user = model.user { return Text(verbatim: "@\(user)") }
        return model.importedAt != nil ? Text("Tu archivo") : Text("No conectado")
    }

    /// Tu nube: un renglón con cuál usas y cuánto le queda (ámbar desde 14 días antes) que lleva a su página (D1, DN1).
    @ViewBuilder private var debridSection: some View {
        let model = debrid.model
        Section {
            PaneLink(Text("Tu nube")) { DebridAccountView(debrid: model) } label: {
                SettingsRow(title: "Tu nube", symbol: "externaldrive.badge.checkmark",
                            tint: model.status.map(DebridAccountView.isWarning) == true ? DS.warning : DS.ListTint.calendar,
                            value: model.hasToken
                                ? Text("\(Text(verbatim: model.service.name)) · \(model.status.map { DebridWords.short($0) } ?? Text("Guardada"))")
                                : Text("Elegir"))
            }
            .accessibilityIdentifier("settings-debrid")
        } footer: { Text("Real-Debrid, TorBox o AllDebrid: de ahí salen los videos. Tu cuenta, tu clave y tus pedidos.") }
        .listRowBackground(DS.surface)
        .task { await model.load(force: true) }
    }
}
