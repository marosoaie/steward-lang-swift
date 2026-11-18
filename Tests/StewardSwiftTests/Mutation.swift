/// SplitMix64: a small, seedable generator, so a failing mutation names a
/// seed that reproduces it.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE5_E9B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Edits to a source's bytes, of the kinds that break Swift's structure.
enum Mutation {
    /// Fragments that open or close a construct, end a line, or aren't
    /// UTF-8.
    static let fragments: [[UInt8]] = [
        "{", "}", "(", ")", "[", "]", "<", ">", "\"", "\"\"\"", "#", "\\(", "/*", "*/", "//", "\n", "\r",
        "`", "@", ":", ",", "->", "func ", "#if X\n", "#endif\n", "#\"", "\"#", "/", "'",
    ].map { Array($0.utf8) } + [[0], [0xFF], [0xC3], [0xE2, 0x82]]

    /// `bytes` after `count` random edits: a byte replaced, a fragment
    /// inserted, a span deleted or a span repeated.
    static func apply(count: Int, to bytes: [UInt8], using generator: inout SeededGenerator) -> [UInt8] {
        (0..<count).reduce(into: bytes) { bytes, _ in
            let position = bytes.isEmpty ? 0 : Int.random(in: 0..<bytes.count, using: &generator)
            let length = Swift.min(Int.random(in: 1...64, using: &generator), bytes.count - position)
            switch Int.random(in: 0..<4, using: &generator) {
            case 0 where !bytes.isEmpty:
                bytes[position] = UInt8.random(in: 0...255, using: &generator)
            case 1:
                bytes.insert(contentsOf: fragments.randomElement(using: &generator) ?? [], at: position)
            case 2 where length > 0:
                bytes.removeSubrange(position..<position + length)
            case 3 where length > 0:
                bytes.insert(contentsOf: bytes[position..<position + length], at: position)
            default:
                bytes.append(contentsOf: fragments.randomElement(using: &generator) ?? [])
            }
        }
    }
}
