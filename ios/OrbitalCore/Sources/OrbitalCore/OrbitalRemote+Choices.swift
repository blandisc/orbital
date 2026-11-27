import Foundation

/// Lo que elegiste para cada título (audio, español, subtítulos) y cómo se sincroniza con tu Orbital. Salió de
/// `OrbitalRemote.swift` (27 nov 2026) para que no pasara de su tope de líneas (`FileBudgetTests`).
extension OrbitalRemote {
    /// Lo que se eligió para un título (audio, «es-419» / «es-ES», subtítulos) y su revisión en tu Orbital.
    public struct TitleChoice: Sendable, Equatable, Codable {
        public var audio: String?
        public var spanish: String?
        public var subtitles: String?
        public var rev: Int
        public init(audio: String? = nil, spanish: String? = nil, subtitles: String? = nil, rev: Int = 0) {
            self.audio = audio; self.spanish = spanish; self.subtitles = subtitles; self.rev = rev
        }
    }

    /// Lo que eligió el iPhone y aún no sabe tu Orbital: solo los campos que cambiaron, lo que hay que olvidar y la
    /// última revisión de ese título que vio el iPhone (si la TV lo cambió después, gana la TV).
    public struct ChoiceChange: Sendable, Equatable, Codable {
        public var audio: String?
        public var spanish: String?
        public var subtitles: String?
        public var forget: [String]
        public var base: Int
        public init(audio: String? = nil, spanish: String? = nil, subtitles: String? = nil, forget: [String] = [], base: Int = 0) {
            self.audio = audio; self.spanish = spanish; self.subtitles = subtitles; self.forget = forget; self.base = base
        }
    }

    public struct ChoicesReply: Sendable, Equatable {
        public var rev: Int
        public var changed: [String: TitleChoice]
        public var rejected: [String]
    }

    /// Manda lo que cambió aquí y trae lo que cambió en la TV desde `since`. nil: tu Orbital es de antes (no sincroniza).
    public func syncChoices(since: Int, changes: [String: ChoiceChange]) async throws -> ChoicesReply? {
        var body: [String: JSON] = [:]
        for (id, c) in changes {
            var fields: [String: JSON] = ["base_rev": .int(c.base)]
            if let v = c.audio { fields["audio"] = .string(v) }
            if let v = c.spanish { fields["spanish"] = .string(v) }
            if let v = c.subtitles { fields["subtitles"] = .string(v) }
            if !c.forget.isEmpty { fields["forget"] = .array(c.forget.map { .string($0) }) }
            body[id] = .object(fields)
        }
        let json: JSON?
        do { json = try await send("api/companion/choices", method: "POST", body: JSON.object(["since": .int(since), "changes": .object(body)]).serialized()) }
        catch Failure.refused(let why) where Self.isUpdateLine(why) { return nil }
        guard let json, let rev = json["rev"]?.intValue else { return nil }
        var changed: [String: TitleChoice] = [:]
        for (id, raw) in json["changed"]?.object ?? [:] {
            changed[id] = TitleChoice(audio: raw["audio"]?.string, spanish: raw["spanish"]?.string, subtitles: raw["subtitles"]?.string,
                                      rev: raw["rev"]?.intValue ?? 0)
        }
        return ChoicesReply(rev: rev, changed: changed, rejected: (json["rejected"]?.array ?? []).compactMap(\.string))
    }
}
