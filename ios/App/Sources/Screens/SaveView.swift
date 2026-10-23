import SwiftUI
import OrbitalCore
import OrbitalModels

/// «Guardar en…»: en qué listas va un título, varias a la vez. Arriba tus listas de Trakt (las recientes primero, y una
/// nueva entra arriba); abajo, siempre en el mismo lugar, las fijas: tu watchlist de Trakt (la de por omisión) y Mi lista de
/// Stremio. **Nada salta al llegar las listas** (`SaveSheetPlan`): su zona aparta su alto al abrir, con renglones esqueleto
/// del mismo alto que los de verdad, y las fijas no dependen de la red.
struct SaveView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var typeSize
    var observer: ModelObserver<TitleModel>
    @State private var naming = false
    @State private var newName = ""
    /// Cuántos renglones aparta la zona de tus listas: se decide al abrir y ya no cambia.
    @State private var reserved: Int?
    /// El alto de un renglón (se mide en una fija: es la misma pieza), para apartar la zona de listas.
    @State private var rowHeight: CGFloat = DS.Size.touchTarget

    var body: some View {
        let m = observer.model
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                header(m).padding(.bottom, DS.Space.s2)
                if m.traktAvailable {
                    PanelGroupTitle(title: "Tus listas de Trakt")
                    lists(m, reserved: reserved ?? reservedRows(m))
                    PanelGroupTitle(title: "Principales").padding(.top, DS.Space.s2)
                }
                ForEach(Array(m.fixedDestinations.enumerated()), id: \.element) { index, destination in
                    CheckRow(title: SaveDestinationName.text(destination), symbol: SaveDestinationName.symbol(destination),
                             color: SaveDestinationName.tint(destination), checked: m.isSaved(in: destination)) { Task { await m.toggle(destination) } }
                        .accessibilityIdentifier("save-fixed-\(destination.rawValue)")
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if index == 0 { rowHeight = $0 } }
                }
                if let message = m.message { DSNotice(verbatim: env.message(message), tone: .error) }
            }
            .padding(DS.Space.gutter)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { if reserved == nil { reserved = reservedRows(m) } }
        .task { if m.lists == nil { await m.loadLists() } }
        .alert("Nueva lista", isPresented: $naming) {
            TextField("Nombre", text: $newName)
            Button("Crear") { let name = newName.trimmingCharacters(in: .whitespacesAndNewlines); newName = ""; Task { await m.createList(named: name) } }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancelar", role: .cancel) { newName = "" }
        } message: { Text("Se crea en Trakt (privada) y este título entra en ella.") }
    }

    private func reservedRows(_ m: TitleModel) -> Int {
        SaveSheetPlan.reservedRows(loaded: m.lists?.count, cached: m.expectedListCount, fallback: DS.SaveSheet.fallbackRows, cap: DS.SaveSheet.visibleRows)
    }

    /// El título y, a la derecha (debajo con letra grande), «Nueva lista…»: siempre en el mismo lugar, aunque carguen las listas.
    private func header(_ m: TitleModel) -> some View {
        let title = VStack(alignment: .leading, spacing: DS.Space.s1) {
            Text("Guardar en…").recipe(.title).accessibilityAddTraits(.isHeader)
            Text(verbatim: m.title).recipe(.footnote).lineLimit(1)
        }
        let newList = Button { naming = true } label: { Label("Nueva lista…", systemImage: "plus").frame(minHeight: DS.Size.touchTarget) }
            .buttonStyle(.glass).accessibilityIdentifier("save-new-list")
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Space.s2) { title; if m.traktAvailable { newList } }
            } else {
                HStack(alignment: .center, spacing: DS.Space.s3) { title; Spacer(minLength: DS.Space.s2); if m.traktAvailable { newList } }
            }
        }
    }

    /// Tus listas en su zona de alto fijo: esqueletos mientras llegan, luego las listas (recientes primero) en esos mismos
    /// renglones. Si hay más de las que caben, se desplazan dentro de la zona; las fijas de abajo no se mueven.
    private func lists(_ m: TitleModel, reserved: Int) -> some View {
        let rows = SaveSheetPlan.rows(lists: m.lists, expected: reserved)
        let height = CGFloat(reserved) * rowHeight + CGFloat(max(0, reserved - 1)) * DS.Space.s2
        return ScrollView {
            VStack(spacing: DS.Space.s2) {
                ForEach(rows) { row in
                    switch row {
                    case .list(let list):
                        CheckRow(title: Text(verbatim: list.name), symbol: "list.bullet", color: DS.ListTint.list, checked: list.contains) { Task { await m.toggleList(list.id) } }
                            .accessibilityIdentifier("save-list-\(list.id)")
                    case .skeleton:
                        CheckRowSkeleton()
                    case .empty:
                        Text("Aún no tienes listas en Trakt.").recipe(.footnote)
                            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
                    }
                }
            }
        }
        .frame(height: height)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(rows.count > reserved ? .visible : .hidden)
        // Mientras cargan, VoiceOver lo dice una vez en lugar de leer renglones vacíos.
        .accessibilityElement(children: m.lists == nil ? .ignore : .contain)
        .accessibilityLabel(m.lists == nil ? Text("Cargando tus listas de Trakt") : Text("Tus listas de Trakt"))
        .accessibilityIdentifier(m.lists == nil ? "save-lists-loading" : "save-lists")
        .animation(nil, value: m.lists)   // llegan en su lugar: sin deslizar ni recorrer nada
    }
}
