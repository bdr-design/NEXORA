#if STAGE_C
import Foundation
import ProbePlatform

enum StageCWALKind: UInt8 { case advance = 1, rescheduleAll = 2 }

final class StageCWAL {
    let epoch: UInt32
    let path: String
    private var handle: FileHandle?
    private(set) var sequence: UInt64 = 0
    private(set) var discardedTailPath: String? = nil

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

    private init(epoch: UInt32, path: String, handle: FileHandle, sequence: UInt64,
                 discardedTailPath: String?) {
        self.epoch = epoch
        self.path = path
        self.handle = handle
        self.sequence = sequence
        self.discardedTailPath = discardedTailPath
    }

    private static func retainTail(_ bytes: Data, directory: String, epoch: UInt32,
                                   validBytes: Int, tailBytes: Int) throws -> String {
        guard tailBytes > 0 && tailBytes <= 71, validBytes >= 16,
              validBytes <= bytes.count && tailBytes == bytes.count - validBytes else {
            throw ProbeError.corruption("stage C WAL torn-tail bounds")
        }
        let tail = Data(bytes.suffix(tailBytes))
        let digest = Snapshot.digestData(tail).map { String(format: "%02x", $0) }.joined()
        let archive = directory + "/wal-\(epoch).discarded-\(validBytes)-\(digest).tail"
        if FileManager.default.fileExists(atPath: archive) {
            guard try Data(contentsOf: URL(fileURLWithPath: archive)) == tail else {
                throw ProbeError.corruption("stage C WAL discarded-tail archive changed")
            }
        } else {
            let pending = archive + ".pending-" + UUID().uuidString
            let archiveHandle = try exclusiveHandle(pending)
            do {
                try archiveHandle.write(contentsOf: tail)
                try archiveHandle.synchronize()
                try archiveHandle.close()
            } catch {
                try? archiveHandle.close()
                throw error
            }
            guard nx_replace_file(pending, archive) == 0 else {
                throw ProbeError.invalid("stage C WAL discarded-tail archive rename")
            }
        }
        guard nx_sync_dir(directory) == 0 else {
            throw ProbeError.invalid("stage C WAL discarded-tail directory sync")
        }
        guard try Data(contentsOf: URL(fileURLWithPath: archive)) == tail else {
            throw ProbeError.corruption("stage C WAL discarded-tail archive verification")
        }
        return archive
    }

    // A recovered world and this WAL prefix describe one state. Recheck the
    // bytes before changing the file so corruption between recovery and resume
    // cannot silently turn a torn tail into valid history. The caller owns the
    // directory exclusively throughout recovery and append.
    static func resume(directory: String, epoch: UInt32,
                       replay: StageCWALReplayResult) throws -> StageCWAL {
        guard epoch > 0, replay.validBytes >= 16, replay.ignoredTailBytes >= 0 else {
            throw ProbeError.invalid("stage C WAL resume metadata")
        }
        let path = directory + "/wal-\(epoch).log"
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        guard replay.validBytes <= bytes.count,
              replay.ignoredTailBytes == bytes.count - replay.validBytes,
              Snapshot.digestData(bytes) == replay.fileDigest else {
            throw ProbeError.corruption("stage C WAL changed after recovery")
        }
        let discardedTailPath: String?
        if replay.ignoredTailBytes > 0 {
            discardedTailPath = try retainTail(bytes, directory: directory, epoch: epoch,
                                               validBytes: replay.validBytes,
                                               tailBytes: replay.ignoredTailBytes)
        } else {
            discardedTailPath = nil
        }
        let h = try FileHandle(forUpdating: URL(fileURLWithPath: path))
        do {
            if replay.ignoredTailBytes > 0 {
                try h.truncate(atOffset: UInt64(replay.validBytes))
                try h.synchronize()
                guard nx_sync_dir(directory) == 0 else {
                    throw ProbeError.invalid("stage C WAL truncation directory sync")
                }
            }
            try h.seek(toOffset: UInt64(replay.validBytes))
            return StageCWAL(epoch: epoch, path: path, handle: h, sequence: replay.commands,
                             discardedTailPath: discardedTailPath)
        } catch {
            try? h.close()
            throw error
        }
    }

    private func append(kind: StageCWALKind, payload: Data) throws {
        guard let handle else { throw ProbeError.invalid("stage C WAL closed") }
        let next = sequence.addingReportingOverflow(1)
        guard !next.overflow else { throw ProbeError.invalid("stage C WAL sequence overflow") }
        var body = Data(capacity: 16 + payload.count)
        Snapshot.appendLE(UInt32(16 + payload.count + 32), into: &body)
        body.append(kind.rawValue); body.append(0); body.append(0); body.append(0)
        Snapshot.appendLE(next.partialValue, into: &body)
        body.append(payload)
        let digest = Snapshot.digestData(body)
        var frame = body; frame.append(digest)
        let split = max(1, frame.count / 2)
        do {
            try handle.write(contentsOf: frame.prefix(split))
            nx_kill_point("c.k9.mid_wal_record")
            try handle.write(contentsOf: frame.suffix(frame.count - split))
            sequence = next.partialValue
        } catch {
            // The last frame may be partial. Recovery must verify and remove
            // that tail before any writer resumes this epoch.
            try? handle.close()
            self.handle = nil
            throw error
        }
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
            self.handle = nil
            try handle.close()
        }
    }

    func synchronize() throws {
        guard let handle else { throw ProbeError.invalid("stage C WAL closed") }
        do { try handle.synchronize() }
        catch {
            try? handle.close()
            self.handle = nil
            throw error
        }
    }

    deinit { try? handle?.close() }
}

struct StageCWALReplayResult {
    let commands: UInt64
    let ignoredTailBytes: Int
    let validBytes: Int
    let fileDigest: Data
}

enum StageCWALReplay {
    static func replay(path: String, on world: SwiftWorld) throws -> StageCWALReplayResult {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProbeError.corruption("stage C missing WAL")
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
        let fileDigest = Snapshot.digestBytes(bytes, range: 0..<bytes.count)
        while position + 4 <= bytes.count {
            var lr = StageCByteReader(bytes: Array(bytes[position..<(position + 4)]))
            let length = Int(try lr.u32())
            guard length == 64 || length == 72 else {
                throw ProbeError.corruption("stage C WAL canonical length")
            }
            let available = bytes.count - position
            if available >= 5 {
                let kind = bytes[position + 4]
                guard (kind == StageCWALKind.advance.rawValue && length == 72) ||
                      (kind == StageCWALKind.rescheduleAll.rawValue && length == 64) else {
                    throw ProbeError.corruption("stage C WAL partial kind/length")
                }
            }
            if available > 5 {
                for offset in 5..<min(available, 8) where bytes[position + offset] != 0 {
                    throw ProbeError.corruption("stage C WAL partial reserved")
                }
            }
            if available >= 16 {
                var sr = StageCByteReader(bytes: Array(bytes[(position + 8)..<(position + 16)]))
                guard try sr.u64() == expectedSequence else {
                    throw ProbeError.corruption("stage C WAL partial sequence")
                }
            }
            if position + length > bytes.count {
                return StageCWALReplayResult(commands: expectedSequence - 1,
                    ignoredTailBytes: bytes.count - position,
                    validBytes: position, fileDigest: fileDigest)
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
            guard length == (kind == .advance ? 72 : 64) else {
                throw ProbeError.corruption("stage C WAL canonical frame length")
            }
            let sequence = try r.u64()
            guard sequence == expectedSequence else { throw ProbeError.corruption("stage C WAL sequence") }
            switch kind {
            case .advance:
                let target = try r.u64(), budget = Int(try r.u32()), units = Int(try r.u32())
                let expectedEvents = Int(try r.u32())
                guard try r.u32() == 0 else { throw ProbeError.corruption("stage C WAL advance reserved") }
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
            ignoredTailBytes: bytes.count - position,
            validBytes: position, fileDigest: fileDigest)
    }
    static func replay(path: String, on world: HybridWorld) throws -> StageCWALReplayResult {
        guard FileManager.default.fileExists(atPath: path) else {
            throw ProbeError.corruption("stage C hybrid missing WAL")
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
        let fileDigest = Snapshot.digestBytes(bytes, range: 0..<bytes.count)
        while position + 4 <= bytes.count {
            var lr = StageCByteReader(bytes: Array(bytes[position..<(position + 4)]))
            let length = Int(try lr.u32())
            guard length == 64 || length == 72 else {
                throw ProbeError.corruption("stage C hybrid WAL canonical length")
            }
            let available = bytes.count - position
            if available >= 5 {
                let kind = bytes[position + 4]
                guard (kind == StageCWALKind.advance.rawValue && length == 72) ||
                      (kind == StageCWALKind.rescheduleAll.rawValue && length == 64) else {
                    throw ProbeError.corruption("stage C hybrid WAL partial kind/length")
                }
            }
            if available > 5 {
                for offset in 5..<min(available, 8) where bytes[position + offset] != 0 {
                    throw ProbeError.corruption("stage C hybrid WAL partial reserved")
                }
            }
            if available >= 16 {
                var sr = StageCByteReader(bytes: Array(bytes[(position + 8)..<(position + 16)]))
                guard try sr.u64() == expectedSequence else {
                    throw ProbeError.corruption("stage C hybrid WAL partial sequence")
                }
            }
            if position + length > bytes.count {
                return StageCWALReplayResult(commands: expectedSequence - 1,
                    ignoredTailBytes: bytes.count - position,
                    validBytes: position, fileDigest: fileDigest)
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
            guard length == (kind == .advance ? 72 : 64) else {
                throw ProbeError.corruption("stage C hybrid WAL canonical frame length")
            }
            let sequence = try r.u64()
            guard sequence == expectedSequence else { throw ProbeError.corruption("stage C hybrid WAL sequence") }
            switch kind {
            case .advance:
                let target = try r.u64(), budget = Int(try r.u32()), units = Int(try r.u32())
                let expectedEvents = Int(try r.u32())
                guard try r.u32() == 0 else { throw ProbeError.corruption("stage C hybrid WAL advance reserved") }
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
            ignoredTailBytes: bytes.count - position,
            validBytes: position, fileDigest: fileDigest)
    }

}
#endif
