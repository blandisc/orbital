import Foundation

/// Un JSON cualquiera. Los `libraryItem` de Stremio se conservan completos (solo se toca `state`),
/// así que no se modelan con campos fijos: lo que no conocemos se devuelve tal cual.
public enum JSON: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSON].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSON].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "JSON no válido") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public static func parse(_ data: Data) -> JSON? {
        // JSONSerialization (en C) y luego al enum: 5–10 veces más rápido que el `Codable` de arriba, que prueba seis tipos por valor.
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) { return JSON(foundation: object) }
        if let json = try? JSONDecoder().decode(JSON.self, from: data) { return json }
        // Un solo número fuera de rango («1e999») no debe tumbar toda la respuesta: se vuelve `null` y se lee lo demás.
        guard let text = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"(?<![\w"\\])-?\d+(?:\.\d+)?[eE][+-]?\d{3,}"#) else { return nil }
        let cleaned = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "null")
        return cleaned == text ? nil : try? JSONDecoder().decode(JSON.self, from: Data(cleaned.utf8))
    }

    public func serialized(sortedKeys: Bool = false) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = sortedKeys ? [.sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    // MARK: lectura tolerante (como los `isinstance` de la versión en Python)
    public subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var nonEmptyString: String? { if case .string(let s) = self, !s.isEmpty { return s }; return nil }
    public var array: [JSON]? { if case .array(let a) = self { return a }; return nil }
    public var object: [String: JSON]? { if case .object(let o) = self { return o }; return nil }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    /// Entero solo si es un número entero (no booleano ni texto).
    public var intValue: Int? {
        switch self {
        case .int(let i): return i
        case .double(let d): return d.isFinite && d == d.rounded() && abs(d) < 9e15 ? Int(d) : nil
        default: return nil
        }
    }
    /// Número (entero o decimal) como Double.
    public var doubleValue: Double? {
        switch self { case .int(let i): return Double(i); case .double(let d): return d.isFinite ? d : nil; default: return nil }
    }
    public var isNull: Bool { if case .null = self { return true }; return false }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
                ExpressibleByNilLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .int(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(nilLiteral: ()) { self = .null }
    public init(arrayLiteral elements: JSON...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSON)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
}

/// `as_int` de Python: un número de Stremio; 0 si viene raro.
public func asInt(_ value: JSON?) -> Int {
    guard let value else { return 0 }
    switch value {
    case .int(let i): return i
    case .double(let d): return d.isFinite && abs(d) < 9e15 ? Int(d) : 0
    case .bool(let b): return b ? 1 : 0
    case .string(let s): return Int(s) ?? 0
    default: return 0
    }
}

extension JSON {
    /// De lo que da `JSONSerialization` (NSDictionary, NSArray, NSNumber…) al enum. Un booleano es un `CFBoolean`; un número
    /// sin decimales (que quepa) es `.int`, como con el decodificador de siempre.
    init(foundation value: Any) {
        switch value {
        case let dict as [String: Any]: self = .object(dict.mapValues(JSON.init(foundation:)))
        case let array as [Any]: self = .array(array.map(JSON.init(foundation:)))
        case let string as String: self = .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { self = .bool(number.boolValue) }
            else if CFNumberIsFloatType(number) {
                let d = number.doubleValue
                self = d.isFinite && d == d.rounded() && abs(d) < 9e15 && !String(describing: number).contains(".") ? .int(Int(d)) : .double(d)
            } else if let i = Int(exactly: number.int64Value), number.int64Value != Int64.max || number.doubleValue == Double(Int64.max) { self = .int(i) }
            else { self = .double(number.doubleValue) }
        default: self = .null
        }
    }
}
