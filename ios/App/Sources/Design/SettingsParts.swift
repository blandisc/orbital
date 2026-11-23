import SwiftUI

// Piezas de Ajustes: el renglón con su ícono de color (como las listas: solo el color, sin fondo), la tarjeta de perfil y
// las vistas previas de cada estilo de Inicio (se elige viéndolo, no por su nombre).

/// Un renglón de Ajustes que lleva a su página: ícono en su color, nombre y, a la derecha, cómo está ahora.
struct SettingsRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    var value: Text?
    /// Lleva a otra página (con flecha). Sin ella, el valor se corre para quedar en la misma columna.
    var linked = true
    @Environment(\.dynamicTypeSize) private var typeSize
    /// En la barra lateral de Ajustes (Mac y iPad ancho, AJ-A) cada renglón es solo su nombre: el valor lo dice la página.
    @Environment(\.settingsPane) private var pane

    var body: some View {
        let value = pane == nil ? value : nil
        LabeledContent {
            // Hasta dos renglones; con letra grande el valor baja bajo el nombre, completo y a la izquierda («Latino, Idioma ori…»
            // se cortaba, revisión 2).
            if let value { value.lineLimit(typeSize.isAccessibilitySize ? nil : 2).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading).padding(.trailing, linked ? 0 : DS.SettingsLook.chevronSlot) }
        } label: {
            Label {
                Text(title).foregroundStyle(DS.text)
            } icon: {
                Image(systemName: symbol).font(DS.TextRecipe.cardTitle.font).foregroundStyle(tint)
                    .frame(width: DS.SettingsLook.rowIcon)
            }
        }
    }
}

/// Arriba de Ajustes: tu avatar (con un lápiz: se ve que se toca), tu nombre y qué está conectado.
struct ProfileCard: View {
    let avatar: String
    let title: Text
    let detail: Text
    let edit: () -> Void

    var body: some View { bodyContent.pointerHover(.lift) }
    @ViewBuilder private var bodyContent: some View {
        Button(action: edit) {
            HStack(spacing: DS.Space.s4) {
                AvatarImage(id: avatar, size: DS.SettingsLook.profileAvatar)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil").font(DS.TextRecipe.badge.font).foregroundStyle(DS.onPrimary)
                            .frame(width: DS.SettingsLook.editBadge, height: DS.SettingsLook.editBadge)
                            .background(DS.primary, in: Circle())
                    }
                VStack(alignment: .leading, spacing: DS.Space.s1) {
                    title.recipe(.cardTitle)
                    detail.recipe(.footnote, color: DS.textMuted).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Space.s1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Cambiar avatar"))
    }
}

/// Un renglón con palomita (en qué listas está un título, «Guardar en…»): su glifo de color, el nombre y ✓ si está.
struct CheckRow: View {
    let title: Text
    let symbol: String
    let color: Color
    let checked: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s2) {
                PanelIcon(symbol: symbol, color: color)
                title.recipe(.labelLarge, color: DS.text).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)   // con letra grande no se corta
                Spacer(minLength: DS.Space.s2)
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(DS.TextRecipe.title.font.weight(.regular))   // ds-exception: la casilla del sistema va en peso regular, como en Ajustes de iOS
                    .foregroundStyle(checked ? DS.accent : DS.textFaint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(DS.Space.s2)
            .frame(minHeight: DS.Size.touchTarget)   // todo el renglón se toca, nunca menos que un objetivo táctil
            .dsCard(.row, translucent: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
        .dsFeedback(.selection, trigger: checked)
    }
}

/// De qué temporadas sale «Un Simpson al azar»: dos atajos (las clásicas, todas) y una cápsula por temporada. Siempre queda
/// al menos una (quitar la última no hace nada).
struct SimpsonsSeasonsPicker: View {
    let selected: [Int]
    let available: [Int]
    let classics: [Int]
    let change: ([Int]) -> Void

    var body: some View {
        let chosen = Set(selected)
        VStack(alignment: .leading, spacing: DS.Space.s2) {
            HStack(spacing: DS.Space.s2) {
                PanelChip(title: Text("Las clásicas (\(Int(classics.first ?? 0))–\(Int(classics.last ?? 0)))"), selected: chosen == Set(classics)) { change(classics) }
                PanelChip(title: Text("Todas"), selected: Set(available).isSubset(of: chosen)) { change(available) }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: DS.Size.touchTarget + DS.Space.s4), spacing: DS.Space.s2)], spacing: DS.Space.s2) {
                ForEach(available, id: \.self) { season in
                    PanelChip(title: Text(verbatim: "\(season)"), selected: chosen.contains(season)) {
                        var next = chosen
                        if next.contains(season) { next.remove(season) } else { next.insert(season) }
                        if !next.isEmpty { change(next.sorted()) }
                    }
                    .accessibilityLabel(Text("Temporada \(season)"))
                }
            }
        }
        .dsFeedback(.selection, trigger: selected)
        .accessibilityElement(children: .contain)   // cada temporada conserva su nombre
        .accessibilityIdentifier("simpsons-seasons")
    }
}

/// MA1 (Fernando, 16 nov 2026): en la Mac, Ajustes es lista y detalle, como Ajustes del Sistema: un renglón de la lista abre su
/// página a la derecha, sin ir y volver. Lo pone `SettingsView` solo en la Mac; sin él (iPhone, iPad), `SettingsLink` es un
/// `NavigationLink` de siempre. La página la arma `SettingsView` en cada pasada (con los valores al día), no el renglón.
struct SettingsPane {
    let current: SettingsPage
    let open: (SettingsPage) -> Void
}

/// Las páginas de Ajustes que se abren desde la lista.
enum SettingsPage: String, CaseIterable {
    case languages, appearance, playback, alerts, downloads, accounts, addons, oneDrive
    case orbital, voice, advanced, learn

    /// El nombre de la página, el mismo del renglón: en la Mac va arriba de la página, a la derecha (MA2).
    var title: Text {
        switch self {
        case .languages: Text("Idiomas")
        case .appearance: Text("Apariencia")
        case .playback: Text("Reproducción")
        case .alerts: Text("Avisos")
        case .downloads: Text("Descargas")
        case .accounts: Text("Cuentas")
        case .addons: Text("Complementos")   // edición: la página solo existe con `settingsEntries.addons`
        case .oneDrive: Text(verbatim: "OneDrive")
        case .orbital: Text("Tu Orbital")
        case .voice: Text("Voz y Siri")
        case .advanced: Text("Avanzado")
        case .learn: Text("Aprende")
        }
    }
}

/// MA2 (Fernando, 17 nov 2026: «dale una pulida a esas pantallas que no son tan comunes»): en la Mac, lo que se abre desde
/// una página de Ajustes (Trakt, Real-Debrid, Letterboxd, un complemento…) se queda a la derecha, con su nombre arriba y «‹»
/// para volver. Antes se empujaba a toda la ventana: una columna angosta sola en la pantalla, sin la lista. Lo pone
/// `SettingsView` solo en la Mac; sin él, `PaneLink` es un `NavigationLink` de siempre.
struct SettingsSubPane {
    let push: (Text, @escaping () -> AnyView) -> Void
}

/// Una página abierta a la derecha en la Mac (MA2): se arma en cada pasada, con los valores al día.
struct SettingsSubPage: Identifiable {
    let id = UUID()
    let title: Text
    let make: () -> AnyView
}

extension EnvironmentValues {
    @Entry var settingsPane: SettingsPane?
    @Entry var settingsSubPane: SettingsSubPane?
}

/// Un enlace dentro de una página de Ajustes: en iPhone y iPad la empuja; en la Mac la abre a la derecha, junto a la lista (MA2).
/// No va dentro de una hoja: la hoja hereda el entorno y abriría la página detrás.
struct PaneLink<Destination: View, Label: View>: View {
    let title: Text
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label
    @Environment(\.settingsSubPane) private var pane

    init(_ title: Text, @ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.title = title; self.destination = destination; self.label = label
    }

    var body: some View {
        if let pane {
            Button { pane.push(title) { AnyView(destination()) } } label: {
                HStack(spacing: DS.Space.s2) {
                    label()
                    Spacer(minLength: DS.Space.s2)
                    Image(systemName: "chevron.right").font(DS.TextRecipe.label.font).foregroundStyle(DS.textFaint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(destination: destination, label: label)
        }
    }
}

/// El nombre de la página abierta a la derecha en la Mac, con «‹» si vino de otra (MA2), como Ajustes del Sistema.
struct SettingsPaneHeader: View {
    let title: Text
    let back: (() -> Void)?
    @Environment(\.readableWidth) private var width   // alineado con la página de abajo (AJ-A)

    var body: some View {
        HStack(spacing: DS.Space.s2) {
            if let back {
                Button(action: back) { Image(systemName: "chevron.left").font(DS.TextRecipe.labelLarge.font) }
                    .buttonStyle(.plain).foregroundStyle(DS.text)
                    .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .macPillBase(Circle())
                    .accessibilityLabel(Text("Volver"))
                    .keyboardShortcut("[", modifiers: .command)
            }
            title.recipe(.section, color: DS.text).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: width, alignment: .leading)
        .padding(.horizontal, DS.Space.gutter)
        .padding(.top, DS.Space.s4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Un renglón de Ajustes que lleva a otra página: en iPhone y iPad la empuja; en la Mac la abre a la derecha, marcado.
struct SettingsLink<Destination: View, Label: View>: View {
    let page: SettingsPage
    @ViewBuilder let destination: () -> Destination
    @ViewBuilder let label: () -> Label
    @Environment(\.settingsPane) private var pane

    init(_ page: SettingsPage, @ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.page = page; self.destination = destination; self.label = label
    }

    var body: some View {
        if let pane {
            let on = pane.current == page
            // El renglón abierto, marcado hasta las orillas de su grupo (el fondo de la sección gana a `listRowBackground`).
            Button { pane.open(page) } label: {
                label().contentShape(Rectangle())
                    .background { if on { DS.surfaceRaised.padding(.horizontal, -DS.Space.s6).padding(.vertical, -DS.Space.s2) } }
            }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
        } else {
            NavigationLink(destination: destination, label: label)
        }
    }
}

/// Un ajuste de pocas opciones a la vista (Español / English): su nombre y lo que cambia a la izquierda, el selector a la
/// derecha, en un solo renglón como `DSToggleRow`. Si no cabe (iPhone angosto, letra grande), el selector baja a lo ancho.
/// Antes el selector iba solo en su tarjeta con el nombre arriba y la explicación abajo, sueltos: en la pantalla ancha de la
/// Mac se veía medio renglón vacío y no se sabía de qué grupo era cada texto (Fernando, 23 nov 2026: «una pulida con ojo
/// experto»).
struct SettingsChoiceRow<ID: Hashable>: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?
    let options: [DSSelector<ID>.Option]
    @Binding var selection: ID

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.s4) {
                label
                Spacer(minLength: DS.Space.s2)
                DSSelector(options: options, selection: $selection, adapts: false).fixedSize()
            }
            VStack(alignment: .leading, spacing: DS.Space.s2) {
                label
                DSSelector(options: options, selection: $selection)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 0) {   // como `DSToggleRow`
            Text(title).foregroundStyle(DS.text)
            if let detail { Text(detail).recipe(.footnote, color: DS.textMuted) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
