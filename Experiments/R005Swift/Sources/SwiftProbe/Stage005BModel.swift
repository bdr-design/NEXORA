import Foundation
import ProbePlatform

let bManifestMagic: UInt64 = 0x32464e414d42584e
let bManifestCommit: UInt32 = 0x54494d43
let bSummaryRecordBytes = 40
let bDays = 30
let bAssets = 1_000_000

struct BOpenBits {
    var words: ContiguousArray<UInt64>
    init(count: Int) { words = .init(repeating: 0, count: (count + 63) >> 6) }
    mutating func set(_ i: Int, _ value: Bool) {
        let w = i >> 6, m = UInt64(1) << (i & 63)
        if value { words[w] |= m } else { words[w] &= ~m }
    }
    func get(_ i: Int) -> Bool { (words[i >> 6] & (UInt64(1) << (i & 63))) != 0 }
}

struct BTotals: Equatable {
    var debit = ContiguousArray(repeating: Int64(0), count: bDays * 32 * 3)
    var credit = ContiguousArray(repeating: Int64(0), count: bDays * 32 * 3)
    var rows = ContiguousArray(repeating: UInt64(0), count: bDays * 32 * 3)
    mutating func add(_ row: LedgerRow) throws {
        guard row.entity < 32, row.period >= 1, row.period <= UInt32(bDays), row.debit < 3, row.credit < 3 else {
            throw ProbeError.corruption("B totals key")
        }
        let base = (Int(row.period - 1) * 32 + Int(row.entity)) * 3
        let di = base + Int(row.debit), ci = base + Int(row.credit)
        let nd = debit[di].addingReportingOverflow(row.amount)
        let nc = credit[ci].addingReportingOverflow(row.amount)
        guard !nd.overflow && !nc.overflow else { throw ProbeError.invalid("B totals overflow") }
        debit[di] = nd.partialValue
        credit[ci] = nc.partialValue
        rows[di] += 1
        rows[ci] += 1
    }
    mutating func add(_ other: BTotals) throws {
        for i in debit.indices {
            let d = debit[i].addingReportingOverflow(other.debit[i])
            let c = credit[i].addingReportingOverflow(other.credit[i])
            guard !d.overflow && !c.overflow else { throw ProbeError.invalid("B totals combine overflow") }
            debit[i] = d.partialValue
            credit[i] = c.partialValue
            rows[i] += other.rows[i]
        }
    }
}

struct BSummaryKey: Hashable {
    let entity: UInt32
    let account: UInt32
    let period: UInt32
}
struct BDeltaValue {
    var debit: Int64 = 0
    var credit: Int64 = 0
    var rows: UInt64 = 0
}

func bDelay(day: Int, group: Int) -> Int {
    let value = (day + group) % 100
    if value == 0 { return 10 }
    if value % 10 == 0 { return 4 }
    return 1
}

func bAmount(group: Int, day: Int, groupSize: Int) -> Int64 {
    let start = group * groupSize
    var total: Int64 = 0
    for asset in start..<(start + groupSize) {
        total += 5 * Int64((asset + day) % 97 + 101)
    }
    return total
}

func bIssueRow(group: Int, day: Int, groups: Int, groupSize: Int) -> LedgerRow {
    let invoice = UInt64(day) * UInt64(groups) + UInt64(group) + 1
    return LedgerRow(invoice: invoice, operation: invoice * 2 - 1,
        tick: UInt64(day + 1) * 86_400 - 1,
        amount: bAmount(group: group, day: day, groupSize: groupSize),
        asset: UInt32(group * groupSize), generation: 1, entity: UInt32(group % 32),
        period: UInt32(day + 1), debit: 1, credit: 2, flags: 0)
}

func bCollectionRow(group: Int, issueDay: Int, collectionDay: Int,
                            groups: Int, groupSize: Int) -> LedgerRow {
    let invoice = UInt64(issueDay) * UInt64(groups) + UInt64(group) + 1
    return LedgerRow(invoice: invoice, operation: invoice * 2,
        tick: UInt64(collectionDay) * 86_400 + 600,
        amount: bAmount(group: group, day: issueDay, groupSize: groupSize),
        asset: UInt32(group * groupSize), generation: 1, entity: UInt32(group % 32),
        period: UInt32(collectionDay + 1), debit: 0, credit: 1, flags: 2)
}

func bSegmentPath(_ directory: String, _ day: Int) -> String { directory + "/seg-\(day).detail" }
func bCarryPath(_ directory: String, _ version: Int) -> String { directory + "/carry-\(version).bin" }
func bSummaryPath(_ directory: String) -> String { directory + "/summary.delta" }
func bManifestPath(_ directory: String) -> String { directory + "/manifest.log" }

func bDirectoryBytes(_ directory: String) throws -> Int {
    var total = 0
    for name in try FileManager.default.contentsOfDirectory(atPath: directory) {
        total += try fileSize(directory + "/" + name)
    }
    return total
}
func bDetailBytes(_ directory: String) throws -> Int {
    var total = 0
    for name in try FileManager.default.contentsOfDirectory(atPath: directory) where name.hasSuffix(".detail") {
        total += try fileSize(directory + "/" + name)
    }
    return total
}

func bWriteSegment(directory: String, day: Int, groups: Int, groupSize: Int,
                           open: inout BOpenBits, reference: inout BTotals) throws -> (BTotals, Int, UInt64) {
    let start = nx_now()
    let writer = try RowWriter(bSegmentPath(directory, day))
    var totals = BTotals()
    for group in 0..<groups {
        let row = bIssueRow(group: group, day: day, groups: groups, groupSize: groupSize)
        try writer.append(row); try totals.add(row); try reference.add(row)
        open.set(Int(row.invoice - 1), true)
    }
    for delay in [1, 4, 10] {
        let issueDay = day - delay
        if issueDay < 0 { continue }
        for group in 0..<groups where bDelay(day: issueDay, group: group) == delay {
            let row = bCollectionRow(group: group, issueDay: issueDay, collectionDay: day,
                                     groups: groups, groupSize: groupSize)
            try writer.append(row); try totals.add(row); try reference.add(row)
            open.set(Int(row.invoice - 1), false)
        }
    }
    try writer.close()
    return (totals, try fileSize(bSegmentPath(directory, day)), nx_now() - start)
}
