import Foundation
import OrbitalCore
import OrbitalAddons
import os

/// La bitácora del reproductor en el registro del sistema (Consola de la Mac con el iPhone conectado, categoría «player»): qué
/// se abrió, qué versión, cuándo sonó y por qué falló. Sin enlaces ni claves: solo ids de IMDb, el servidor y el motivo.
extension PlayerModel {
    nonisolated static let log = Logger(subsystem: "mx.iracheta.orbital", category: "player")

    /// La misma bitácora en un archivo de la app (`player-log.txt`, las últimas `logKeep` líneas), para leerla desde la Mac con
    /// `devicectl` cuando algo no carga en el iPhone (el registro del sistema pide la clave de administrador).
    nonisolated static let logFile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Orbital", isDirectory: true).appendingPathComponent("player-log.txt")
    nonisolated static let logKeep = 400
    /// El archivo se escribe en su propia fila, fuera del hilo principal: leerlo y reescribirlo entero (unos 40 KB) en cada línea
    /// detenía la pantalla justo al cambiar de versión, de pista o de episodio, que es cuando más se anota (23 nov 2026).
    nonisolated private static let logQueue = DispatchQueue(label: "mx.iracheta.orbital.player-log", qos: .utility)

    nonisolated public static func note(_ text: String) {
        log.notice("\(text, privacy: .public)")
        guard NSClassFromString("XCTestCase") == nil else { return }   // las pruebas no escriben en la Mac
        let line = ISODates.string(Date()) + " " + text
        logQueue.async {
            let old = (try? String(contentsOf: logFile, encoding: .utf8))?.split(separator: "\n").map(String.init) ?? []
            let kept = (old + [line]).suffix(logKeep).joined(separator: "\n") + "\n"
            try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? kept.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }
}
