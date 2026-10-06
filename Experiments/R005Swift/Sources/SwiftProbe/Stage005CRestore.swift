#if STAGE_C
import Foundation

struct StageCRestored {
    let world: SwiftWorld
    let epoch: UInt32
    let replayedCommands: UInt64
    let ignoredWALTailBytes: Int
    let terminalWALEpoch: UInt32
    let terminalWALReplay: StageCWALReplayResult
}

enum StageCSnapshotRestore {
    private struct RecordLocation {
        let elements: UInt32
        let payload: Range<Int>
        let digest: Data
    }

    static func markerValid(_ directory: String, epoch: UInt32) -> Bool {
        let path = directory + "/snapshot-\(epoch).commit"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count == 8 else { return false }
        var r = StageCByteReader(bytes: [UInt8](data))
        return (try? r.u32()) == epoch && (try? r.u32()) == UInt32(0x54494d43)
    }

    static func restoreSnapshot(_ path: String) throws -> SwiftWorld {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        guard data.count >= 16 + 64, data.prefix(8) == Snapshot.prefix else {
            throw ProbeError.corruption("stage C snapshot prefix")
        }
        var prefix = StageCByteReader(bytes: Array(data[8..<16]))
        guard try prefix.u32() == Snapshot.version, try prefix.u32() == Snapshot.flags else {
            throw ProbeError.corruption("stage C snapshot version/flags")
        }
        let footerStart = data.count - 64
        guard data.subdata(in: footerStart..<(footerStart + 8)) == Snapshot.footerMagic else {
            throw ProbeError.corruption("stage C footer magic")
        }
        var footer = StageCByteReader(bytes: Array(data[(footerStart + 8)..<data.count]))
        var footerCounts: [UInt32] = []
        for _ in 0..<4 { footerCounts.append(try footer.u32()) }
        let footerBytes = try footer.u64()
        var footerDigest = Data()
        for _ in 0..<32 { footerDigest.append(try footer.u8()) }
        guard footerBytes == UInt64(data.count) else { throw ProbeError.corruption("stage C footer bytes") }

        var locations: [StageCRecordKey: RecordLocation] = [:]
        var counts = [UInt32](repeating: 0, count: 4)
        var position = 16
        while position < footerStart {
            guard position + 16 <= footerStart else { throw ProbeError.corruption("stage C record header tail") }
            var h = StageCByteReader(bytes: Array(data[position..<(position + 16)]))
            let kind = try h.u16(), reserved = try h.u16(), index = try h.u32()
            let elements = try h.u32(), payloadBytes = Int(try h.u32())
            guard reserved == 0, kind <= 3, payloadBytes >= 0 else {
                throw ProbeError.corruption("stage C record header")
            }
            let end = position + 16 + payloadBytes + 32
            guard end <= footerStart else { throw ProbeError.corruption("stage C record truncation") }
            let payloadRange = (position + 16)..<(position + 16 + payloadBytes)
            let digest = data.subdata(in: (position + 16 + payloadBytes)..<end)
            let payload = data.subdata(in: payloadRange)
            guard digest == Snapshot.digestData(payload) else { throw ProbeError.corruption("stage C restore payload hash") }
            let key = StageCRecordKey(kind: kind, index: index)
            guard locations[key] == nil else { throw ProbeError.corruption("stage C duplicate record restore") }
            locations[key] = RecordLocation(elements: elements, payload: payloadRange, digest: digest)
            counts[Int(kind)] += 1
            position = end
        }
        guard position == footerStart, counts == footerCounts else {
            throw ProbeError.corruption("stage C record/footer counts")
        }
        guard let controlLoc = locations[StageCRecordKey(kind: 0, index: 0)] else {
            throw ProbeError.corruption("stage C missing control")
        }
        let control = try Snapshot.decodeControl(data.subdata(in: controlLoc.payload))
        let expected: [UInt32] = [1, UInt32((control.count + 255) >> 8),
            UInt32((control.eventCapacity + 511) >> 9), UInt32((control.groups + 2047) >> 11)]
        guard counts == expected else { throw ProbeError.corruption("stage C expected chunk counts") }
        for kind in UInt16(0)...UInt16(3) {
            for index in UInt32(0)..<expected[Int(kind)] {
                guard locations[StageCRecordKey(kind: kind, index: index)] != nil else {
                    throw ProbeError.corruption("stage C missing canonical chunk")
                }
            }
        }
        var canonical = Data(capacity: locations.count * 38)
        for kind in UInt16(0)...UInt16(3) {
            for index in UInt32(0)..<expected[Int(kind)] {
                let key = StageCRecordKey(kind: kind, index: index)
                Snapshot.appendLE(kind, into: &canonical); Snapshot.appendLE(index, into: &canonical)
                canonical.append(locations[key]!.digest)
            }
        }
        guard Snapshot.digestData(canonical) == footerDigest else {
            throw ProbeError.corruption("stage C footer rollup")
        }

        let world = try SwiftWorld(count: control.count, eventCapacity: control.eventCapacity)
        try world.restoreScalars(now: control.now, revenue: control.revenue,
            receivable: control.receivable, cash: control.cash, processed: control.processed,
            hash: control.sequenceHash)
        try world.stageCRestoreExtras(rejected: control.rejectedStale, changeEpoch: control.changeEpoch)
        for index in UInt32(0)..<expected[1] {
            let key = StageCRecordKey(kind: 1, index: index), location = locations[key]!
            try Snapshot.applyAssetPayload(data.subdata(in: location.payload), index: index,
                                           elements: location.elements, to: world)
        }
        for index in UInt32(0)..<expected[2] {
            let key = StageCRecordKey(kind: 2, index: index), location = locations[key]!
            try Snapshot.applyNodePayload(data.subdata(in: location.payload), index: index,
                                          elements: location.elements, to: world.wheel)
        }
        for index in UInt32(0)..<expected[3] {
            let key = StageCRecordKey(kind: 3, index: index), location = locations[key]!
            try Snapshot.applyGroupPayload(data.subdata(in: location.payload), index: index,
                                           elements: location.elements, to: world)
        }
        try world.wheel.stageCRestoreControl(control.wheel)
        var liveCount = 0
        var seen = ContiguousArray(repeating: UInt8(0), count: world.count)
        for id in 0..<world.wheel.capacity where world.wheel.live[id] == 1 {
            liveCount += 1
            let e = world.wheel.event(UInt32(id)), i = Int(e.asset)
            guard i < world.count, seen[i] == 0, world.active[i] == 1,
                  e.generation == world.generations[i] else {
                throw ProbeError.corruption("stage C restored live event")
            }
            seen[i] = 1
        }
        guard liveCount == world.wheel.pending else { throw ProbeError.corruption("stage C restored pending") }
        for i in 0..<world.count {
            guard seen[i] == world.active[i] else { throw ProbeError.corruption("stage C restored active/event") }
        }
        return world
    }

    static func committedEpochs(_ directory: String) throws -> [UInt32] {
        var epochs: [UInt32] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: directory)
            where name.hasPrefix("snapshot-") && name.hasSuffix(".commit") {
            let raw = name.dropFirst(9).dropLast(7)
            if let value = UInt32(raw), markerValid(directory, epoch: value) { epochs.append(value) }
        }
        return epochs.sorted(by: >)
    }

    static func walEpochs(_ directory: String) throws -> [UInt32] {
        var epochs: [UInt32] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: directory)
            where name.hasPrefix("wal-") && name.hasSuffix(".log") {
            let raw = name.dropFirst(4).dropLast(4)
            if let value = UInt32(raw) { epochs.append(value) }
        }
        return epochs.sorted()
    }

    static func recoverLatest(_ directory: String) throws -> StageCRestored {
        let epochs = try committedEpochs(directory)
        guard !epochs.isEmpty else { throw ProbeError.corruption("stage C no committed snapshot") }
        let allWALs = try walEpochs(directory)
        var lastError: Error? = nil
        for epoch in epochs {
            do {
                let world = try restoreSnapshot(directory + "/snapshot-\(epoch).bin")
                let replayEpochs = allWALs.filter { $0 >= epoch }
                guard replayEpochs.first == epoch else {
                    throw ProbeError.corruption("stage C missing base WAL")
                }
                var expected = epoch
                var commands: UInt64 = 0
                var ignoredTail = 0
                var terminalEpoch = epoch
                var terminalReplay: StageCWALReplayResult? = nil
                for (position, walEpoch) in replayEpochs.enumerated() {
                    guard walEpoch == expected else { throw ProbeError.corruption("stage C WAL epoch gap") }
                    let replay = try StageCWALReplay.replay(
                        path: directory + "/wal-\(walEpoch).log", on: world)
                    let sum = commands.addingReportingOverflow(replay.commands)
                    guard !sum.overflow else { throw ProbeError.corruption("stage C replay count overflow") }
                    commands = sum.partialValue
                    ignoredTail = replay.ignoredTailBytes
                    terminalEpoch = walEpoch
                    terminalReplay = replay
                    if ignoredTail > 0 {
                        guard position == replayEpochs.count - 1 else {
                            throw ProbeError.corruption("stage C WAL after torn current WAL")
                        }
                        break
                    }
                    if expected == UInt32.max {
                        guard position == replayEpochs.count - 1 else {
                            throw ProbeError.corruption("stage C WAL epoch overflow")
                        }
                    } else {
                        expected += 1
                    }
                }
                guard let terminalReplay else {
                    throw ProbeError.corruption("stage C missing terminal WAL")
                }
                return StageCRestored(world: world, epoch: epoch,
                    replayedCommands: commands, ignoredWALTailBytes: ignoredTail,
                    terminalWALEpoch: terminalEpoch, terminalWALReplay: terminalReplay)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ProbeError.corruption("stage C no restorable generation")
    }
}
#endif
