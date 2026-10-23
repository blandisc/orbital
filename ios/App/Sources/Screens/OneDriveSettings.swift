import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes › OneDrive: tus películas y series de OneDrive como una fuente más (como en la TV). Se conecta con un código
/// en microsoft.com/link, se elige la carpeta y sus videos salen primero en «Fuente» de su película o episodio.
struct OneDriveSettings: View {
    @State private var observer = ModelObserver(AppEnvironment.shared.oneDriveSetup)
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var confirmUnlink = false
    @State private var draftID = ""
    @State private var pickingFolder = false

    var body: some View {
        let model = observer.model
        Form {
            Section {
                switch model.state {
                case .off:
                    Text("Usa la misma de la TV. Si aún no la tienes: en entra.microsoft.com › Registros de aplicaciones › Nuevo registro, ponle «Orbital», elige «Cuentas personales de Microsoft» y créala. En «Autenticación» activa «Permitir flujos de clientes públicos». Copia su «Id. de aplicación (cliente)».")
                        .recipe(.footnote)
                    TextField("Id. de aplicación (cliente)", text: $draftID).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .onAppear { draftID = model.clientID }
                    if !draftID.trimmingCharacters(in: .whitespaces).isEmpty { Button("Guardar") { model.setClientID(draftID) } }
                case .unlinked:
                    Button("Conectar OneDrive") { Task { await model.link() } }
                    Text("Aparece un código para escribir en microsoft.com/link. Solo pide leer tus archivos.").recipe(.caption, color: DS.textFaint)
                case .linking(let code, let url):
                    VStack(alignment: .leading, spacing: DS.Space.s2) {
                        Text("Escribe este código en \(url.replacingOccurrences(of: "https://", with: "")):").recipe(.footnote)
                        Text(verbatim: code).font(DS.TextRecipe.display.font.weight(.bold)).foregroundStyle(DS.text).textSelection(.enabled).monospaced()
                        HStack { ProgressView(); Text("Esperando…").recipe(.footnote) }
                    }
                    VStack(alignment: .leading, spacing: DS.Space.s1) {
                        Label("Orbital solo lee: nunca cambia ni borra nada", systemImage: "lock")
                        Label("Solo mira la carpeta que elijas después", systemImage: "folder")
                        Label("Tus videos se ven directo, sin bajarlos completos", systemImage: "play.circle")
                    }
                    .font(DS.TextRecipe.footnote.font).foregroundStyle(DS.textMuted)
                    // En el mismo iPhone: se copia el código y se abre la página de Microsoft (ahí solo se pega).
                    Button("Copiar el código y abrir Microsoft", systemImage: "arrow.up.forward.app") {
                        UIPasteboard.general.string = code
                        if let link = URL(string: url) { openURL(link) }
                    }
                    Button("Cancelar", role: .cancel) { model.cancelLinking() }
                case .linked:
                    Label("OneDrive conectado", systemImage: "checkmark.icloud")
                    Button("Desconectar OneDrive", role: .destructive) { confirmUnlink = true }
                case .failed(let message):
                    DSNotice(verbatim: env.message(message), tone: .error)
                    Button("Volver a intentar") { Task { await model.link() } }
                }
            } header: { Text("Cuenta") }
            .listRowBackground(DS.surface)

            if model.state == .linked {
                Section {
                    // En una hoja propia: al elegir, se cierra entera y vuelves aquí a ver lo que encontró.
                    Button { pickingFolder = true } label: {
                        HStack(spacing: DS.Space.s2) {
                            SettingsRow(title: "Carpeta", symbol: "folder", tint: DS.ListTint.library,
                                        value: model.folder.isEmpty ? Text("Elige una") : model.folder == "/" ? Text("Todo tu OneDrive") : Text(verbatim: model.folder))
                            Image(systemName: "chevron.right").font(DS.TextRecipe.caption.font.weight(.semibold)).foregroundStyle(DS.textFaint)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: { Text("Dónde están tus películas") } footer: {
                    Text("Solo se mira esa carpeta y sus subcarpetas. Cada video se reconoce por su nombre («Dune Part Two (2024).mkv», «Severance S01E03.mkv»).")
                }
                .listRowBackground(DS.surface)

                if !model.folder.isEmpty {
                    Section {
                        if let index = model.index {
                            LabeledContent("Películas") { Text(verbatim: "\(model.movies)") }
                            LabeledContent("Episodios") { Text(verbatim: "\(model.episodes)") }
                            if index.unmatched > 0 {
                                Text("\(index.unmatched) sin ficha: revisa que su nombre diga el título (y el año).").recipe(.caption, color: DS.textFaint)
                            }
                            Text("Revisada \(index.scannedAt, format: .relative(presentation: .named))").recipe(.caption, color: DS.textFaint)
                        }
                        if let error = model.scanError { DSNotice(verbatim: env.message(error), tone: .warn) }
                        Button { Task { await model.rescan() } } label: {
                            HStack { Text("Revisar ahora"); if model.scanning { Spacer(); ProgressView() } }
                        }
                        .disabled(model.scanning)
                    } header: { Text("Lo que encontré") } footer: {
                        Text("Tus películas y series salen en Descargas › Mi media: se ven al instante y se bajan al iPhone.")
                    }
                    .listRowBackground(DS.surface)
                }
            }
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle("OneDrive").navigationBarTitleDisplayMode(.inline)
        .onAppear { model.refresh() }
        .sheet(isPresented: $pickingFolder) {
            NavigationStack { OneDriveFolderPicker(path: "", model: model) { pickingFolder = false } }
        }
        .confirmationDialog("¿Desconectar OneDrive?", isPresented: $confirmUnlink, titleVisibility: .visible) {
            Button("Desconectar", role: .destructive) { Task { await model.unlink() } }
        } message: { Text("Mi media se vacía. Lo que ya bajaste al iPhone se queda.") }
    }
}

/// Una carpeta de tu OneDrive: sus subcarpetas para entrar y «Usar esta carpeta».
struct OneDriveFolderPicker: View {
    let path: String
    let model: OneDriveModel
    /// Cierra el selector entero (no solo esta carpeta).
    let done: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var folders: [OneDriveFolder]?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                // En la raíz: todo tu OneDrive (se recorren hasta cuatro niveles de carpetas).
                Button(path.isEmpty ? "Usar todo mi OneDrive" : "Usar esta carpeta", systemImage: "checkmark.circle") {
                    Task { await model.choose(path.isEmpty ? "/" : path) }
                    done()
                }
            } footer: {
                if path.isEmpty { Text("Mejor elige la carpeta de tus películas: con todo tu OneDrive la revisión tarda más.") }
                else { Text(verbatim: path) }
            }
            .listRowBackground(DS.surface)
            Section {
                if let error {
                    DSNotice(verbatim: env.message(error), tone: .warn)
                    Button("Volver a intentar", systemImage: "arrow.clockwise") { Task { await load() } }
                }
                else if let folders {
                    if folders.isEmpty { Text("No hay más carpetas aquí.").recipe(.footnote) }
                    ForEach(folders) { folder in
                        NavigationLink { OneDriveFolderPicker(path: folder.path, model: model, done: done) } label: {
                            Label(folder.name, systemImage: "folder")
                        }
                    }
                } else { ProgressView().frame(maxWidth: .infinity) }
            }
            .listRowBackground(DS.surface)
        }
        .scrollContentBackground(.hidden).background(Backdrop())
        .navigationTitle(path.isEmpty ? Text("OneDrive") : Text(verbatim: (path as NSString).lastPathComponent))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if path.isEmpty { ToolbarItem(placement: .cancellationAction) { Button("Cancelar", action: done) } } }
        .task { await load() }
    }

    private func load() async {
        error = nil; folders = nil
        do { folders = try await model.folders(path) } catch { self.error = "\(error)" }
    }
}
