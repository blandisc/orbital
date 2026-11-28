import SwiftUI
import OrbitalCore
import OrbitalModels

/// Ajustes › Tus idiomas (N4-A, Fernando, 4 nov: «asegúrate que sea fácil cambiar tus idiomas preferidos, que esté claro en
/// ajustes»): el único lugar de tus idiomas. Una lista en orden que se reacomoda (arrastrar, el menú «Subir» / «Bajar» de cada
/// uno, ⌥↑ / ⌥↓ con teclado y las acciones de VoiceOver), con «Idioma original» como un renglón más; se agrega y se quita.
/// El primero es tu idioma (no puede ser «Idioma original»). De aquí salen las versiones, el reproductor y Torrentio.
struct YourLanguagesView: View {
    @Environment(AppEnvironment.self) private var env
    let settings: ModelObserver<SettingsModel>
    @FocusState private var focused: String?

    /// Dentro de la página «Idiomas» (ID-A): solo su grupo, sin su propio formulario ni título.
    var embedded = false

    var body: some View {
        if embedded { audioSection } else {
            Form { audioSection }
                .tint(DS.accent)
                .scrollContentBackground(.hidden).background(Backdrop())
                .dsInlineTitle("Tus idiomas")
                .readableListWidth()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("your-languages")
        }
    }

    /// El audio, en orden: con cuál arranca y cuál prueba después.
    @ViewBuilder private var audioSection: some View {
        let model = settings.model
        let list = model.settings.yourLanguages
        let ui = model.settings.uiLanguage
        Section {
                ForEach(Array(list.enumerated()), id: \.element) { index, code in
                    row(code, index: index, list: list, ui: ui, model: model)
                }
                .onMove { from, to in
                    var next = list
                    next.move(fromOffsets: from, toOffset: to)
                    save(model, Self.normalized(next))
                }
                if list.count < Services.addableLanguages.count {
                    PaneLink(Text("Agregar idioma")) { YourLanguagesPicker(settings: settings) } label: {
                        Label { Text("Agregar idioma").foregroundStyle(DS.text) } icon: {
                            Image(systemName: "plus.circle.fill").font(DS.TextRecipe.cardTitle.font).foregroundStyle(DS.accent).frame(width: DS.SettingsLook.rowIcon)
                        }
                    }
                    .accessibilityIdentifier("languages-add")
                }
            } header: {
                if embedded { Text("Lo que ves (el audio, en este orden)") }
            } footer: {
                Text("En este orden busca versiones y elige con cuál arranca. Si no hay en el primero, prueba el siguiente.")
            }
            .listRowBackground(DS.surface)
    }

    /// Un idioma: su lugar, su nombre (el primero dice «Tu idioma») y su menú.
    @ViewBuilder private func row(_ code: String, index: Int, list: [String], ui: String, model: SettingsModel) -> some View {
        let canUp = index > 0 && !(code == "original" && index == 1)
        let canDown = index < list.count - 1 && !(index == 0 && list[1] == "original")
        let canRemove = list.filter { $0 != "original" && $0 != code }.count > 0
        let move = { (step: Int) in save(model, Self.moved(list, code, by: step)) }
        let remove = { save(model, Self.normalized(list.filter { $0 != code })) }
        // IP-B (24 nov 2026, «que también se vea un poquito más pulido»): el lugar en un círculo (el primero, relleno: con
        // ese arranca), la bandera en su propio lugar y el nombre más fuerte.
        HStack(spacing: DS.Space.s4) {
            Text(verbatim: "\(index + 1)").recipe(.label, color: index == 0 ? DS.onSolidPrimary : DS.textMuted).monospacedDigit()
                .frame(width: DS.SettingsLook.rowIcon, height: DS.SettingsLook.rowIcon)
                .background(Circle().fill(index == 0 ? DS.solidPrimary : .clear))
                .overlay(Circle().strokeBorder(index == 0 ? .clear : DS.hairline, lineWidth: DS.Stroke.regular))
            LanguageMark(code: code)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: Self.name(code, ui)).recipe(.labelLarge, color: DS.text)
                if index == 0 { Text("Con este arranca si lo hay").recipe(.footnote, color: DS.textMuted) }
                else if code == "original" { Text("El de cada película o serie (japonés en un anime)").recipe(.footnote, color: DS.textMuted) }
            }
            Spacer(minLength: DS.Space.s2)
            Menu {
                if canUp { Button("Subir", systemImage: "arrow.up") { move(-1) } }
                if canDown { Button("Bajar", systemImage: "arrow.down") { move(1) } }
                if canRemove { Button("Quitar", systemImage: "minus.circle", role: .destructive, action: remove) }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(DS.textMuted).frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
            }
            .accessibilityLabel(Text("Opciones"))
        }
        .contentShape(Rectangle())
        .focusable()
        .focused($focused, equals: code)
        // Teclado (iPad y Mac): ⌥↑ y ⌥↓ lo suben y lo bajan; ⌫ lo quita.
        .onKeyPress(phases: .down) { press in
            if press.modifiers.contains(.option), press.key == .upArrow, canUp { move(-1); return .handled }
            if press.modifiers.contains(.option), press.key == .downArrow, canDown { move(1); return .handled }
            if press.key == .delete, canRemove { remove(); return .handled }
            return .ignored
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if canUp { Button("Subir") { move(-1) } }
            if canDown { Button("Bajar") { move(1) } }
            if canRemove { Button("Quitar", action: remove) }
        }
        .swipeActions { if canRemove { Button("Quitar", role: .destructive, action: remove).tint(DS.danger) } }
        .moveDisabled(index == 0 && list.count > 1 && list[1] == "original")
        .accessibilityIdentifier("language-\(code)")
    }

    /// Guarda y lo dice, como la TV: «Guardé tus idiomas · La próxima búsqueda ya los usa».
    private func save(_ model: SettingsModel, _ list: [String]) {
        let before = model.settings.yourLanguages
        withAnimation(DS.Motion.press) { model.setLanguages(list) }
        if model.settings.yourLanguages != before { env.notify(Strings.tr("Guardé tus idiomas", language: model.settings.uiLanguage),
                                                               detail: Strings.tr("La próxima búsqueda ya los usa", language: model.settings.uiLanguage), tone: .success) }
    }

    /// El nombre de un idioma de la lista: «Latino», «Castellano», «Español (cualquiera)», «Idioma original», «Inglés»…
    static func name(_ code: String, _ ui: String) -> String {
        switch code {
        case "original": Strings.tr("Idioma original", language: ui)
        case "es": Strings.tr("Español (cualquiera)", language: ui)
        default: Streams.versionLanguageName(code, in: ui)
        }
    }

    /// «Latino, Idioma original, Inglés…»: para el renglón de Ajustes.
    /// «Latino y original», «Latino, original +2»: corto, para que quepa en el renglón de Ajustes en una línea (AJ-A, 20 nov
    /// 2026: «Latino, Idioma original…» se partía en dos y se cortaba).
    static func summary(_ list: [String], _ ui: String) -> String {
        let names = list.prefix(2).map { $0 == "original" ? Strings.tr("original", language: ui) : name($0, ui) }
        let and = ui == "en" ? " and " : " y "
        if list.count > 2 { return names.joined(separator: ", ") + " +\(list.count - 2)" }
        return names.joined(separator: and)
    }

    /// Sube o baja uno.
    static func moved(_ list: [String], _ code: String, by step: Int) -> [String] {
        var next = list
        guard let i = next.firstIndex(of: code), next.indices.contains(i + step) else { return list }
        next.swapAt(i, i + step)
        return normalized(next)
    }

    /// «Idioma original» nunca va primero: el primero es tu idioma.
    static func normalized(_ list: [String]) -> [String] {
        guard list.first == "original", list.count > 1 else { return list }
        var next = list
        next.swapAt(0, 1)
        return next
    }
}

/// «Agregar idioma»: los que todavía no están en tu lista; se agrega al final.
struct YourLanguagesPicker: View {
    let settings: ModelObserver<SettingsModel>
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let model = settings.model
        let list = model.settings.yourLanguages
        let ui = model.settings.uiLanguage
        Form {
            Section {
                ForEach(Services.addableLanguages.filter { !list.contains($0) }, id: \.self) { code in
                    Button {
                        model.setLanguages(list + [code])
                        env.notify(Strings.tr("Guardé tus idiomas", language: ui), detail: Strings.tr("La próxima búsqueda ya los usa", language: ui), tone: .success)
                        dismiss()
                    } label: {
                        Label { Text(verbatim: YourLanguagesView.name(code, ui)).foregroundStyle(DS.text) } icon: { LanguageMark(code: code) }
                    }
                    .accessibilityIdentifier("languages-add-\(code)")
                }
            } footer: { Text("Se agrega al final de tu lista.") }
            .listRowBackground(DS.surface)
        }
        .tint(DS.accent)
        .scrollContentBackground(.hidden).background(Backdrop())
        .dsInlineTitle("Agregar idioma")
        .readableListWidth()
    }
}
