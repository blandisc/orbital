import Foundation

/// Las pistas de un MKV leídas de su encabezado, sin reproducirlo (Fernando, 12 nov: «me tengo que meter a checar cada uno
/// porque solamente reconoce el idioma inglés»). Un MKV dice sus pistas al principio (`Tracks`, dentro de `Segment`); si no
/// cabe en lo leído, su índice (`SeekHead`) dice dónde está y se lee solo ese pedazo.
public enum MatroskaTracks {
    /// Lo que se sacó de un pedazo del archivo: las pistas de audio, o dónde están (desde el principio del archivo).
    public enum Found: Equatable, Sendable {
        case tracks([MediaTrack])
        case elsewhere(Int64)
        /// No es un MKV, o lo leído no alcanza ni dice dónde buscar.
        case unknown
    }

    static let ebml: UInt32 = 0x1A45DFA3, segment: UInt32 = 0x18538067, seekHead: UInt32 = 0x114D9B74, seek: UInt32 = 0x4DBB
    static let seekID: UInt32 = 0x53AB, seekPosition: UInt32 = 0x53AC, tracksID: UInt32 = 0x1654AE6B, cluster: UInt32 = 0x1F43B675
    static let trackEntry: UInt32 = 0xAE, trackType: UInt32 = 0x83, language: UInt32 = 0x22B59C, languageBCP47: UInt32 = 0x22B59D
    static let name: UInt32 = 0x536E, codec: UInt32 = 0x86, flagDefault: UInt32 = 0x88, flagForced: UInt32 = 0x55AA, trackNumber: UInt32 = 0xD7

    /// Lee el principio del archivo (`data` empieza en el byte 0).
    public static func read(head data: Data) -> Found {
        var r = Reader(Array(data))
        guard r.id() == ebml, let size = r.size(), r.skip(size) else { return .unknown }
        guard r.id() == segment, r.size() != nil else { return .unknown }
        let segmentStart = Int64(r.at)
        var tracksAt: Int64?
        while !r.atEnd {
            let start = r.at
            guard let id = r.id(), let size = r.size() else { break }
            if id == tracksID { return r.fits(size) ? .tracks(tracks(r.slice(size))) : .elsewhere(Int64(start)) }
            if id == cluster { break }   // ya son los cuadros del video: las pistas iban antes o en otra parte
            if id == seekHead, r.fits(size), let position = tracksPosition(r.slice(size)) { tracksAt = segmentStart + position }
            guard r.skip(size) else { break }
        }
        return tracksAt.map(Found.elsewhere) ?? .unknown
    }

    /// Lee el pedazo que empieza justo en `Tracks` (lo que dijo `elsewhere`).
    public static func read(tracksAt data: Data) -> [MediaTrack]? {
        var r = Reader(Array(data))
        guard r.id() == tracksID, let size = r.size(), r.fits(size) else { return nil }
        return tracks(r.slice(size))
    }

    private static func tracksPosition(_ bytes: [UInt8]) -> Int64? {
        var r = Reader(bytes)
        while !r.atEnd {
            guard let id = r.id(), let size = r.size(), r.fits(size) else { return nil }
            guard id == seek else { _ = r.skip(size); continue }
            var entry = Reader(r.slice(size)); _ = r.skip(size)
            var target: UInt32?, position: UInt64?
            while !entry.atEnd {
                guard let child = entry.id(), let length = entry.size(), entry.fits(length) else { break }
                let value = entry.slice(length); _ = entry.skip(length)
                if child == seekID { target = value.reduce(0) { $0 << 8 | UInt32($1) } }
                if child == seekPosition { position = value.reduce(0) { $0 << 8 | UInt64($1) } }
            }
            if target == tracksID, let position, position < UInt64(Int64.max) { return Int64(position) }
        }
        return nil
    }

    /// Las pistas de audio de `Tracks`: su idioma (el BCP 47 si lo trae; si no dice, inglés, como dice la norma) y su nombre.
    static func tracks(_ bytes: [UInt8]) -> [MediaTrack] {
        var r = Reader(bytes), out: [MediaTrack] = []
        while !r.atEnd {
            guard let id = r.id(), let size = r.size(), r.fits(size) else { break }
            guard id == trackEntry else { _ = r.skip(size); continue }
            var entry = Reader(r.slice(size)); _ = r.skip(size)
            var type: UInt64 = 0, number = out.count + 1, lang: String?, bcp47: String?, title: String?, codecID: String?
            var isDefault = true, forced = false
            while !entry.atEnd {
                guard let child = entry.id(), let length = entry.size(), entry.fits(length) else { break }
                let value = entry.slice(length); _ = entry.skip(length)
                let number64 = value.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                let text = String(decoding: value.prefix { $0 != 0 }, as: UTF8.self)
                switch child {
                case trackType: type = number64
                case trackNumber: number = Int(clamping: number64)
                case language: lang = text
                case languageBCP47: bcp47 = text
                case name: title = text
                case codec: codecID = text
                case flagDefault: isDefault = number64 != 0
                case flagForced: forced = number64 != 0
                default: break
                }
            }
            guard type == 2 else { continue }   // 2 = audio
            out.append(MediaTrack(id: number, kind: .audio, language: bcp47 ?? lang ?? "eng", title: title, codec: codecID,
                                  isDefault: isDefault, isForced: forced))
        }
        return out
    }

    /// Un encabezado de MKV de muestra (un video y estas pistas de audio), para la demostración y las pruebas. `seekOnly`: las
    /// pistas van después de un relleno y el principio solo dice dónde están (como algunos archivos grandes).
    public static func sampleHeader(audio: [(language: String, name: String?)], seekOnly: Bool = false, padding: Int = 0) -> Data {
        func idBytes(_ id: UInt32) -> [UInt8] { withUnsafeBytes(of: id.bigEndian, Array.init).drop { $0 == 0 }.map { $0 } }
        func element(_ id: UInt32, _ payload: [UInt8]) -> [UInt8] {
            var size = [UInt8](repeating: 0, count: 8); size[0] = 0x01
            for i in 0..<7 { size[7 - i] = UInt8((payload.count >> (8 * i)) & 0xFF) }
            return idBytes(id) + size + payload
        }
        func uint(_ id: UInt32, _ value: UInt8) -> [UInt8] { element(id, [value]) }
        func text(_ id: UInt32, _ value: String) -> [UInt8] { element(id, Array(value.utf8)) }
        var entries = element(trackEntry, uint(trackNumber, 1) + uint(trackType, 1) + text(codec, "V_MPEG4/ISO/AVC"))
        for (i, track) in audio.enumerated() {
            entries += element(trackEntry, uint(trackNumber, UInt8(i + 2)) + uint(trackType, 2) + text(language, track.language)
                               + (track.name.map { text(name, $0) } ?? []) + text(codec, "A_EAC3"))
        }
        let tracksElement = element(tracksID, entries)
        let header = element(ebml, text(0x4282, "matroska"))
        guard seekOnly else { return Data(header + [0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] + tracksElement) }
        // SeekHead (mide 4 + 8 + seek) y luego un relleno (Void, 0xEC) antes de las pistas.
        let seekPayload: (Int) -> [UInt8] = { position in
            element(seek, element(seekID, idBytes(tracksID)) + element(seekPosition, (0..<8).reversed().map { UInt8((position >> (8 * $0)) & 0xFF) }))
        }
        let seekHeadLength = element(seekHead, seekPayload(0)).count
        let void = element(0xEC, [UInt8](repeating: 0, count: padding))
        let body = element(seekHead, seekPayload(seekHeadLength + void.count)) + void + tracksElement
        return Data(header + [0x18, 0x53, 0x80, 0x67, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF] + body)
    }

    /// EBML: números de largo variable (el primer bit encendido dice cuántos bytes miden).
    struct Reader {
        let bytes: [UInt8]
        var at = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }
        var atEnd: Bool { at >= bytes.count }

        /// El número de un elemento (con su marca, como lo escribe la norma: 0x1A45DFA3).
        mutating func id() -> UInt32? {
            guard at < bytes.count else { return nil }
            let first = bytes[at], length = first.leadingZeroBitCount + 1
            guard length <= 4, at + length <= bytes.count else { return nil }
            let value = bytes[at..<at + length].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            at += length
            return value
        }

        /// El tamaño de un elemento; «desconocido» (todo en unos) cuenta como hasta el final.
        mutating func size() -> UInt64? {
            guard at < bytes.count else { return nil }
            let first = bytes[at], length = first.leadingZeroBitCount + 1
            guard length <= 8, at + length <= bytes.count else { return nil }
            var value = UInt64(first & (0xFF >> length))
            var allOnes = value == UInt64(0xFF >> length)
            for byte in bytes[at + 1..<at + length] { value = value << 8 | UInt64(byte); allOnes = allOnes && byte == 0xFF }
            at += length
            return allOnes ? UInt64.max : value
        }

        func fits(_ size: UInt64) -> Bool { size != UInt64.max && size <= UInt64(bytes.count - at) }
        func slice(_ size: UInt64) -> [UInt8] { Array(bytes[at..<at + Int(size)]) }
        /// Salta el elemento; false si se sale de lo leído (o mide «desconocido»).
        mutating func skip(_ size: UInt64) -> Bool {
            guard fits(size) else { return false }
            at += Int(size)
            return true
        }
    }
}
