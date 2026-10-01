#if STAGE_C
import Foundation
import ProbePlatform

enum StageCWALKind: UInt8 { case advance = 1, rescheduleAll = 2 }

final class StageCWAL {
    let epoch: UInt32
    let path: String
    private var handle: FileHandle?
    private(set) var sequence: UInt64 = 0

    init(directory: String, epoch: UInt32) throws {
        self.epoch = epoch
        self.path = directory + "/wal-\(epoch).log"
        let h = try exclusiveHandle(path)
        var prefix = Data("NXRWAL02".utf8)
        Snapshot.appendLE(UInt32(2), into: &prefix)
        Snapshot.appendLE(UInt32(1), into: &prefix)
        try h.write(contentsOf: prefix)
        try h.synchronize()
        self.handle = h
    }

    private func append(kind: StageCWALKind, payload: Data) throws {
        guard let handle else { throw ProbeError.invalid("stage C WAL closed") }
        sequence &+= 1
        guard sequence > 0 else { throw ProbeError.invalid("stage C WAL sequence overflow") }
        var body = Data(capacity: 16 + payload.count)
        Snapshot.appendLE(UInt32(16 + payload.count + 32), into: &body)
        body.append(kind.rawValue); body.append(0); body.append(0); body.append(0)
        Snapshot.appendLE(sequence, into: &body)
        body.append(payload)
        let digest = Snapshot.digestData(body)
        var frame = body; frame.append(digest)
        let split = max(1, frame.count / 2)
        try handle.write(contentsOf: frame.prefix(split))
        nx_kill_point("c.k9.mid_wal_record")
        try handle.write(contentsOf: frame.suffix(frame.count - split))
    }

    func appendAdvance(target: UInt64, budget: Int, units: Int, events: Int) throws {
        guard budget > 0, units >= 0, events >= 0,
              budget <= Int(UInt32.max), units <= Int(UInt32.max), events <= Int(UInt32.max) else {
            throw ProbeError.invalid("stage C WAL advance")
        }
        var payload = Data(capacity: 24)
        Snapshot.appendLE(target, into: &payload)
        Snapshot.appendLE(UInt32(budget), into: &payload)
        Snapshot.appendLE(UInt32(units), into: &payload)
        Snapshot.appendLE(UInt32(events), into: &payload)
        Snapshot.appendLE(UInt32(0), into: &payload)
        try append(kind: .advance, payload: payload)
    }

    func appendRescheduleAll(baseNow: UInt64, firstOperation: UInt64) throws {
        guard firstOperation > 0 else { throw ProbeError.invalid("stage C WAL reschedule") }
        var payload = Data(capacity: 16)
        Snapshot.appendLE(baseNow, into: &payload)
        Snapshot.appendLE(firstOperation, into: &payload)
        try append(kind: .rescheduleAll, payload: payload)
    }

    func close() throws {
        if let handle {
            try handle.close()
            self.handle = nil
        }
    }

    deinit { try? handle?.close() }
}

struct StageCWALReplayResult {
    let commands: UInt64
    let ignoredTailBytes: Int
}

enum StageCWALReplay {
    static func replay(path: String, on world: SwiftWorld) throws -> StageCWALReplayResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return StageCWALReplayResult(commands: 0, ignoredTailBytes: 0)
        }
        let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
        guard bytes.count >= 16, String(decoding: bytes[0..<8], as: UTF8.self) == "NXRWAL02" else {
            throw ProbeError.corruption("stage C WAL prefix")
        }
        var prefix = StageCByteReader(bytes: Array(bytes[8..<16]))
        guard try prefix.u32() == 2, try prefix.u32() == 1 else {
            throw ProbeError.corruption("stage C WAL version")
        }
        var position = 16
        var expectedSequence: UInt64 = 1
        while position + 4 <= bytes.count {
            var lr = StageCByteReader(bytes: Array(bytes[position..<(position + 4)]))
            let length = Int(try lr.u32())
            guard length >= 48 else { throw ProbeError.corruption("stage C WAL length") }
            if position + length > bytes.count {
                return StageCWALReplayResult(commands: expectedSequence - 1,
                    ignoredTailBytes: bytes.count - position)
            }
            let frame = Data(bytes[position..<(position + length)])
            let body = frame.prefix(length - 32)
            let digest = frame.suffix(32)
            guard Data(digest) == Snapshot.digestData(Data(body)) else {
                throw ProbeError.corruption("stage C WAL hash")
            }
            var r = StageCByteReader(bytes: Array(body))
            guard Int(try r.u32()) == length else { throw ProbeError.corruption("stage C WAL frame length") }
            let kindRaw = try r.u8()
            guard try r.u8() == 0, try r.u8() == 0, try r.u8() == 0,
                  let kind = StageCWALKind(rawValue: kindRaw) else {
                throw ProbeError.corruption("stage C WAL kind")
            }
            let sequence = try r.u64()
            guard sequence == expectedSequence else { throw ProbeError.corruption("stage C WAL sequence") }
            switch kind {
            case .advance:
                let target = try r.u64(), budget = Int(try r.u32()), units = Int(try r.u32())
                let expectedEvents = Int(try r.u32()); _ = try r.u32()
                if units > 0 {
                    let p = try world.advance(to: target, budget: budget, workBudget: units)
                    try require(p.events == expectedEvents && p.units == units,
                                "stage C replay advance state")
                } else {
                    try require(expectedEvents == 0, "stage C zero-unit advance events")
                }
            case .rescheduleAll:
                let baseNow = try r.u64(), firstOperation = try r.u64()
                try stageCRescheduleAll(world, baseNow: baseNow, firstOperation: firstOperation)
            }
            expectedSequence += 1
            position += length
        }
        return StageCWALReplayResult(commands: expectedSequence - 1,
            ignoredTailBytes: bytes.count - position)
    }
    static func replay(path: String, on world: HybridWorld) throws -> StageCWALReplayResult {
        guard FileManager.default.fileExists(atPath: path) else {
            return StageCWALReplayResult(commands: 0, ignoredTailBytes: 0)
        }
        let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
        guard bytes.count >= 16, String(decoding: bytes[0..<8], as: UTF8.self) == "NXRWAL02" else {
            throw ProbeError.corruption("stage C hybrid WAL prefix")
        }
        var prefix = StageCByteReader(bytes: Array(bytes[8..<16]))
        guard try prefix.u32() == 2, try prefix.u32() == 1 else {
            throw ProbeError.corruption("stage C hybrid WAL version")
        }
        var position = 16
        var expectedSequence: UInt64 = 1
        while position + 4 <= bytes.count {
            var lr = StageCByteReader(bytes: Array(bytes[position..<(position + 4)]))
            let length = Int(try lr.u32())
            guard length >= 48 else { throw ProbeError.corruption("stage C hybrid WAL length") }
            if position + length > bytes.count {
                return StageCWALReplayResult(commands: expectedSequence - 1,
                    ignoredTailBytes: bytes.count - position)
            }
            let frame = Data(bytes[position..<(position + length)])
            let body = frame.prefix(length - 32)
            let digest = frame.suffix(32)
            guard Data(digest) == Snapshot.digestData(Data(body)) else {
                throw ProbeError.corruption("stage C hybrid WAL hash")
            }
            var r = StageCByteReader(bytes: Array(body))
            guard Int(try r.u32()) == length else { throw ProbeError.corruption("stage C hybrid WAL frame length") }
            let kindRaw = try r.u8()
            guard try r.u8() == 0, try r.u8() == 0, try r.u8() == 0,
                  let kind = StageCWALKind(rawValue: kindRaw) else {
                throw ProbeError.corruption("stage C hybrid WAL kind")
            }
            let sequence = try r.u64()
            guard sequence == expectedSequence else { throw ProbeError.corruption("stage C hybrid WAL sequence") }
            switch kind {
            case .advance:
                let target = try r.u64(), budget = Int(try r.u32()), units = Int(try r.u32())
                let expectedEvents = Int(try r.u32()); _ = try r.u32()
                if units > 0 {
                    let p = try world.advance(to: target, budget: budget, workBudget: units)
                    try require(p.events == expectedEvents && p.units == units,
                                "stage C hybrid replay advance state")
                } else {
                    try require(expectedEvents == 0, "stage C hybrid zero-unit advance events")
                }
            case .rescheduleAll:
                let baseNow = try r.u64(), firstOperation = try r.u64()
                try stageCHybridRescheduleAll(world, baseNow: baseNow, firstOperation: firstOperation)
            }
            expectedSequence += 1
            position += length
        }
        return StageCWALReplayResult(commands: expectedSequence - 1,
            ignoredTailBytes: bytes.count - position)
    }

}
#endif
