import SwiftUI
import UIKit
import OrbitalCore

/// La ficha de la Mac (FI-B) en su propia capa: encima de la pantalla, pero fuera de ella. Antes era un `overlay` de la raíz
/// y abrirla o cerrarla volvía a acomodar y pintar todo lo de atrás (las pestañas que se quedan armadas): 450–550 ms con la
/// pantalla congelada al abrir otra película y ~200 ms al cerrar, igual con la ficha vacía. En su capa, la pantalla de atrás
/// no se entera: ~100 ms al abrir y casi nada al cerrar (medido con Instruments el 24 nov 2026, docs/ios-interfaz.md).
/// Una por ventana (`RootView`); `SideTitle` le dice en qué ventana vive, qué entorno hereda y cuándo cerrarse.
@MainActor @Observable final class MacTitleHost {
    /// Lo que la ficha hereda de la pantalla (la app, el idioma, los atajos de los pósters), uno por uno (`SideTitle`).
    /// Todo el entorno de golpe (`\.self`) no: se llevaba algo que escondía la ficha a VoiceOver y a la accesibilidad.
    @ObservationIgnored var inherit: (AnyView) -> AnyView = { $0 }
    @ObservationIgnored var reduceMotion = false
    /// Hasta dónde llega el renglón de pestañas (en la ventana): ahí los clics pasan, para cambiar de pestaña en un solo clic.
    @ObservationIgnored var stripBottom: CGFloat = 0 { didSet { layer?.stripBottom = stripBottom } }
    @ObservationIgnored private weak var root: UIViewController?
    @ObservationIgnored private var layer: TitleLayer?
    @ObservationIgnored private var host: TitleHostController?

    /// ¿Hay una ficha a la vista? Lo único que se observa: con ella abierta, lo de atrás se esconde a VoiceOver.
    private(set) var isOpen = false

    func attach(_ window: UIWindow?) {
        if let root = window?.rootViewController { self.root = root }
    }

    /// Abre la ficha (o la cambia, si ya hay una abierta).
    func show(_ route: TitleRoute) {
        guard let root else { return }
        let layer = layer ?? makeLayer(in: root)
        host?.rootView = panel(route)
        guard !layer.isOpen else { return }
        isOpen = true
        layer.bringToFront()
        layer.present(animated: !reduceMotion)
        host?.becomeFirstResponder()   // Esc la cierra aunque el último clic haya sido atrás
    }

    func hide() {
        guard isOpen else { return }
        isOpen = false
        layer?.dismiss(animated: !reduceMotion) { [weak self] in
            // Ya escondida, se vacía: lo que la ficha tenía corriendo (cargas, avisos) se detiene, como antes al cerrarla.
            self?.host?.rootView = AnyView(EmptyView())
        }
    }

    private func panel(_ route: TitleRoute) -> AnyView {
        inherit(AnyView(TitlePanel(route: route, close: { [weak self] in self?.hide() })
            .background(DS.backdropDeep.ignoresSafeArea())))
    }

    private func makeLayer(in root: UIViewController) -> TitleLayer {
        let host = TitleHostController(rootView: AnyView(EmptyView()))
        host.onEscape = { [weak self] in self?.hide() }
        let layer = TitleLayer(panel: host.view)
        layer.frame = root.view.bounds
        layer.stripBottom = stripBottom
        layer.onClose = { [weak self] in self?.hide() }
        root.addChild(host)
        layer.install(in: root.view)
        host.didMove(toParent: root)
        self.layer = layer
        self.host = host
        return layer
    }
}

/// La ficha en su controlador: con Esc se cierra.
private final class TitleHostController: UIHostingController<AnyView> {
    var onEscape: (() -> Void)?
    override var canBecomeFirstResponder: Bool { true }
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escape))]
    }
    @objc private func escape() { onEscape?() }
}

/// La pantalla oscurecida y, encima, la ficha a la derecha (cerca de 40 % de la ventana, como
/// `DS.TitleAction.sidePanelWidth`). Las dos van sueltas en la vista de la raíz (así VoiceOver y la accesibilidad de la Mac
/// ven la ficha). Tocar lo oscuro la cierra; el renglón de pestañas deja pasar el clic.
private final class TitleLayer: UIView {
    var onClose: (() -> Void)?
    var stripBottom: CGFloat = 0
    private(set) var isOpen = false
    private let panel: UIView

    init(panel: UIView) {
        self.panel = panel
        super.init(frame: .zero)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        isHidden = true
        backgroundColor = UIColor(DS.scrim)
        accessibilityElementsHidden = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapOutside)))
        let shadow = DS.Elevation.medium
        panel.backgroundColor = .clear
        panel.isHidden = true
        panel.layer.shadowColor = UIColor(shadow.color).cgColor
        panel.layer.shadowOpacity = 1
        panel.layer.shadowRadius = shadow.radius
        panel.layer.shadowOffset = CGSize(width: 0, height: shadow.y)
    }

    required init?(coder: NSCoder) { nil }

    func install(in parent: UIView) {
        frame = parent.bounds
        parent.addSubview(self)
        parent.addSubview(panel)
    }

    func bringToFront() {
        superview?.bringSubviewToFront(self)
        superview?.bringSubviewToFront(panel)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let t = DS.TitleAction.self
        let width = min(max(bounds.width * t.sidePanelShare, t.sidePanelMin), t.sidePanelMax)
        panel.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        panel.center = CGPoint(x: frame.maxX - width / 2, y: frame.midY)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        isOpen && point.y >= stripBottom
    }

    @objc private func tapOutside() { onClose?() }

    func present(animated: Bool) {
        isOpen = true
        isHidden = false
        panel.isHidden = false
        setNeedsLayout()
        layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: panel)   // VoiceOver pasa a la ficha
        guard animated else { alpha = 1; panel.transform = .identity; return }
        alpha = 0
        panel.transform = CGAffineTransform(translationX: panel.bounds.width, y: 0)
        UIView.animate(withDuration: DesignTokens.Motion.slow, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = 1
            self.panel.transform = .identity
        }
    }

    func dismiss(animated: Bool, then done: @escaping () -> Void) {
        guard isOpen else { return }
        isOpen = false
        let finish = { [weak self] in
            guard let self, !self.isOpen else { return }   // se volvió a abrir mientras salía
            self.isHidden = true
            self.panel.isHidden = true
            UIAccessibility.post(notification: .screenChanged, argument: nil)
            done()
        }
        guard animated else { finish(); return }
        UIView.animate(withDuration: DesignTokens.Motion.base, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.alpha = 0
            self.panel.transform = CGAffineTransform(translationX: self.panel.bounds.width, y: 0)
        } completion: { _ in finish() }
    }
}
