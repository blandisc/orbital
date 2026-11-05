import Foundation

extension OrbitalRemote {
    /// «Continuar» en cualquier aparato: manda con qué fuente, audio y subtítulos se vio cada video aquí y trae lo que tu
    /// Orbital recuerda de `want` (lo de la TV o de otro aparato), con su hora. nil: tu Orbital es de antes.
    public func syncResume(_ changes: [String: ResumeChoice], want: [String]) async throws -> [String: ResumeChoice]? {
        var body: [String: JSON] = [:]
        for (id, c) in changes {
            var fields: [String: JSON] = ["video_id": .string(c.videoID), "at": .double(c.at ?? 0)]
            if let v = c.source { fields["source"] = .string(v) }
            if let v = c.audio { fields["audio"] = v.json }
            if let v = c.subtitle { fields["subtitle"] = v.json }
            body[id] = .object(fields)
        }
        let json: JSON?
        do {
            json = try await send("api/companion/resume", method: "POST", body: JSON.object(["changes": .object(body), "want": .array(want.map { .string($0) })]).serialized(),
                                  timeout: 6)
        } catch Failure.refused(let why) where why.contains("versión anterior") { return nil }
        guard let found = json?["resume"]?.object else { return nil }
        var out: [String: ResumeChoice] = [:]
        for (id, raw) in found {
            guard let videoID = raw["video_id"]?.nonEmptyString else { continue }
            out[id] = ResumeChoice(videoID: videoID, source: raw["source"]?.nonEmptyString, audio: ResumeChoice.Track.parse(raw["audio"]),
                                   subtitle: ResumeChoice.Track.parse(raw["subtitle"]), at: raw["at"]?.doubleValue)
        }
        return out
    }
}
