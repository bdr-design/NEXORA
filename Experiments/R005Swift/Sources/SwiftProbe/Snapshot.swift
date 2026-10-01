#if STAGE_C
import Foundation
import ProbePlatform

struct StageCWheelControl {
    var cursor: UInt64
    var pending: Int
    var free: UInt32
    var cascade: Int
    var leaf: Int
    var sortPhase: Int
    var width: Int
    var merges: Int
    var seek: Int
    var leftCount: Int
    var rightCount: Int
    var pair: UInt32
    var left: UInt32
    var right: UInt32
    var outHead: UInt32
    var outTail: UInt32
    var heads: [UInt32]
    var tails: [UInt32]
    var sorted: [Bool]
    var occupied: [UInt64]
}

struct StageCWorldControl {
    var count: Int
    var eventCapacity: Int
    var groups: Int
    var now: UInt64
    var revenue: Int64
    var receivable: Int64
    var cash: Int64
    var processed: UInt64
    var sequenceHash: UInt64
    var rejectedStale: Int
    var changeEpoch: UInt32
    var wheel: StageCWheelControl
}

struct StageCRecordKey: Hashable, Comparable, Sendable {
    let kind: UInt16
    let index: UInt32
    static func < (lhs: StageCRecordKey, rhs: StageCRecordKey) -> Bool {
        lhs.kind != rhs.kind ? lhs.kind < rhs.kind : lhs.index < rhs.index
    }
}

enum Snapshot {
    static let prefix = Data("NXRSNAP2".utf8)
    static let footerMagic = Data("NXREND02".utf8)
    static let version: UInt32 = 2
    static let flags: UInt32 = 1

    static func appendLE<T: FixedWidthInteger>(_ value: T, into data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes in data.append(contentsOf: bytes) }
    }

    static func append<T: BitwiseCopyable>(_ column: ContiguousArray<T>, _ range: Range<Int>,
                                           into data: inout Data) {
        guard !range.isEmpty else { return }
        column.withUnsafeBufferPointer { pointer in
            let start = pointer.baseAddress!.advanced(by: range.lowerBound)
            let bytes = UnsafeRawBufferPointer(start: start,
                                               count: range.count * MemoryLayout<T>.stride)
            data.append(contentsOf: bytes)
        }
    }

    static func shaWords(_ data: Data) -> [UInt64] {
        let result: NXRHash = data.withUnsafeBytes { raw in
            let pointer = raw.bindMemory(to: UInt8.self).baseAddress
            return nx_hash_bytes(pointer, raw.count)
        }
        precondition(result.status == 0)
        return [result.a, result.b, result.c, result.d]
    }

    static func appendDigestWords(_ words: [UInt64], into data: inout Data) {
        precondition(words.count == 4)
        for word in words {
            for shift in stride(from: 56, through: 0, by: -8) {
                data.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
            }
        }
    }

    static func digestData(_ data: Data) -> Data {
        var out = Data(capacity: 32)
        appendDigestWords(shaWords(data), into: &out)
        return out
    }

    static func record(kind: UInt16, index: UInt32, elements: UInt32, payload: Data) -> Data {
        var data = Data(capacity: 16 + payload.count + 32)
        appendLE(kind, into: &data)
        appendLE(UInt16(0), into: &data)
        appendLE(index, into: &data)
        appendLE(elements, into: &data)
        appendLE(UInt32(payload.count), into: &data)
        data.append(payload)
        data.append(digestData(payload))
        return data
    }

    static func controlRecord(_ world: SwiftWorld) -> Data {
        var payload = Data(capacity: 20_000)
        world.stageCAppendControl(into: &payload)
        return record(kind: 0, index: 0, elements: 1, payload: payload)
    }

    static func assetRecord(_ world: SwiftWorld, chunk: Int) -> Data {
        let lo = chunk << 8
        let range = lo..<min(lo + 256, world.count)
        var payload = Data(capacity: range.count * 65)
        append(world.generations, range, into: &payload)
        append(world.airports, range, into: &payload)
        append(world.destinations, range, into: &payload)
        append(world.departures, range, into: &payload)
        append(world.fares, range, into: &payload)
        append(world.completed, range, into: &payload)
        append(world.accruedOperations, range, into: &payload)
        append(world.active, range, into: &payload)
        append(world.contracts, range, into: &payload)
        append(world.changeEpochs, range, into: &payload)
        append(world.entities, range, into: &payload)
        append(world.policies, range, into: &payload)
        append(world.origins, range, into: &payload)
        precondition(payload.count == range.count * 65)
        return record(kind: 1, index: UInt32(chunk), elements: UInt32(range.count), payload: payload)
    }

    static func nodeRecord(_ wheel: TimingWheel, chunk: Int) -> Data {
        let lo = chunk << 9
        let range = lo..<min(lo + 512, wheel.capacity)
        var payload = Data(capacity: range.count * 30)
        wheel.stageCAppendNodeChunk(range, into: &payload)
        precondition(payload.count == range.count * 30)
        return record(kind: 2, index: UInt32(chunk), elements: UInt32(range.count), payload: payload)
    }

    static func groupRecord(_ world: SwiftWorld, chunk: Int) -> Data {
        let lo = chunk << 11
        let range = lo..<min(lo + 2048, world.groupAmounts.count)
        var payload = Data(capacity: range.count * 8)
        append(world.groupAmounts, range, into: &payload)
        precondition(payload.count == range.count * 8)
        return record(kind: 3, index: UInt32(chunk), elements: UInt32(range.count), payload: payload)
    }

    static func worldDigest(_ world: SwiftWorld) -> [UInt64] {
        let assetChunks = (world.count + 255) >> 8
        let nodeChunks = (world.wheel.capacity + 511) >> 9
        let groupChunks = (world.groupAmounts.count + 2047) >> 11
        var canonical = Data(capacity: (1 + assetChunks + nodeChunks + groupChunks) * 38)
        func add(kind: UInt16, index: UInt32, record: Data) {
            let payloadBytes = record.count - 48
            let digest = record.subdata(in: (16 + payloadBytes)..<record.count)
            appendLE(kind, into: &canonical)
            appendLE(index, into: &canonical)
            canonical.append(digest)
        }
        add(kind: 0, index: 0, record: controlRecord(world))
        for chunk in 0..<assetChunks { add(kind: 1, index: UInt32(chunk), record: assetRecord(world, chunk: chunk)) }
        for chunk in 0..<nodeChunks { add(kind: 2, index: UInt32(chunk), record: nodeRecord(world.wheel, chunk: chunk)) }
        for chunk in 0..<groupChunks { add(kind: 3, index: UInt32(chunk), record: groupRecord(world, chunk: chunk)) }
        return shaWords(canonical)
    }

    static func filePrefix() -> Data {
        var data = Data(capacity: 16)
        data.append(prefix)
        appendLE(version, into: &data)
        appendLE(flags, into: &data)
        return data
    }

    static func footer(counts: [UInt32], totalBytes: UInt64,
                       canonicalDigestInput: Data) -> Data {
        precondition(counts.count == 4)
        var data = Data(capacity: 64)
        data.append(footerMagic)
        for count in counts { appendLE(count, into: &data) }
        appendLE(totalBytes, into: &data)
        data.append(digestData(canonicalDigestInput))
        precondition(data.count == 64)
        return data
    }
}

struct StageCByteReader {
    let bytes: [UInt8]
    var offset: Int = 0

    mutating func u8() throws -> UInt8 {
        guard offset < bytes.count else { throw ProbeError.corruption("stage C truncated u8") }
        defer { offset += 1 }
        return bytes[offset]
    }
    mutating func u16() throws -> UInt16 {
        guard offset <= bytes.count - 2 else { throw ProbeError.corruption("stage C truncated u16") }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
    mutating func u32() throws -> UInt32 {
        guard offset <= bytes.count - 4 else { throw ProbeError.corruption("stage C truncated u32") }
        defer { offset += 4 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
    mutating func u64() throws -> UInt64 {
        let low = try u32(), high = try u32()
        return UInt64(low) | UInt64(high) << 32
    }
    mutating func i64() throws -> Int64 { Int64(bitPattern: try u64()) }
    mutating func i32() throws -> Int { Int(Int32(bitPattern: try u32())) }
}

extension Snapshot {
    static func decodeControl(_ payload: Data) throws -> StageCWorldControl {
        var r = StageCByteReader(bytes: [UInt8](payload))
        let count = Int(try r.u32()), capacity = Int(try r.u32()), groups = Int(try r.u32())
        guard (1...2_000_000).contains(count), capacity >= count, capacity <= 2_000_000,
              groups == (count + 15) / 16 else { throw ProbeError.corruption("stage C control sizes") }
        let now = try r.u64(), revenue = try r.i64(), receivable = try r.i64(), cash = try r.i64()
        let processed = try r.u64(), sequenceHash = try r.u64()
        let rejected64 = try r.u64()
        guard rejected64 <= UInt64(Int.max) else { throw ProbeError.corruption("stage C rejected") }
        let changeEpoch = try r.u32()
        let cursor = try r.u64(), pending = Int(try r.u32()), free = try r.u32()
        let cascade = try r.i32(), leaf = try r.i32(), sortPhase = try r.i32(), width = try r.i32()
        let merges = try r.i32(), seek = try r.i32(), leftCount = try r.i32(), rightCount = try r.i32()
        let pair = try r.u32(), left = try r.u32(), right = try r.u32(), outHead = try r.u32(), outTail = try r.u32()
        var heads: [UInt32] = []; heads.reserveCapacity(2048)
        var tails: [UInt32] = []; tails.reserveCapacity(2048)
        var sorted: [Bool] = []; sorted.reserveCapacity(2048)
        var occupied: [UInt64] = []; occupied.reserveCapacity(32)
        for _ in 0..<2048 { heads.append(try r.u32()) }
        for _ in 0..<2048 { tails.append(try r.u32()) }
        for _ in 0..<2048 {
            let value = try r.u8(); guard value <= 1 else { throw ProbeError.corruption("stage C sorted") }
            sorted.append(value == 1)
        }
        for _ in 0..<32 { occupied.append(try r.u64()) }
        guard r.offset == r.bytes.count else { throw ProbeError.corruption("stage C control tail") }
        let wheel = StageCWheelControl(cursor: cursor, pending: pending, free: free,
            cascade: cascade, leaf: leaf, sortPhase: sortPhase, width: width, merges: merges,
            seek: seek, leftCount: leftCount, rightCount: rightCount,
            pair: pair, left: left, right: right, outHead: outHead, outTail: outTail,
            heads: heads, tails: tails, sorted: sorted, occupied: occupied)
        return StageCWorldControl(count: count, eventCapacity: capacity, groups: groups, now: now,
            revenue: revenue, receivable: receivable, cash: cash, processed: processed,
            sequenceHash: sequenceHash, rejectedStale: Int(rejected64), changeEpoch: changeEpoch,
            wheel: wheel)
    }

    static func applyAssetPayload(_ payload: Data, index: UInt32, elements: UInt32,
                                  to world: SwiftWorld) throws {
        let count = Int(elements), start = Int(index) << 8
        guard count > 0, start >= 0, start + count <= world.count, payload.count == count * 65 else {
            throw ProbeError.corruption("stage C asset chunk")
        }
        var r = StageCByteReader(bytes: [UInt8](payload))
        var generations=[UInt32]();generations.reserveCapacity(count)
        var airports=[UInt32]();airports.reserveCapacity(count)
        var destinations=[UInt32]();destinations.reserveCapacity(count)
        var departures=[UInt64]();departures.reserveCapacity(count)
        var fares=[Int64]();fares.reserveCapacity(count)
        var completed=[UInt64]();completed.reserveCapacity(count)
        var accrued=[UInt64]();accrued.reserveCapacity(count)
        var active=[UInt8]();active.reserveCapacity(count)
        var contracts=[UInt32]();contracts.reserveCapacity(count)
        var epochs=[UInt32]();epochs.reserveCapacity(count)
        var entities=[UInt32]();entities.reserveCapacity(count)
        var policies=[UInt32]();policies.reserveCapacity(count)
        var origins=[UInt32]();origins.reserveCapacity(count)
        for _ in 0..<count { generations.append(try r.u32()) }
        for _ in 0..<count { airports.append(try r.u32()) }
        for _ in 0..<count { destinations.append(try r.u32()) }
        for _ in 0..<count { departures.append(try r.u64()) }
        for _ in 0..<count { fares.append(try r.i64()) }
        for _ in 0..<count { completed.append(try r.u64()) }
        for _ in 0..<count { accrued.append(try r.u64()) }
        for _ in 0..<count { active.append(try r.u8()) }
        for _ in 0..<count { contracts.append(try r.u32()) }
        for _ in 0..<count { epochs.append(try r.u32()) }
        for _ in 0..<count { entities.append(try r.u32()) }
        for _ in 0..<count { policies.append(try r.u32()) }
        for _ in 0..<count { origins.append(try r.u32()) }
        for j in 0..<count {
            try world.restoreAsset(start+j, gen: generations[j], airport: airports[j],
                destination: destinations[j], departure: departures[j], fare: fares[j],
                trips: completed[j], last: accrued[j], active: active[j],
                contract: contracts[j], assetChangeEpoch: epochs[j], entity: entities[j],
                policy: policies[j], origin: origins[j])
        }
    }

    static func applyNodePayload(_ payload: Data, index: UInt32, elements: UInt32,
                                 to wheel: TimingWheel) throws {
        let count = Int(elements), start = Int(index) << 9
        guard count > 0, start + count <= wheel.capacity, payload.count == count * 30 else {
            throw ProbeError.corruption("stage C node chunk")
        }
        var r = StageCByteReader(bytes: [UInt8](payload))
        var due=[UInt64]();due.reserveCapacity(count)
        var operation=[UInt64]();operation.reserveCapacity(count)
        var asset=[UInt32]();asset.reserveCapacity(count)
        var generation=[UInt32]();generation.reserveCapacity(count)
        var next=[UInt32]();next.reserveCapacity(count)
        var kind=[UInt8]();kind.reserveCapacity(count)
        var live=[UInt8]();live.reserveCapacity(count)
        for _ in 0..<count { due.append(try r.u64()) }
        for _ in 0..<count { operation.append(try r.u64()) }
        for _ in 0..<count { asset.append(try r.u32()) }
        for _ in 0..<count { generation.append(try r.u32()) }
        for _ in 0..<count { next.append(try r.u32()) }
        for _ in 0..<count { kind.append(try r.u8()) }
        for _ in 0..<count { live.append(try r.u8()) }
        for j in 0..<count {
            try wheel.stageCRestoreNode(start+j, due: due[j], operation: operation[j],
                asset: asset[j], generation: generation[j], next: next[j],
                kind: kind[j], live: live[j])
        }
    }

    static func applyGroupPayload(_ payload: Data, index: UInt32, elements: UInt32,
                                  to world: SwiftWorld) throws {
        let count = Int(elements), start = Int(index) << 11
        guard count > 0, start + count <= world.groupAmounts.count, payload.count == count * 8 else {
            throw ProbeError.corruption("stage C group chunk")
        }
        var r = StageCByteReader(bytes: [UInt8](payload))
        for j in 0..<count { try world.restoreGroup(start+j, try r.i64()) }
    }
}
#endif
