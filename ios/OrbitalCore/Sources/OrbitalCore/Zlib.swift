import Foundation

/// zlib en Swift puro (sin depender de `Compression` ni de libz): igual en iOS y en Linux, y se prueba
/// contra lo que genera Python. El bitfield de «visto» de Stremio es un flujo zlib pequeño.
public enum Zlib {
    public enum Failure: Error { case truncated, badHeader, badBlock, badChecksum, badCode }

    // MARK: Adler-32
    public static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a &+ UInt32(byte)) % 65521
            b = (b &+ a) % 65521
        }
        return (b << 16) | a
    }

    // MARK: compresión (bloques sin comprimir: válido para cualquier lector zlib; los datos son diminutos)
    public static func compressStored(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var index = 0
        repeat {
            let count = min(65535, data.count - index)
            let final: UInt8 = index + count >= data.count ? 1 : 0
            out.append(final)
            out.append(UInt8(count & 0xff)); out.append(UInt8(count >> 8))
            out.append(UInt8(~count & 0xff)); out.append(UInt8((~count >> 8) & 0xff))
            out.append(contentsOf: data[index..<index + count])
            index += count
        } while index < data.count
        let sum = adler32(data)
        out.append(contentsOf: [UInt8(sum >> 24), UInt8((sum >> 16) & 0xff), UInt8((sum >> 8) & 0xff), UInt8(sum & 0xff)])
        return out
    }

    // MARK: descompresión
    public static func decompress(_ input: [UInt8]) throws -> [UInt8] {
        guard input.count >= 6 else { throw Failure.truncated }
        let cmf = Int(input[0]), flg = Int(input[1])
        guard cmf & 0x0f == 8, (cmf << 8 | flg) % 31 == 0, flg & 0x20 == 0 else { throw Failure.badHeader }
        var reader = BitReader(bytes: input, position: 2)
        var out: [UInt8] = []
        var last = false
        while !last {
            last = try reader.bits(1) == 1
            switch try reader.bits(2) {
            case 0:
                reader.alignToByte()
                let len = try reader.bits(16), nlen = try reader.bits(16)
                guard len == (~nlen & 0xffff) else { throw Failure.badBlock }
                for _ in 0..<len { out.append(UInt8(try reader.bits(8))) }
            case 1:
                try inflate(&reader, &out, literals: .fixedLiterals, distances: .fixedDistances)
            case 2:
                let (lit, dist) = try readDynamicTables(&reader)
                try inflate(&reader, &out, literals: lit, distances: dist)
            default:
                throw Failure.badBlock
            }
        }
        reader.alignToByte()
        guard reader.position + 4 <= input.count else { throw Failure.truncated }
        let p = reader.position
        let expected = UInt32(input[p]) << 24 | UInt32(input[p + 1]) << 16 | UInt32(input[p + 2]) << 8 | UInt32(input[p + 3])
        guard expected == adler32(out) else { throw Failure.badChecksum }
        return out
    }

    private struct BitReader {
        let bytes: [UInt8]
        var position: Int
        var bit = 0
        mutating func bits(_ n: Int) throws -> Int {
            var value = 0
            for i in 0..<n {
                guard position < bytes.count else { throw Failure.truncated }
                value |= Int((bytes[position] >> UInt8(bit)) & 1) << i
                bit += 1
                if bit == 8 { bit = 0; position += 1 }
            }
            return value
        }
        mutating func alignToByte() { if bit != 0 { bit = 0; position += 1 } }
    }

    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []

        init(lengths: [Int]) {
            for l in lengths { counts[l] += 1 }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for i in 1..<16 { offsets[i] = offsets[i - 1] + counts[i - 1] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, l) in lengths.enumerated() where l != 0 {
                symbols[offsets[l]] = symbol
                offsets[l] += 1
            }
        }

        func decode(_ reader: inout BitReader) throws -> Int {
            var code = 0, first = 0, index = 0
            for length in 1..<16 {
                code |= try reader.bits(1)
                let count = counts[length]
                if code - count < first { return symbols[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw Failure.badCode
        }

        static let fixedLiterals: Huffman = {
            var lengths = [Int](repeating: 8, count: 288)
            for i in 144..<256 { lengths[i] = 9 }
            for i in 256..<280 { lengths[i] = 7 }
            return Huffman(lengths: lengths)
        }()
        static let fixedDistances = Huffman(lengths: [Int](repeating: 5, count: 30))
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static func inflate(_ r: inout BitReader, _ out: inout [UInt8], literals: Huffman, distances: Huffman) throws {
        while true {
            let symbol = try literals.decode(&r)
            if symbol < 256 { out.append(UInt8(symbol)); continue }
            if symbol == 256 { return }
            let s = symbol - 257
            guard s < 29 else { throw Failure.badCode }
            let length = lengthBase[s] + (try r.bits(lengthExtra[s]))
            let d = try distances.decode(&r)
            guard d < 30 else { throw Failure.badCode }
            let distance = distBase[d] + (try r.bits(distExtra[d]))
            guard distance <= out.count else { throw Failure.badCode }
            for _ in 0..<length { out.append(out[out.count - distance]) }
        }
    }

    private static func readDynamicTables(_ r: inout BitReader) throws -> (Huffman, Huffman) {
        let nlen = try r.bits(5) + 257, ndist = try r.bits(5) + 1, ncode = try r.bits(4) + 4
        guard nlen <= 286, ndist <= 30 else { throw Failure.badBlock }
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengths = [Int](repeating: 0, count: 19)
        for i in 0..<ncode { codeLengths[order[i]] = try r.bits(3) }
        let codeTable = Huffman(lengths: codeLengths)
        var lengths: [Int] = []
        while lengths.count < nlen + ndist {
            let symbol = try codeTable.decode(&r)
            if symbol < 16 { lengths.append(symbol); continue }
            var repeatValue = 0, count = 0
            switch symbol {
            case 16:
                guard let previous = lengths.last else { throw Failure.badBlock }
                repeatValue = previous; count = 3 + (try r.bits(2))
            case 17: count = 3 + (try r.bits(3))
            default: count = 11 + (try r.bits(7))
            }
            guard lengths.count + count <= nlen + ndist else { throw Failure.badBlock }
            lengths.append(contentsOf: [Int](repeating: repeatValue, count: count))
        }
        return (Huffman(lengths: Array(lengths[0..<nlen])), Huffman(lengths: Array(lengths[nlen...])))
    }
}
