import Foundation
import ProbePlatform

func bReadCarry(_ directory: String, version: Int?) throws -> [LedgerRow] {
    guard let version else { return [] }
    let path = bCarryPath(directory, version)
    guard FileManager.default.fileExists(atPath: path) else { throw ProbeError.corruption("missing committed carry") }
    var values: [LedgerRow] = []
    _ = try rows(path) { values.append($0) }
    return values
}

func bWriteCarry(_ rowsToWrite: [LedgerRow], directory: String, version: Int) throws -> Int {
    let path = bCarryPath(directory, version)
    let writer = try RowWriter(path)
    for row in rowsToWrite { try writer.append(row) }
    try writer.close()
    return try fileSize(path)
}

func bSummarize(_ row: LedgerRow, segment: Int,
                        into deltas: inout [BSummaryKey: BDeltaValue],
                        open: BOpenBits) throws {
    if row.debit == 1 && row.credit == 2 && open.get(Int(row.invoice - 1)) {
        throw ProbeError.invariant("B open issue summarized")
    }
    let debitKey = BSummaryKey(entity: row.entity, account: row.debit, period: row.period)
    let creditKey = BSummaryKey(entity: row.entity, account: row.credit, period: row.period)
    var dv = deltas[debitKey, default: BDeltaValue()]
    let nd = dv.debit.addingReportingOverflow(row.amount)
    guard !nd.overflow else { throw ProbeError.invalid("B delta debit overflow") }
    dv.debit = nd.partialValue; dv.rows += 1; deltas[debitKey] = dv
    var cv = deltas[creditKey, default: BDeltaValue()]
    let nc = cv.credit.addingReportingOverflow(row.amount)
    guard !nc.overflow else { throw ProbeError.invalid("B delta credit overflow") }
    cv.credit = nc.partialValue; cv.rows += 1; deltas[creditKey] = cv
    _ = segment
}

func bAppendDeltas(_ deltas: [BSummaryKey: BDeltaValue], segment: Int,
                           directory: String) throws -> Int {
    let path = bSummaryPath(directory)
    if !FileManager.default.fileExists(atPath: path) { _ = FileManager.default.createFile(atPath: path, contents: nil) }
    let h = try FileHandle(forWritingTo: URL(fileURLWithPath: path)); defer { try? h.close() }
    try h.seekToEnd()
    let ordered = deltas.keys.sorted {
        if $0.period != $1.period { return $0.period < $1.period }
        if $0.entity != $1.entity { return $0.entity < $1.entity }
        return $0.account < $1.account
    }
    let split = max(1, ordered.count / 2)
    for (position, key) in ordered.enumerated() {
        let value = deltas[key]!
        var b = Bytes(reserve: bSummaryRecordBytes)
        b.u32(UInt32(segment)); b.u32(key.entity); b.u32(key.account); b.u32(key.period)
        b.i64(value.debit); b.i64(value.credit); b.u64(value.rows)
        try require(b.data.count == bSummaryRecordBytes, "B summary delta size")
        try h.write(contentsOf: Data(b.data))
        if position + 1 == split { nx_kill_point("b.s1.mid_summary_append") }
    }
    try h.synchronize()
    nx_kill_point("b.s2.after_summary_sync")
    return try fileSize(path)
}

func bReadSummary(_ directory: String, limit: Int? = nil) throws -> BTotals {
    let path = bSummaryPath(directory)
    guard FileManager.default.fileExists(atPath: path) else { return BTotals() }
    let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    let end = limit ?? bytes.count
    guard end <= bytes.count, end % bSummaryRecordBytes == 0 else { throw ProbeError.corruption("B summary length") }
    var r = Reader(bytes: Array(bytes[0..<end]))
    var totals = BTotals()
    while r.offset < r.bytes.count {
        _ = try r.u32()
        let entity = try r.u32(), account = try r.u32(), period = try r.u32()
        let debit = try r.i64(), credit = try r.i64(), count = try r.u64()
        guard entity < 32, account < 3, period >= 1, period <= UInt32(bDays), debit >= 0, credit >= 0 else {
            throw ProbeError.corruption("B summary record")
        }
        let index = (Int(period - 1) * 32 + Int(entity)) * 3 + Int(account)
        totals.debit[index] += debit; totals.credit[index] += credit; totals.rows[index] += count
    }
    return totals
}

func bAppendManifest(segment: Int, segmentHash: [UInt64], summaryLength: Int,
                             carryVersion: Int, directory: String) throws {
    try require(segmentHash.count == 4, "B segment hash width")
    let path = bManifestPath(directory)
    let fd = nx_open_append(path); guard fd >= 0 else { throw ProbeError.invalid("B manifest open") }
    let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? h.close() }
    var b = Bytes(reserve: 64)
    b.u64(bManifestMagic); b.u32(UInt32(segment)); b.u32(UInt32(carryVersion)); b.u64(UInt64(summaryLength))
    for v in segmentHash { b.u64(v) }
    let crc = nx_crc(0, b.data, b.data.count); b.u32(crc); b.u32(bManifestCommit)
    try require(b.data.count == 64, "B manifest record size")
    try h.write(contentsOf: Data(b.data)); try h.synchronize()
    nx_kill_point("b.s4.after_manifest_sync")
}

struct BManifestState { let segment: Int; let carryVersion: Int; let summaryLength: Int }
func bManifestState(_ directory: String) throws -> BManifestState? {
    let path = bManifestPath(directory)
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: path)))
    var offset = 0, last: BManifestState? = nil
    while offset + 64 <= bytes.count {
        let frame = Array(bytes[offset..<(offset + 64)])
        var r = Reader(bytes: frame)
        guard try r.u64() == bManifestMagic else { throw ProbeError.corruption("B manifest magic") }
        let segment = Int(try r.u32()), carry = Int(try r.u32()), summary = Int(try r.u64())
        for _ in 0..<4 { _ = try r.u64() }
        let crc = try r.u32(), marker = try r.u32()
        guard marker == bManifestCommit, crc == nx_crc(0, frame, 56) else { throw ProbeError.corruption("B manifest committed record") }
        if let last { guard segment == last.segment + 1 else { throw ProbeError.corruption("B manifest sequence") } }
        last = BManifestState(segment: segment, carryVersion: carry, summaryLength: summary)
        offset += 64
    }
    return last
}

func bRecoverStore(_ directory: String) throws -> BManifestState? {
    let state = try bManifestState(directory)
    let summary = bSummaryPath(directory)
    if FileManager.default.fileExists(atPath: summary) {
        let h = try FileHandle(forWritingTo: URL(fileURLWithPath: summary)); defer { try? h.close() }
        try h.truncate(atOffset: UInt64(state?.summaryLength ?? 0)); try h.synchronize()
    }
    for name in try FileManager.default.contentsOfDirectory(atPath: directory) {
        if name.hasPrefix("carry-") && name.hasSuffix(".bin") {
            let raw = name.dropFirst(6).dropLast(4)
            if let version = Int(raw), version != state?.carryVersion { try FileManager.default.removeItem(atPath: directory + "/" + name) }
        }
        if name.hasPrefix("seg-") && name.hasSuffix(".detail"), let committed = state?.segment {
            let raw = name.dropFirst(4).dropLast(7)
            if let day = Int(raw), day <= committed { try FileManager.default.removeItem(atPath: directory + "/" + name) }
        }
    }
    guard nx_sync_dir(directory) == 0 else { throw ProbeError.invalid("B recovery directory sync") }
    return state
}

func bCloseSegment(directory: String, segment: Int, open: BOpenBits,
                           previousCarryVersion: Int?, reference: BTotals,
                           liveSegmentTotals: [Int: BTotals]) throws -> [String: Any] {
    let start = nx_now()
    let previousCarry = try bReadCarry(directory, version: previousCarryVersion)
    var nextCarry: [LedgerRow] = []; nextCarry.reserveCapacity(previousCarry.count + 1024)
    var deltas: [BSummaryKey: BDeltaValue] = [:]
    var summarizedRowsActual: UInt64 = 0
    for row in previousCarry {
        if open.get(Int(row.invoice - 1)) { nextCarry.append(row) }
        else { try bSummarize(row, segment: segment, into: &deltas, open: open); summarizedRowsActual += 1 }
    }
    let segmentPath = bSegmentPath(directory, segment)
    _ = try rows(segmentPath) { row in
        if row.debit == 1 && row.credit == 2 && open.get(Int(row.invoice - 1)) { nextCarry.append(row) }
        else {
            try bSummarize(row, segment: segment, into: &deltas, open: open)
            summarizedRowsActual += 1
        }
    }
    var debit: Int64 = 0, credit: Int64 = 0
    for value in deltas.values { debit += value.debit; credit += value.credit }
    try require(debit == credit, "B I1 debit != credit")
    let summaryLength = try bAppendDeltas(deltas, segment: segment, directory: directory)
    let carryBytes = try bWriteCarry(nextCarry, directory: directory, version: segment)
    nx_kill_point("b.s3.after_carry_sync")
    try bAppendManifest(segment: segment, segmentHash: try fileHash(segmentPath),
                        summaryLength: summaryLength, carryVersion: segment, directory: directory)
    let preDeleteBytes = try bDirectoryBytes(directory)
    try FileManager.default.removeItem(atPath: segmentPath)
    if let previousCarryVersion, previousCarryVersion != segment {
        let old = bCarryPath(directory, previousCarryVersion)
        if FileManager.default.fileExists(atPath: old) { try FileManager.default.removeItem(atPath: old) }
    }
    nx_kill_point("b.s5.after_delete_before_dirsync")
    guard nx_sync_dir(directory) == 0 else { throw ProbeError.invalid("B close directory sync") }

    var actual = try bReadSummary(directory)
    var carryTotals = BTotals()
    for row in nextCarry { try carryTotals.add(row) }
    try actual.add(carryTotals)
    for (day, totals) in liveSegmentTotals where day > segment { try actual.add(totals) }
    try require(actual == reference, "B I2 summary+window+carry != independent reference")
    return ["summarizeNS":nx_now() - start, "rowsSummarized":summarizedRowsActual,
            "openCarried":nextCarry.count, "carryBytes":carryBytes, "preDeleteBytes":preDeleteBytes,
            "invariants":["I1":true,"I2":true,"I3":true]]
}

func bVerifyDisk(directory: String, throughDay: Int, groups: Int, groupSize: Int) throws -> [String: Any] {
    let state = try bRecoverStore(directory)
    var actual = try bReadSummary(directory, limit: state?.summaryLength)
    if let state {
        for row in try bReadCarry(directory, version: state.carryVersion) { try actual.add(row) }
    }
    for day in 0...throughDay {
        let path = bSegmentPath(directory, day)
        if FileManager.default.fileExists(atPath: path) { _ = try rows(path) { try actual.add($0) } }
    }
    var expected = BTotals()
    for day in 0...throughDay {
        for group in 0..<groups { try expected.add(bIssueRow(group: group, day: day, groups: groups, groupSize: groupSize)) }
        for delay in [1,4,10] {
            let issueDay = day - delay
            if issueDay < 0 { continue }
            for group in 0..<groups where bDelay(day: issueDay, group: group) == delay {
                try expected.add(bCollectionRow(group: group, issueDay: issueDay, collectionDay: day,
                                                groups: groups, groupSize: groupSize))
            }
        }
    }
    try require(actual == expected, "B final disk scan != independent reference")
    return ["status":"pass","committedSegment":state?.segment ?? -1,"totalsExact":true]
}
