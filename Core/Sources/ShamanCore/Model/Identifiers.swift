import Foundation

/// Milliseconds since the Unix epoch, UTC. The only time representation stored
/// anywhere in this app. Local time is a presentation concern and is derived at
/// render time from the device calendar — it never enters the schema.
public typealias EpochMillis = Int64

extension Date {
    public var epochMillis: EpochMillis { EpochMillis((timeIntervalSince1970 * 1000).rounded()) }

    public init(epochMillis: EpochMillis) {
        self.init(timeIntervalSince1970: Double(epochMillis) / 1000)
    }
}

/// UUIDv7: 48-bit big-endian millisecond timestamp, then version/variant bits,
/// then randomness. Sorts lexicographically by creation time, which makes the
/// append-only event log naturally ordered and makes a future server-side merge
/// a sort rather than a reconciliation.
public enum UUIDv7 {
    public static func generate(at millis: EpochMillis = Date().epochMillis) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)

        let ts = UInt64(bitPattern: Int64(millis)) & 0x0000_FFFF_FFFF_FFFF
        bytes[0] = UInt8((ts >> 40) & 0xFF)
        bytes[1] = UInt8((ts >> 32) & 0xFF)
        bytes[2] = UInt8((ts >> 24) & 0xFF)
        bytes[3] = UInt8((ts >> 16) & 0xFF)
        bytes[4] = UInt8((ts >> 8) & 0xFF)
        bytes[5] = UInt8(ts & 0xFF)

        for i in 6..<16 { bytes[i] = UInt8.random(in: 0...255) }

        bytes[6] = (bytes[6] & 0x0F) | 0x70          // version 7
        bytes[8] = (bytes[8] & 0x3F) | 0x80          // variant 10

        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Recovers the embedded timestamp. Returns nil for any UUID that is not v7.
    public static func timestamp(of uuid: UUID) -> EpochMillis? {
        let b = uuid.uuid
        guard (b.6 & 0xF0) == 0x70 else { return nil }
        var ts: UInt64 = 0
        for byte in [b.0, b.1, b.2, b.3, b.4, b.5] { ts = (ts << 8) | UInt64(byte) }
        return EpochMillis(ts)
    }
}
