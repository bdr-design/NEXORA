import Foundation
import ProbePlatform

func stageBRun(_ directory: String, caseName: String, window: Int = 7) throws -> [String: Any] {
    let groups: Int, groupSize: Int
    if caseName == "G16" { groups = 62_500; groupSize = 16 }
    else if caseName == "G1" { groups = 1_000_000; groupSize = 1 }
    else { throw ProbeError.invalid("stage-b case G16|G1") }
    guard window == 3 || window == 7 else { throw ProbeError.invalid("stage-b window") }
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
    _ = FileManager.default.createFile(atPath: bSummaryPath(directory), contents: nil)
    _ = FileManager.default.createFile(atPath: bManifestPath(directory), contents: nil)
    var open = BOpenBits(count: groups * bDays)
    var reference = BTotals()
    var segmentTotals: [Int: BTotals] = [:]
    var previousCarryVersion: Int? = nil
    var records: [[String: Any]] = []
    var peakBytes = 0, maxDayBytes = 0, maxCarryBytes = 0
    for day in 0..<bDays {
        let written = try bWriteSegment(directory: directory, day: day, groups: groups, groupSize: groupSize,
                                        open: &open, reference: &reference)
        segmentTotals[day] = written.0; maxDayBytes = max(maxDayBytes, written.1)
        peakBytes = max(peakBytes, try bDirectoryBytes(directory))
        var close: [String: Any] = ["summarizeNS":0,"rowsSummarized":0,"openCarried":0,
                                    "carryBytes":0,"preDeleteBytes":try bDirectoryBytes(directory),
                                    "invariants":["I1":true,"I2":true,"I3":true]]
        if day >= window {
            let segment = day - window
            close = try bCloseSegment(directory: directory, segment: segment, open: open,
                                      previousCarryVersion: previousCarryVersion, reference: reference,
                                      liveSegmentTotals: segmentTotals)
            previousCarryVersion = segment
            segmentTotals.removeValue(forKey: segment)
            maxCarryBytes = max(maxCarryBytes, close["carryBytes"] as? Int ?? 0)
            peakBytes = max(peakBytes, close["preDeleteBytes"] as? Int ?? 0)
        }
        let total = try bDirectoryBytes(directory)
        peakBytes = max(peakBytes, total)
        records.append(["case":caseName,"window":window,"day":day + 1,
                        "detailBytes":try bDetailBytes(directory),"totalBytes":total,"peakBytes":peakBytes,
                        "segmentWriteNS":written.2,"summarizeNS":close["summarizeNS"]!,
                        "rowsSummarized":close["rowsSummarized"]!,"openCarried":close["openCarried"]!,
                        "invariants":close["invariants"]!])
    }
    let verified = try bVerifyDisk(directory: directory, throughDay: bDays - 1, groups: groups, groupSize: groupSize)
    let summaryBytes = try fileSize(bSummaryPath(directory))
    return ["status":"pass","case":caseName,"window":window,"assets":bAssets,"groups":groups,
            "days":records,"BdayMax":maxDayBytes,"S30":summaryBytes,"Omax":maxCarryBytes,
            "peakBytes":peakBytes,"finalDiskVerification":verified]
}

func stageBCrashBootstrap(_ directory: String) throws -> [String: Any] {
    let groups = 128, groupSize = 1
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
    _ = FileManager.default.createFile(atPath: bSummaryPath(directory), contents: nil)
    _ = FileManager.default.createFile(atPath: bManifestPath(directory), contents: nil)
    var open = BOpenBits(count: groups * bDays), reference = BTotals()
    for day in 0...2 { _ = try bWriteSegment(directory: directory, day: day, groups: groups, groupSize: groupSize, open: &open, reference: &reference) }
    return ["status":"pass"]
}

func bCrashState(groups: Int, throughDay: Int) throws -> (BOpenBits, BTotals, [Int: BTotals]) {
    var open = BOpenBits(count: groups * bDays), reference = BTotals(), totals: [Int: BTotals] = [:]
    for day in 0...throughDay {
        var t = BTotals()
        for group in 0..<groups {
            let row = bIssueRow(group: group, day: day, groups: groups, groupSize: 1)
            try t.add(row); try reference.add(row); open.set(Int(row.invoice - 1), true)
        }
        for delay in [1,4,10] {
            let issueDay = day - delay; if issueDay < 0 { continue }
            for group in 0..<groups where bDelay(day: issueDay, group: group) == delay {
                let row = bCollectionRow(group: group, issueDay: issueDay, collectionDay: day, groups: groups, groupSize: 1)
                try t.add(row); try reference.add(row); open.set(Int(row.invoice - 1), false)
            }
        }
        totals[day] = t
    }
    return (open, reference, totals)
}

func stageBCrashAction(_ directory: String) throws -> [String: Any] {
    let state = try bCrashState(groups: 128, throughDay: 2)
    _ = try bCloseSegment(directory: directory, segment: 0, open: state.0,
                          previousCarryVersion: nil, reference: state.1, liveSegmentTotals: state.2)
    return ["status":"pass"]
}

func stageBRecoverCrash(_ directory: String) throws -> [String: Any] {
    let result = try bVerifyDisk(directory: directory, throughDay: 2, groups: 128, groupSize: 1)
    return result
}
