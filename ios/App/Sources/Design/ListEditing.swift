import SwiftUI
import OrbitalCore

/// Editar tus listas (Fernando, 6 nov 2026: «quiero poder editar las listas, quitarle y ponerle elementos, y que sea
/// evidente»). Solo en las listas que son tuyas (Mi lista y tus listas de Trakt, `TitleActions.isEditable`); un ranking, un
/// catálogo o Para ti no llevan nada de esto y no parecen editables.
///
/// - El marcador del póster (`DSBookmarkToggle`) es un botón: un toque lo quita de Mi lista, con «Deshacer» en el aviso.
/// - «Editar» en la barra (`ListEditToolbar`): cada póster lleva su «−» (`DSRemoveMark`) y «+» abre la búsqueda para agregar
///   (`AddToListSheet`). «Listo» termina.
/// - Mantener el dedo (o clic secundario): «Quitar de esta lista».
/// Con teclado y puntero en iPad y Mac: los mismos botones (con su realce), ⌘E edita y ⌘N agrega.

/// El marcador de un póster que está en Mi lista, ahora como control: un toque lo quita (sin pregunta; el aviso trae
/// «Deshacer»). Se ve igual que la placa de siempre, con el área de toque de 44 pt.
struct DSBookmarkToggle: View {
    /// «Mi lista» o el nombre de la lista (para VoiceOver: «Quitar de Mi lista»).
    let listName: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "bookmark.fill").font(DS.TextRecipe.badge.font).foregroundStyle(DS.paper)
                .padding(DS.Space.s1 + DS.Space.s1 / 2)
                .background(DS.badgeBackground, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                .padding(DS.Space.s2)
                .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerHover(.highlight, radius: DS.Radius.sm)
        .accessibilityLabel(Text("Quitar de \(listName)"))
        .accessibilityIdentifier("poster-unbookmark")
    }
}

/// El «−» de cada póster mientras editas una lista: rojo sobre un círculo claro, en la esquina, imposible de no ver.
struct DSRemoveMark: View {
    let listName: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(DS.paper, DS.danger)
                .font(DS.TextRecipe.section.font)
                .frame(minWidth: DS.Size.touchTarget, minHeight: DS.Size.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerHover(.highlight, radius: DS.Radius.md)
        .accessibilityLabel(Text("Quitar de \(listName)"))
        .accessibilityIdentifier("poster-remove")
        .transition(.scale.combined(with: .opacity))
    }
}

extension View {
    /// Un póster de una lista tuya: el «−» en la esquina mientras editas (y el póster deja de abrir la ficha, para no
    /// tropezar), y «Quitar de esta lista» al mantener el dedo. Sin `remove` (lista ajena), nada cambia.
    /// `menu: false` si el póster ya trae su menú con «Quitar de esta lista» (los de Para ti).
    func listEditable(editing: Bool, listName: Text, menu: Bool = true, remove: (() -> Void)?) -> some View {
        modifier(ListEditableModifier(editing: editing, listName: listName, menu: menu, remove: remove))
    }
}

private struct ListEditableModifier: ViewModifier {
    let editing: Bool
    let listName: Text
    let menu: Bool
    let remove: (() -> Void)?

    func body(content: Content) -> some View {
        if let remove {
            let marked = content
                .allowsHitTesting(!editing)
                .overlay(alignment: .topTrailing) { if editing { DSRemoveMark(listName: listName, action: remove) } }
            if menu {
                marked.contextMenu { Button(role: .destructive, action: remove) { Label("Quitar de esta lista", systemImage: "minus.circle") } }
            } else {
                marked
            }
        } else {
            content
        }
    }
}

/// «Editar» · «Listo» y «Agregar» (+) en la barra de una lista tuya. Con teclado: ⌘E y ⌘N.
struct ListEditToolbar: ToolbarContent {
    @Binding var editing: Bool
    let add: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: add) { Label("Agregar", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("list-add")
            Button { withAnimation(DS.Motion.base(reduceMotion)) { editing.toggle() } } label: {
                Text(editing ? "Listo" : "Editar").fontWeight(editing ? .semibold : .regular)
            }
            .keyboardShortcut("e", modifiers: .command)
            .accessibilityIdentifier("list-edit")
        }
    }
}

/// «Agregar a …»: busca un título por nombre y agrégalo con un toque; lo que ya está en la lista lleva su palomita y un
/// toque lo quita. La hoja se queda abierta para agregar varios.
struct AddToListSheet: View {
    @Environment(\.titleName) var titleName
    let listName: Text
    let search: (String) async -> [SearchResult]
    let contains: (String) -> Bool
    let toggle: (SearchResult) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var searching = false
    /// Se vuelve a pintar al agregar (la palomita sale al instante).
    @State private var version = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Busca una película o serie", text: $query).submitLabel(.search)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                        .onSubmit { Task { await run() } }
                        .accessibilityIdentifier("list-add-search")
                }
                .listRowBackground(DS.surface)
                Section {
                    if searching { DSLoadingState() }
                    else if results.isEmpty && !query.isEmpty { Text("Sin resultados: prueba con el título en inglés.").recipe(.footnote) }
                    ForEach(results) { r in row(r) }
                }
                .listRowBackground(DS.surface)
            }
            .readableListWidth()
            .scrollContentBackground(.hidden).background(Backdrop())
            .navigationTitle(Text("Agregar a \(listName)")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .task(id: query) {
                try? await Task.sleep(nanoseconds: DS.Timing.searchDebounce)
                guard !Task.isCancelled else { return }
                await run()
            }
        }
    }

    private func row(_ r: SearchResult) -> some View {
        let inList = contains(r.metaID)
        return Button { Task { await toggle(r); version += 1 } } label: {
            HStack(spacing: DS.Space.s3) {
                PosterView(url: r.poster, title: titleName(r.title, id: r.metaID, kind: r.kind)).frame(width: DS.Size.thumbSmall)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: titleName(r.title, id: r.metaID, kind: r.kind)).recipe(.cardTitle)
                    Text(verbatim: r.year).recipe(.caption)
                }
                Spacer(minLength: 0)
                Image(systemName: inList ? "checkmark.circle.fill" : "plus.circle")
                    .font(DS.TextRecipe.section.font)
                    .foregroundStyle(inList ? DS.text : DS.textMuted)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id("\(r.id)-\(version)")
        .accessibilityLabel(Text(verbatim: titleName(r.title, id: r.metaID, kind: r.kind)))
        .accessibilityValue(inList ? Text("En la lista") : Text(""))
        .accessibilityHint(inList ? Text("Quitar de \(listName)") : Text("Agregar a \(listName)"))
    }

    private func run() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { results = []; return }
        searching = results.isEmpty
        let found = await search(text)
        guard text == query.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        results = found
        searching = false
    }
}
