// CPR1 wire format for IMU batches (must match backend/app/ingest.py).
// Header (little-endian): magic u32 "CPR1", seq u32, count u16, reserved u16 = 12 bytes.
// Row: ts f64 + 9 × f32 (userAcceleration xyz [g], gravity xyz [g], rotationRate xyz [rad/s]) = 44 bytes.
import Foundation

nonisolated struct CPRPacketEncoder {
    static let magic: UInt32 = 0x4350_5231
    static let headerBytes = 12
    static let rowBytes = 44

    private(set) var count = 0
    private var rows = Data()

    mutating func append(ts: Double, values: [Float32]) {
        precondition(values.count == 9, "a row has exactly 9 Float32 values")
        rows.appendLE(ts.bitPattern)
        for v in values { rows.appendLE(v.bitPattern) }
        count += 1
    }

    /// Returns the finished packet and clears the batch.
    mutating func flush(seq: UInt32) -> Data {
        var p = Data(capacity: Self.headerBytes + rows.count)
        p.appendLE(Self.magic)
        p.appendLE(seq)
        p.appendLE(UInt16(count))
        p.appendLE(UInt16(0))
        p.append(rows)
        rows.removeAll(keepingCapacity: true)
        count = 0
        return p
    }

    mutating func reset() {
        rows.removeAll(keepingCapacity: true)
        count = 0
    }
}

extension Data {
    nonisolated mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
