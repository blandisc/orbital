import Foundation
import OrbitalCore

/// Cuándo una versión «falló» y qué se prueba después. Lo que ya suena no se cambia solo por otra versión salvo que de verdad
/// falle (Fernando, 12 nov: el video ya sonaba y un segundo después salía «Probando otra versión… Sigue en el mismo punto» y
/// volvía a cargar el mismo archivo desde 0). Cada marca queda en la bitácora con su motivo, para diagnosticar la próxima vez.
extension PlayerModel {
    /// Una duración corta de una versión que ya está en Real-Debrid se cree solo si no cambia en este tiempo: al abrir, el motor
    /// dice un momento lo que lleva leído (8 s, 16 s…) antes que lo que dura el episodio, y eso se tomaba por el aviso de
    /// «descargando» de Real-Debrid.
    static let placeholderConfirmSeconds: TimeInterval = 4

    /// La única forma de dar una versión por fallida: se anota en la bitácora con el motivo (`RetryOnlyWhenItFailsTests` lo vigila).
    func markFailed(_ failed: Source?, _ why: String) {
        guard let failed else { return }
        markFailed(index: failed.index, why, release: failed.release)
    }

    func markFailed(index: Int, _ why: String, release: String? = nil) {
        guard failedSources.insert(index).inserted else { return }
        let name = release ?? sourceChoices.first { $0.index == index }?.release ?? "#\(index)"
        Self.note("versión fallida (\(stripURLs(why).prefix(100))): \(name.prefix(100))")
    }

    /// El archivo de una versión, si el complemento lo dice (`behaviorHints.filename`): el mismo archivo en otro torrent es la
    /// misma versión.
    static func fileName(_ source: Source) -> String? {
        source.stream["behaviorHints"]?["filename"]?.string.map { $0.lowercased() }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Lo que un reintento no prueba: lo que falló y lo mismo con otro enlace (el mismo archivo o el mismo enlace). Así «otra
    /// versión» nunca vuelve a cargar la que se acaba de dejar, desde 0.
    var retrySkip: Set<Int> {
        guard !failedSources.isEmpty else { return [] }
        var failed = sourceChoices.filter { failedSources.contains($0.index) }
        if let source, failedSources.contains(source.index), !failed.contains(where: { $0.index == source.index }) { failed.append(source) }
        let names = Set(failed.compactMap(Self.fileName)), links = Set(failed.compactMap(\.playbackURL))
        let same = sourceChoices.filter { choice in Self.fileName(choice).map(names.contains) == true || choice.playbackURL.map(links.contains) == true }
        return failedSources.union(same.map(\.index))
    }

    /// El aviso corto de Real-Debrid de verdad. Si Real-Debrid tenía que bajarla (no está al instante), su aviso es lo esperado y
    /// se cree en cuanto se ve; si ya está en Real-Debrid, la duración corta tiene que mantenerse `placeholderConfirmSeconds` (o
    /// terminar ahí): una lectura que crece, o que el video ya rebasó, es del motor abriendo el archivo, no un aviso.
    func confirmedPlaceholder(_ s: EngineSnapshot) -> Bool {
        guard isPlaceholder(s), s.position <= s.duration + 1 else {
            if rd.shortDuration != nil { rd.shortDuration = nil }
            return false
        }
        if s.state == .ended || source?.instant != true { return true }
        let now = clock()
        guard let seen = rd.shortDuration, abs(seen.seconds - s.duration) < 1 else {
            Self.note(String(format: "duración corta: %.0f s en %.0f s (se espera a ver si se mantiene)", s.duration, s.position))
            rd.shortDuration = (s.duration, now)
            return false
        }
        return now.timeIntervalSince(seen.since) >= Self.placeholderConfirmSeconds
    }
}
