import Foundation
import OrbitalCore

/// Ajustes › «Usar con tu Orbital» (maquetas en https://claude.ai/artifact/FwxKwFe1Y19tTu6LLv3Vhw): primero se conecta con la
/// consola (el código de la TV, escaneado dentro de la app, o a mano) y luego un mini tutorial. Hasta conectar, el interruptor
/// sigue apagado: «Ahora no» deja la app como estaba.
@MainActor
public final class OrbitalSetupModel: ObservableModel {
    public enum Stage: Equatable, Sendable { case connect, connected, tutorial(Int) }
    /// Las páginas del tutorial: Ver en la TV, el control, y la voz con lo demás.
    public static let tutorialPages = 3

    public private(set) var stage: Stage { didSet { changed() } }
    /// Conectando (después de leer el código o de tocar «Conectar»).
    public private(set) var connecting = false { didSet { changed() } }
    /// Por qué no se conectó, en palabras («Ese código no es de Orbital», lo que dijo la consola); nil si no hay problema.
    public private(set) var problem: String? { didSet { changed() } }
    private let services: Services

    /// `tutorialOnly`: «Qué puedes hacer con la TV», ya conectada: directo al tutorial.
    public init(_ services: Services, tutorialOnly: Bool = false) {
        self.services = services
        stage = tutorialOnly ? .tutorial(1) : .connect
        super.init()
    }

    /// A dónde quedó conectada («orbital.casa»).
    public var host: String { services.orbital.base?.host ?? "" }

    /// Lo que leyó la cámara: el código de la TV es un enlace `orbital-ios://pair?u=…&t=…`.
    public func scanned(_ payload: String) async {
        guard !connecting else { return }
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)), let pair = OrbitalRemote.pairing(url) else {
            problem = "Ese código no es de Orbital. En la TV abre Ajustes › Cuentas › iPhone."
            return
        }
        await connect(address: pair.address, token: pair.token)
    }

    /// «Conectar a mano»: la dirección y el token (el mismo de Alexa).
    public func connectByHand(address: String, token: String) async {
        let address = address.trimmingCharacters(in: .whitespaces), token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !token.isEmpty else { problem = "Escribe la dirección y el token."; return }
        await connect(address: address, token: token)
    }

    private func connect(address: String, token: String) async {
        connecting = true; problem = nil
        defer { connecting = false }
        do {
            try await services.connectOrbital(address: address, token: token)
            stage = .connected
        } catch {
            // No contestó o no aceptó el token: se queda apagada, como estaba.
            services.turnOffOrbital()
            problem = (error as? OrbitalRemote.Failure)?.description ?? "Tu Orbital no contestó."
        }
    }

    /// «Ver qué puedes hacer» y «Siguiente» en el tutorial; nil cuando ya terminó.
    @discardableResult
    public func advance() -> Stage? {
        switch stage {
        case .connect: return stage
        case .connected: stage = .tutorial(1)
        case .tutorial(let page) where page < Self.tutorialPages: stage = .tutorial(page + 1)
        case .tutorial: return nil
        }
        return stage
    }
}
