import Foundation

public enum StableHash {
    /// Deterministic FNV-1a 64-bit hash. This is an idempotency checksum, not a security primitive.
    public static func hex(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
