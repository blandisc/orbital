import Foundation
import os

/// La bitácora de la app por tema (se lee en Consola filtrando por `mx.iracheta.orbital`). Va en las cargas y guardados que
/// antes se tragaban el error con `try?`: un archivo dañado o una caché que no se pudo escribir ya dejan rastro (auditoría,
/// 31 oct 2026).
public enum Log {
    static let subsystem = "mx.iracheta.orbital"
    /// Lo tuyo en disco: biblioteca del teléfono y trabajo pendiente.
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    /// Las cachés (lo último que se vio, en Caches).
    public static let cache = Logger(subsystem: subsystem, category: "cache")
    /// Lo que se pide a la red y no se pudo armar (una dirección inválida).
    public static let network = Logger(subsystem: subsystem, category: "network")
}
