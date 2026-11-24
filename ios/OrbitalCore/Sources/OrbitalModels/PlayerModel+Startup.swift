import Foundation
import OrbitalCore
import os

/// Cuánto tarda cada tramo del arranque, de tocar «Ver» al primer cuadro (23 nov 2026: «que se sienta casi instantáneo»).
/// Sale una línea en la bitácora del reproductor al sonar, sin enlaces ni claves:
/// «arranque: buscar 0.02 · elegir 0.01 · enlace 0.19 · abrir 2.50 · primer cuadro 0.60 · total 3.32 s (ya resuelta)».
/// - buscar: las versiones (de la caché si la ficha ya las pidió).
/// - elegir: cuál suena (lo que pediste, «Continuar», la familia de la serie).
/// - enlace: «dónde ibas», lo de otros aparatos y la dirección final del complemento (`StreamLinks`), a la par.
/// - abrir: el motor abre el archivo (conexión, primeros bytes, revisión del archivo).
/// - primer cuadro: de abierto a que suena.
public struct StartupStages: Sendable, Equatable {
    public enum Stage: String, Sendable, CaseIterable { case found = "buscar", chosen = "elegir", link = "enlace", opened = "abrir", playing = "primer cuadro" }
    public private(set) var began: Date?
    public private(set) var marks: [Stage: Date] = [:]
    /// Cómo se llegó a la dirección que se abrió (`StreamLinks.Outcome`).
    public var link: String?
    /// Versiones que no abrieron antes de la que sonó.
    public var retries = 0

    public init(at began: Date? = nil) { self.began = began }

    /// La primera vez que se llega a cada tramo (un reintento no la mueve: su tiempo cae en el siguiente tramo).
    public mutating func mark(_ stage: Stage, at date: Date) {
        guard began != nil, marks[stage] == nil else { return }
        marks[stage] = date
    }

    /// La línea de la bitácora, cuando ya sonó; nil antes (o si no empezó con «Ver»: un cambio de versión, volver a la app).
    public func summary() -> String? {
        guard let began, let end = marks[.playing] else { return nil }
        var last = began, parts: [String] = []
        for stage in Stage.allCases {
            guard let at = marks[stage] else { continue }
            parts.append("\(stage.rawValue) " + String(format: "%.2f", max(0, at.timeIntervalSince(last))))
            last = max(last, at)
        }
        let extra = [link, retries > 0 ? "\(retries) sin abrir" : nil].compactMap { $0 }
        return "arranque: " + parts.joined(separator: " · ") + " · total " + String(format: "%.2f", end.timeIntervalSince(began)) + " s"
            + (extra.isEmpty ? "" : " (" + extra.joined(separator: ", ") + ")")
    }
}

extension PlayerModel {
    /// Las marcas del arranque también como eventos de Instruments (los «signposts» de la categoría «player»).
    nonisolated static let signposts = OSSignposter(subsystem: "mx.iracheta.orbital", category: "player")

    func markStartup(_ stage: StartupStages.Stage) {
        guard startup.began != nil else { return }
        startup.mark(stage, at: clock())
        Self.signposts.emitEvent("arranque", "\(stage.rawValue, privacy: .public)")
        guard stage == .playing else { return }
        startup.retries = failedSources.count
        if let line = startup.summary() { Self.note(line) }
        startup = StartupStages()   // una vez por «Ver»: lo que siga (cambios de versión, volver a la app) no es el arranque
    }

    /// Ya se eligió la versión: su dirección final se empieza a resolver a la par de «dónde ibas» (`StreamLinks`). Solo las que
    /// arrancan al instante: la redirección de una que la nube aún baja es su video de aviso, y ese no se guarda.
    func chose(_ found: Source) {
        markStartup(.chosen)
        guard found.instant, let url = found.playbackURL else { return }
        links.start(url)
    }

    /// La dirección que se abre: la final si ya se resolvió (o va en camino), si no la del complemento.
    func openable(_ url: URL) async -> URL {
        guard url.isFileURL == false, source?.instant == true, source?.playbackURL == url else { return url }
        let (target, how) = await links.playable(url)
        if startup.began != nil { startup.link = how.rawValue }
        return target
    }
}

extension Double {
    /// Redondeo a décimas (los pasos de la sincronía no acumulan 0.30000000000000004).
    func rounded(toPlaces places: Int) -> Double { let f = pow(10, Double(places)); return (self * f).rounded() / f }
}
