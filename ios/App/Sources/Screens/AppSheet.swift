import SwiftUI

/// Toda hoja de la app pasa por aquí: `appSheet` es `.sheet` con la app (`AppEnvironment`) puesta a mano en lo que muestra.
/// En la Mac («Diseñada para iPad») la hoja arma su contenido para leer sus preferencias antes de heredar el entorno de quien
/// la abre, y una vista con `@Environment(AppEnvironment.self)` adentro tronaba la app (la 2491, 23 nov 2026: abrir una hoja
/// con una película puesta). Es lo mismo que pasaba con las cubiertas (`DesignRulesTests+Covers`).
/// También declara las barras del iPhone Duo (`duoBars`): cada hoja es su propia presentación y UIKit le pregunta a ella.
/// `DesignRulesTests+Sheets` falla si vuelve un `.sheet(` suelto.
extension View {
    func appSheet<Sheet: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(FlagSheet(isPresented: isPresented, onDismiss: onDismiss, sheet: content))
    }

    func appSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                   @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(ItemSheet(item: item, onDismiss: onDismiss, sheet: content))
    }
}

private struct FlagSheet<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let sheet: () -> Sheet
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss) { sheet().environment(env).duoBars() }
    }
}

private struct ItemSheet<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let sheet: (Item) -> Sheet
    @Environment(AppEnvironment.self) private var env

    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: onDismiss) { sheet($0).environment(env).duoBars() }
    }
}
