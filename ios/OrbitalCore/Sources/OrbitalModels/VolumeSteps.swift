import Foundation
import OrbitalCore

/// Qué hace cada toque del + y − del control (en pantalla o los botones del costado), en el mismo orden que ▲ ▼ del mando
/// (V5-B, Fernando, 4 nov 2026): pasado el 100 de Windows sube el Extra del reproductor y al bajar primero se quita el
/// Extra. Con freno: al llegar a 100 manteniendo el +, el iPhone vibra y se detiene; para entrar al Extra sueltas y vuelves
/// a tocar. Sin video no hay Extra: el + en 100 solo avisa (V6-A).
public struct VolumeSteps: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Se manda a la TV; `brake`: además llegó a 100 y se frena (vibra).
        case send, brake
        /// Sigues manteniendo el + frenado en 100: no se manda nada.
        case hold
        /// El + en 100 sin video: «El Extra es solo para videos».
        case onlyVideos
    }

    /// Dos toques más juntos que esto son el botón mantenido (la repetición de iOS va cada ~0,1 s). Antes 0,35 s: tocar rápido
    /// contaba como mantener y el freno del 100 no dejaba pasar (Fernando, 6 nov: «se traba cuando le das rápido»).
    public static let holdGap: TimeInterval = 0.15
    /// La repetición del botón mantenido: de aquí para abajo, pasos dobles.
    public static let repeatGap: TimeInterval = 0.15, repeatsBeforeFast = 3

    private var lastPress = Date.distantPast, braked = false

    public init() {}

    /// Un toque de `delta` (±5) sobre lo que se ve: qué hacer y cómo queda la barra al momento.
    public mutating func press(_ delta: Int, on volume: OrbitalRemote.Volume?, at now: Date = Date()) -> (Outcome, OrbitalRemote.Volume?) {
        let held = now.timeIntervalSince(lastPress) < Self.holdGap
        lastPress = now
        guard let v = volume else { return (.send, nil) }
        if delta < 0 { braked = false }
        if delta > 0, v.extraMax != nil, v.level >= 100, (v.extra ?? 100) <= 100 {
            guard v.extra != nil else { return (.onlyVideos, v) }
            if braked && held { return (.hold, v) }
            braked = false
        }
        let next = v.stepped(by: delta)
        if delta > 0, v.extra != nil, v.extraMax != nil, v.level < 100, next.level >= 100 {
            braked = true
            return (.brake, next)
        }
        return (.send, next)
    }
}

public extension OrbitalRemote.Volume {
    /// El volumen tras un toque, en el orden del mando: con un video, pasado el 100 el Extra; al bajar, primero el Extra.
    func stepped(by delta: Int) -> OrbitalRemote.Volume {
        if let extra, (delta > 0 && level >= 100) || (delta < 0 && extra > 100) {
            return .init(level: level, muted: false, extra: max(100, min(extraMax ?? 200, extra + delta)), extraMax: extraMax)
        }
        return .init(level: max(0, min(100, level + delta)), muted: delta > 0 ? false : muted, extra: extra, extraMax: extraMax)
    }
}
