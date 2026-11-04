import SwiftUI
import OrbitalCore
import OrbitalModels

// Piezas del reproductor: los botones con nombre, «Audio y subtítulos» (`SubtitleDock`) y sus partes.

/// Cuando el video no abre: cada caso con su pantalla y sus salidas.

/// Cuando el reproductor no puede: una pantalla propia (no un aviso rojo encima de los controles), con lo que pasó dicho
/// desde tu lado y solo las salidas que sirven en ese caso.
struct PlayerFailureView: View {
    let failure: PlayerModel.Failure
    /// Un episodio (no una película): para decir «este episodio».
    let isEpisode: Bool
    let retry: () -> Void
    let infuse: (() -> Void)?
    /// Hay otras versiones: elegir una ahí mismo (antes había que cerrar y volver a abrir).
    var chooseVersion: (() -> Void)? = nil
    /// ¿El iPhone tiene internet? Con red, «no pude pedir las fuentes» es que tus complementos no contestaron (antes decía
    /// «Sin conexión» igual).
    var online = true
    /// Sin internet, lo que sí se puede ver: tus descargas.
    var openDownloads: (() -> Void)? = nil
    /// Por qué, cuando se sabe (D5, R1, R7): «Tu Real-Debrid venció», «Real-Debrid no lo dejó bajar»… Su texto sale de
    /// `UnavailableCause` (la tabla común con la TV) y su única salida, de `action`.
    var cause: UnavailableCause? = nil
    /// «Renovar»: real-debrid.com en el navegador.
    var renew: (() -> Void)? = nil
    /// «Ajustes».
    var openSettings: (() -> Void)? = nil
    /// El idioma de la app (para los textos de la causa).
    var uiLanguage = "es"
    /// «Pedirlo y avisarme» (R7): Real-Debrid lo baja y avisa; nil si no se puede pedir (sin clave, sin Torrentio).
    var request: (() -> Void)? = nil
    let close: () -> Void
    /// «¿Qué es esto?» (O2), en las causas de Real-Debrid.
    @State private var explaining = false

    var body: some View {
        // En vertical, todo en una columna; en horizontal (poco alto) no cabían los tres botones bajo el texto y el último
        // quedaba cortado: ahí el texto va a la izquierda y las salidas a la derecha.
        GeometryReader { geo in
            // `ViewThatFits` daba por bueno el renglón vertical (el texto se puede comprimir) y los botones se cortaban abajo:
            // se decide por la forma de la pantalla.
            let wide = geo.size.width > geo.size.height
            Group {
                if wide { HStack(spacing: DS.Space.s8) { info; options } }
                else { VStack(spacing: DS.Space.s4) { info; options } }
            }
            .padding(DS.Space.gutter)
            .frame(width: geo.size.width, height: geo.size.height)
            // Si ni así cabe (letra muy grande), se desliza en vez de cortar el texto.
            .modifier(ScrollIfNeeded())
        }
        .background(DS.backdropDeep.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $explaining) { DebridExplainer() }
    }

    /// Las causas de Real-Debrid llevan «¿Qué es esto?» (O2): es donde surge la duda.
    private var aboutDebrid: Bool {
        switch cause {
        case .notInDebrid?, .nobodyHasIt?, .downloading?, .debridRefused?: true
        default: false
        }
    }

    /// El ícono y lo que pasó, dicho desde tu lado.
    private var info: some View {
        VStack(spacing: DS.Space.s4) {
            Image(systemName: symbol).font(DS.TextRecipe.display.font).foregroundStyle(DS.textMuted)
            VStack(spacing: DS.Space.s2) {
                title.recipe(.section).multilineTextAlignment(.center)
                message.recipe(.secondary, color: DS.textMuted).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: DS.Size.cardMax)
        }
    }

    /// Solo las salidas que sirven en ese caso.
    private var options: some View {
        VStack(spacing: DS.Space.s2) {
            if let cause {
                // Una sola salida, la de la causa; y cerrar.
                if let action = cause.action, let perform = perform(action) {
                    option(Text(verbatim: UnavailableCause.label(action, tr)), primary: true, action: perform)
                    option(Text("Cerrar"), primary: false, action: close)
                } else if case .downloading = cause, let request {
                    // Ya pedido: el mismo pedido (nunca otro) y el permiso de avisos, si falta.
                    option(Text("Avisarme cuando esté"), primary: true, action: request)
                    option(Text("Cerrar"), primary: false, action: close)
                } else {
                    option(Text("Cerrar"), primary: true, action: close)
                }
                if aboutDebrid {
                    Button { explaining = true } label: { Text("¿Qué es esto?").font(DS.TextRecipe.label.font).frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget) }
                        .buttonStyle(.borderless).tint(DS.accent)
                        .accessibilityIdentifier("player-debrid-explain")
                }
            } else {
            switch failure {
            case .noSources, .localFile:
                option(Text("Cerrar"), primary: true, action: close)
            case .network:
                option(Text("Reintentar"), primary: true, action: retry)
                if !online, let openDownloads { option(Text("Ver tus descargas"), primary: false, action: openDownloads) }
                option(Text("Cerrar"), primary: false, action: close)
            case .noneWorked, .sourceDied:
                option(Text("Reintentar"), primary: true, action: retry)
                if let chooseVersion { option(Text("Elegir otra versión"), primary: false, action: chooseVersion) }
                if let infuse { option(Text("Abrir en Infuse"), primary: false, action: infuse) }
                option(Text("Cerrar"), primary: false, action: close)
            }
            }
        }
        .frame(maxWidth: DS.Size.cardMax)
    }

    private func tr(_ key: String) -> String { Strings.tr(key, language: uiLanguage) }

    private func perform(_ action: UnavailableCause.Action) -> (() -> Void)? {
        switch action {
        case .renew: renew
        case .settings: openSettings
        case .retry: retry
        case .otherVersion: chooseVersion
        case .request: request
        }
    }

    private var symbol: String {
        switch cause {
        case .debridExpired?, .noPremium?, .reconnectDebrid?: return "person.crop.circle.badge.exclamationmark"
        case .debridRefused?: return "nosign"
        case .notInDebrid?, .downloading?: return "arrow.down.circle"
        case .nobodyHasIt?: return "magnifyingglass"
        default: break
        }
        return switch failure {
        case .noSources: "film.stack"
        case .noneWorked, .sourceDied: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .network: online ? "exclamationmark.icloud" : "wifi.slash"
        case .localFile: "externaldrive.badge.exclamationmark"
        }
    }

    private var title: Text {
        if let cause { return Text(verbatim: cause.title(tr)) }
        return switch failure {
        case .noSources: Text("Todavía no hay dónde verlo")
        case .noneWorked: Text("No pude reproducirlo")
        case .sourceDied: Text("Se cortó el video")
        case .network: online ? Text("Tus complementos no contestan") : Text("Sin conexión")
        case .localFile: Text("No se puede abrir la descarga")
        }
    }

    private var message: Text {
        if let cause, let detail = cause.detail(tr, languageName: { Streams.versionLanguageName($0, in: uiLanguage).lowercased() }) {
            return Text(verbatim: detail)
        }
        if cause != nil { return Text(verbatim: "") }
        return switch failure {
        case .noSources: isEpisode ? Text("Real-Debrid aún no tiene este episodio. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.")
            : Text("Real-Debrid aún no tiene esta película. Los estrenos suelen aparecer unas horas después; vuelve a intentarlo más tarde.")
        case .noneWorked: Text("Probamos las versiones que hay y ninguna respondió. A veces es momentáneo.")
        case .sourceDied: Text("La versión dejó de responder. Al reintentar seguimos donde ibas, con otra si hace falta.")
        case .network: online ? Text("Hay internet, pero ninguno respondió. Suele ser momentáneo; intenta de nuevo en un rato.")
            : Text("Revisa tu conexión a internet e intenta de nuevo. Lo que descargaste sí se puede ver.")
        case .localFile: Text("El archivo descargado no se puede leer. Bórralo en Descargas y bájalo otra vez.")
        }
    }

    private func option(_ label: Text, primary: Bool, action: @escaping () -> Void) -> some View {
        // El principal y el secundario de siempre, a tamaño de dedo (antes cápsulas pintadas a mano con el alto de una tecla
        // del control, D9 y D18).
        let button = Button(action: action) { label.font(DS.TextRecipe.labelLarge.font).frame(maxWidth: .infinity) }
        return Group {
            if primary { button.dsPrimaryButton(size: .large) } else { button.dsSecondaryButton().controlSize(.large) }
        }
    }
}
