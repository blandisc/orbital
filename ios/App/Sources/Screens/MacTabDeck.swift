import SwiftUI

/// Las pestañas de la Mac como una baraja (23 nov 2026, Fernando: «le pico explorar y se tarda como 2 segundos en cambiar.
/// Debería ser instantáneo»). Con las pestañas del sistema (`TabView`), cambiar de pestaña sacaba la pantalla de la ventana y
/// al regresar SwiftUI la volvía a dibujar entera y volvía a correr sus `.task`: Instruments en la app instalada (2495, Release)
/// marcó la app congelada 0.6–0.7 s en cada cambio y 1.1–1.5 s la primera vez a Explorar. Aquí cada pantalla se arma la
/// primera vez que la abres y después solo se esconde (transparente, sin toques ni VoiceOver): cambiar es mostrar otra carta.
///
/// Lo que antes se detenía al desaparecer (el cielo, el vaivén de los canales, la marca de Descargas, el cursor de Buscar)
/// ahora lee `@TabHidden` o `.onTabHidden`. Nunca un valor del entorno que cambie con la pestaña: cambiar el entorno de una
/// pantalla obliga a SwiftUI a volver a resolver cada texto y color de ella (la primera versión lo hacía y cada cambio seguía
/// costando ~0.7 s). Regla en docs/ios-interfaz.md § «Cambiar de pestaña en la Mac» y `testMacTabsStayBuilt`.
struct MacTabDeck<Home: View, Explore: View, Library: View, Search: View>: View {
    /// Solo la Mac: en el iPad y el iPhone siguen las pestañas del sistema (su barra, su animación).
    static var isOn: Bool { ThisDevice.isMac }

    let current: Int
    let home: Home, explore: Explore, library: Library, search: Search
    /// Las pantallas que ya se abrieron (las demás no se arman hasta que las pidas: el arranque no paga Explorar).
    @State private var mounted: Set<Int> = []

    var body: some View {
        let shown = mounted.union([current])
        ZStack {
            card(0, shown) { home }
            card(1, shown) { explore }
            card(3, shown) { library }
            card(2, shown) { search }
        }
        .onChange(of: current, initial: true) { _, now in if !mounted.contains(now) { mounted.insert(now) } }
    }

    @ViewBuilder private func card(_ id: Int, _ shown: Set<Int>, @ViewBuilder _ content: () -> some View) -> some View {
        if shown.contains(id) {
            let on = id == current
            content()
                .opacity(on ? 1 : 0)
                .allowsHitTesting(on)
                .accessibilityHidden(!on)
                .zIndex(on ? 1 : 0)
                .environment(\.macTabID, id)   // fijo: la carta siempre es la misma pestaña
        }
    }
}

extension EnvironmentValues {
    /// La pestaña de la baraja de la Mac a la que pertenece esta pantalla (`MacTabDeck`); nil fuera de la Mac. No cambia nunca
    /// para una misma pantalla: si está a la vista o no se pregunta a `MacTabs` (`@TabHidden`, `.onTabHidden`).
    @Entry var macTabID: Int?
}

/// Esta pantalla está armada pero escondida en la baraja de la Mac: no anima, no toma el cursor y sus atajos no cuentan.
/// Solo vuelve a pintar a la vista que lo lee (en iPhone y iPad siempre `false`: ahí la pestaña escondida desaparece).
@MainActor @propertyWrapper struct TabHidden: DynamicProperty {
    @Environment(\.macTabs) private var tabs
    @Environment(\.macTabID) private var id
    init() {}
    var wrappedValue: Bool {
        guard let id, let tabs else { return false }
        return tabs.current != id
    }
}

extension View {
    /// Lo que antes iba en `onAppear`/`onDisappear` y en la baraja de la Mac ya no ocurre al cambiar de pestaña: `true` al
    /// esconderse, `false` al volver. Solo este modificador se vuelve a pintar, no la pantalla.
    func onTabHidden(_ action: @escaping (Bool) -> Void) -> some View { modifier(TabHiddenWatch(action: action)) }

    /// Un atajo de teclado que solo vale si su pantalla está a la vista: en la baraja de la Mac las pantallas escondidas
    /// siguen armadas y su ⌘N le ganaba a la de la pantalla que ves.
    func shownKeyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        modifier(ShownShortcut(shortcut: KeyboardShortcut(key, modifiers: modifiers)))
    }
    func shownKeyboardShortcut(_ shortcut: KeyboardShortcut) -> some View {
        modifier(ShownShortcut(shortcut: shortcut))
    }
}

private struct TabHiddenWatch: ViewModifier {
    let action: (Bool) -> Void
    @TabHidden private var hidden
    func body(content: Content) -> some View { content.onChange(of: hidden) { _, now in action(now) } }
}

private struct ShownShortcut: ViewModifier {
    let shortcut: KeyboardShortcut
    @TabHidden private var hidden
    func body(content: Content) -> some View { content.keyboardShortcut(hidden ? nil : shortcut) }
}
