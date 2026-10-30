import Foundation

/// Por qué no se llega a tu Orbital, para decirlo claro en vez de «no contesta»: el iPhone sin internet, el túnel caído (la
/// dirección no responde), la consola apagada detrás del túnel o un token que ya no sirve.
public enum ConnectionIssue: Sendable, Equatable {
    case noInternet, tunnelDown, orbitalDown, tokenChanged
}

extension OrbitalRemote {
    /// Lo que contestó tu Orbital a una orden de voz: si la hizo y qué decir en voz alta («Poniendo The Office…»).
    public struct VoiceReply: Sendable, Equatable {
        public var ok: Bool
        public var speech: String
        /// Lo que se entendió («pon The Office», ya limpio), para enseñarlo bajo la respuesta. Vacío si la consola no lo manda.
        public var heard: String
        /// Varias con el mismo nombre (Dune de 1984 y de 2021): se enseñan para tocar la que es.
        public var choices: [VoiceChoice]
        /// Con «pon Dune» la consola ya puso una de `choices` (su `meta_id`); las demás quedan para cambiarla. Sin él
        /// («busca Dune»), `choices` es una lista para elegir.
        public var picked: String?
        /// «¿Qué puedo decir?»: abrir la guía de voz en el iPhone.
        public var guide: Bool
        /// Tres frases para lo que se ve ahora en la TV (las sugerencias bajo el micrófono).
        public var hints: [String]
        public init(ok: Bool, speech: String, heard: String = "", choices: [VoiceChoice] = [], picked: String? = nil, guide: Bool = false,
                    hints: [String] = []) {
            self.ok = ok; self.speech = speech; self.heard = heard; self.choices = choices
            self.picked = picked; self.guide = guide; self.hints = hints
        }
    }

    /// Una de las opciones que manda la consola cuando no sabe cuál: `kind` es movie o series.
    public struct VoiceChoice: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var subtitle: String
        public var kind: String
        public var metaID: String
        public var image: String?
        public init(id: String, title: String, subtitle: String, kind: String, metaID: String, image: String? = nil) {
            self.id = id; self.title = title; self.subtitle = subtitle; self.kind = kind; self.metaID = metaID; self.image = image
        }

        init?(_ json: JSON) {
            guard let title = json["title"]?.string, let metaID = json["meta_id"]?.string, !metaID.isEmpty else { return nil }
            self.init(id: json["id"]?.string ?? metaID, title: title, subtitle: json["subtitle"]?.string ?? "",
                      kind: json["kind"]?.string ?? "movie", metaID: metaID, image: json["image"]?.string)
        }
    }

    /// Una orden en texto libre, como a Alexa («pon The Office temporada 2», «pausa», «abre Zelda»): la consola la entiende
    /// con la misma lógica (`voice.py`). Sirve para Siri y para el micrófono de la app.
    public func voice(_ text: String) async throws -> VoiceReply {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        let json = try await send("api/voice", method: "POST", body: JSON.object(["text": .string(trimmed), "source": "iphone"]).serialized(), timeout: 20)   // no cuenta como «Alexa se usó»
        let choices = (json?["choices"]?.array ?? []).compactMap(VoiceChoice.init)
        return VoiceReply(ok: json?["ok"]?.bool ?? true, speech: json?["speech"]?.string ?? "", heard: json?["heard"]?.string ?? "",
                          choices: choices, picked: json?["picked"]?.nonEmptyString, guide: json?["guide"]?.bool ?? false,
                          hints: Self.phrases(json?["hints"]))
    }

    /// Las frases del momento: `moment` es series, movie, live o home.
    public struct VoiceHints: Sendable, Equatable {
        public var moment: String
        public var hints: [String]
        public init(moment: String, hints: [String]) { self.moment = moment; self.hints = hints }
    }

    /// Qué se puede decir ahora según lo que se ve en la TV. Una consola vieja no tiene la ruta: `Failure.outdated`.
    public func voiceHints() async throws -> VoiceHints {
        let json = try await send("api/voice/hints", method: "GET", body: nil, timeout: 5)
        return VoiceHints(moment: json?["moment"]?.string ?? "home", hints: Self.phrases(json?["hints"]))
    }

    static func phrases(_ json: JSON?) -> [String] {
        (json?.array ?? []).compactMap { $0.string?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Por qué no se llega a tu Orbital (nil: sí se llega, o no está conectada). Un `api/ping` con el token (sin él contaría
    /// como intento fallido) y 4 s de plazo: un 502/503/504 lo da el túnel cuando la consola detrás no contesta; un 530 o no
    /// conectar (DNS, TLS, tiempo agotado), el túnel mismo.
    public func diagnose() async -> ConnectionIssue? {
        guard let request = try? request("api/ping", method: "GET", body: nil, timeout: Self.diagnoseTimeout) else { return nil }
        do {
            let response = try await http.send(request)
            switch response.status {
            case 200..<300: return nil
            case 401, 403: return .tokenChanged
            case 530: return .tunnelDown   // Cloudflare: el túnel no está conectado
            default: return .orbitalDown   // 502/503/504 y cualquier otro error: algo contestó, pero no tu Orbital
            }
        } catch {
            if Task.isCancelled { return nil }
            return Self.issue(for: error)
        }
    }

    public static let diagnoseTimeout: TimeInterval = 4

    /// Un fallo de red: sin internet en el iPhone, o todo lo demás (no conecta, DNS, TLS, tiempo agotado) es el túnel.
    static func issue(for error: Error) -> ConnectionIssue {
        let code = (error as? URLError)?.code ?? (error as? NetworkError)?.code
        return code == .notConnectedToInternet || code == .dataNotAllowed ? .noInternet : .tunnelDown
    }
}
