import SwiftUI
import OrbitalCore
import OrbitalModels

/// MA1 (Fernando, 16 nov 2026): en la Mac, Ajustes es lista y detalle, como Ajustes del Sistema. La lista a la izquierda y la
/// página elegida a la derecha: cambias varias cosas sin ir y volver (antes, una columna angosta al centro con dos tercios
/// vacíos). Lo que se abre desde una página (Probar la velocidad, Lo que recuerda cada título…) se empuja como siempre.
/// AJ-A (22 nov 2026): la lista es una barra lateral angosta (un renglón por página, sin su valor) y la página llena lo
/// demás; igual en el iPad ancho (donde la barra de arriba también va en el renglón del logo). iPhone e iPad angosto, la lista.
extension SettingsView {
    @ViewBuilder func macSplit(_ list: some View, _ model: SettingsModel) -> some View {
        if TopRow.tabsInLogoRow {
            HStack(spacing: 0) {
                list
                    .frame(width: DS.Mac.settingsListWidth)
                    // PU3-A (26 nov 2026): la lista deja el margen de la app como las demás pantallas (iba pegada a la orilla).
                    .padding(.leading, DS.Space.gutter)
                    .environment(\.settingsPane, SettingsPane(current: macPage, open: { macPage = $0; macStack = [] }))
                    .overlay(alignment: .trailing) { Rectangle().fill(DS.hairline).frame(width: DS.Stroke.hairline) }
                // MA2: su nombre arriba y, si vino de otra página, «‹» para volver; lo que abre se queda aquí (`PaneLink`).
                VStack(spacing: 0) {
                    SettingsPaneHeader(title: macStack.last?.title ?? macPage.title,
                                       back: macStack.isEmpty ? nil : { macStack.removeLast() })
                    Group {
                        if let top = macStack.last {
                            top.make().id(top.id)
                        } else {
                            destination(macPage, model).id(macPage)   // cada página empieza arriba y con su propio estado
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .listSectionSpacing(DS.Mac.settingsSectionGap)   // cada grupo con su aire: su explicación no se pega al siguiente
                }
                .environment(\.settingsSubPane, SettingsSubPane { title, make in macStack.append(SettingsSubPage(title: title, make: make)) })
                .environment(\.readableWidth, DS.Mac.settingsPageWidth)   // AJ-A: la página llena el ancho, no una columna de 720
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .macSettingsType()
            .background(Backdrop())
            .dsFeedback(.selection, trigger: macPage)
            .dsFeedback(.selection, trigger: macStack.count)
        } else {
            list
        }
    }
}

private extension View {
    /// Solo en la Mac: en el iPad ancho manda el tamaño de letra que eligió la persona.
    @ViewBuilder func macSettingsType() -> some View {
        if ThisDevice.isMac { font(DS.styled(DS.Mac.settingsBody)).dynamicTypeSize(DS.Mac.settingsType) } else { self }   // ds-exception: Ajustes en la Mac, un paso arriba
    }
}
