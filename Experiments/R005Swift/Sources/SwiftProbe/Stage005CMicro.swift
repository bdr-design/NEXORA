#if STAGE_C
import Foundation
import ProbePlatform
import Synchronization

func stageCMicroTransportChecks(_ directory: String) throws -> [String: Any] {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let empty = StageCRecordQueue(capacity: 1)
    empty.finish()
    try require(empty.waitAndPop() == nil && empty.isDrained, "micro empty finish wake")

    let queue = StageCRecordQueue(capacity: 10000)
    let group = DispatchGroup(), started = DispatchSemaphore(value: 0)
    let failures = Atomic<Int>(0), consumed = Atomic<Int>(0)
    group.enter()
    DispatchQueue.global(qos: .utility).async {
        defer { group.leave() }
        started.signal()
        for i in 0..<10000 {
            guard let r = queue.waitAndPop(), r.count == 2,
                  (Int(r[0]) | (Int(r[1]) << 8)) == i else {
                failures.store(1, ordering: .releasing)
                return
            }
            _ = consumed.add(1, ordering: .relaxed)
        }
        if queue.waitAndPop() != nil { failures.store(1, ordering: .releasing) }
    }
    try require(started.wait(timeout: .now() + 5) == .success, "micro consumer startup")
    for i in 0..<10000 { queue.push([UInt8(truncatingIfNeeded: i), UInt8(truncatingIfNeeded: i >> 8)]) }
    queue.finish()
    try require(group.wait(timeout: .now() + 5) == .success, "micro queue completion")
    try require(failures.load(ordering: .acquiring) == 0 &&
                consumed.load(ordering: .acquiring) == 10000 && queue.isDrained, "micro queue FIFO")

    let path = directory + "/transport.bin"
    try require(FileManager.default.createFile(atPath: path, contents: nil), "micro writer file")
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    let bytes = (0..<10000).map { UInt8(truncatingIfNeeded: $0) }
    for range in [0..<17, 17..<9999, 9999..<10000] {
        try Snapshot.writeRecord(bytes, descriptor: handle.fileDescriptor, range: range)
    }
    try handle.synchronize()
    try require(try Data(contentsOf: URL(fileURLWithPath: path)) == Data(bytes), "micro exact writer bytes")
    var rejected = 0
    do { try Snapshot.writeRecord(bytes, descriptor: -1, range: 0..<1) } catch { rejected += 1 }
    do { try Snapshot.writeRecord(bytes, descriptor: handle.fileDescriptor, range: 0..<10001) } catch { rejected += 1 }
    try require(rejected == 2, "micro writer error/range rejection")
    let abc = Data("abc".utf8)
    let knownSHA = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    let digest = Snapshot.digestData(abc)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    var oldDigest = Data()
    Snapshot.appendDigestHash(Snapshot.hashData(abc), into: &oldDigest)
    try require(hex == knownSHA && digest == oldDigest &&
                Snapshot.digestBytes([UInt8](abc), range: 0..<3) == oldDigest,
                "micro independent SHA-256 and digest encoding")
    return ["status":"pass","fifoRecords":10000,"emptyFinish":true,
            "exactWrittenBytes":10000,"rejectedMisuse":rejected,
            "knownSHA256":true,"legacyDigestEncoding":true,
            "scope":"queue/writer lifecycle checks, not Stage C acceptance"]
}

// Diagnostic only. No micro result may close C or select a production layout.
private func microDrain(_ world: SwiftWorld, sink: SnapshotSink? = nil) throws -> [String: Any] {
    var elapsed: UInt64 = 0, events = 0, calls = 0, activeWriterCalls = 0
    var maxAlloc: UInt64 = 0
    while true {
        if let sink, try sink.resultIfDone() == nil { activeWriterCalls += 1 }
        nx_alloc_begin()
        let start = nx_now()
        let p = try world.advance(to: 600, budget: 1024)
        let finish = nx_now()
        let allocations = nx_alloc_end()
        try require(allocations.available == 1, "micro allocation observer unavailable")
        elapsed += finish - start; events += p.events; calls += 1
        maxAlloc = max(maxAlloc, allocations.calls)
        try require(p.stop != .blocked, "micro drain blocked")
        if p.stop == .target { break }
    }
    try require(events == world.count, "micro complete event count")
    return ["nsPerEvent":Double(elapsed)/Double(events),"events":events,"calls":calls,
            "activeWriterCalls":activeWriterCalls,"maxAllocations":maxAlloc]
}

func stageCMicroComponents(_ directory: String) throws -> [String: Any] {
    let positive = nx_alloc_calibrate()
    try require(positive > 0, "micro allocator positive control")
    let world = try SwiftWorld(count: 1_000_000); try world.seedFixture()
    let state = StageCState(world: world)
    func record(_ canonical: Int) -> [UInt8] {
        if canonical < state.assetChunks { return Snapshot.assetRecord(world, chunk: canonical) }
        if canonical < state.assetChunks + state.nodeChunks {
            return Snapshot.nodeRecord(world.wheel, chunk: canonical - state.assetChunks)
        }
        return Snapshot.groupRecord(world, chunk: canonical - state.assetChunks - state.nodeChunks)
    }
    var copyRows: [[String: Any]] = []
    for run in 0..<4 {
        var ns: UInt64 = 0, allocations: UInt64 = 0, bytes = 0, checksum: UInt64 = 0
        for i in 0..<state.totalChunks {
            nx_alloc_begin(); let start = nx_now()
            let value = record(i)
            let finish = nx_now(); let a = nx_alloc_end()
            ns += finish - start; allocations += a.calls; bytes += value.count
            checksum &+= UInt64(value[16]) + UInt64(value[value.count - 1])
        }
        copyRows.append(["run":run,"warmup":run==0,"ns":ns,"bytes":bytes,
                         "allocations":allocations,"records":state.totalChunks,"checksum":checksum])
    }
    let shared = Snapshot.assetRecord(world, chunk: 0)
    let queue = StageCRecordQueue(capacity: 10000)
    nx_alloc_begin(); let queueStart = nx_now()
    for _ in 0..<10000 { queue.push(shared) }
    let queueNS = nx_now() - queueStart; let queueAlloc = nx_alloc_end()
    try require(queueAlloc.available == 1 && queueAlloc.calls == 0, "micro queue producer allocations")
    queue.finish()
    for _ in 0..<10000 { try require(queue.pop() != nil, "micro queue missing record") }
    try require(queue.isDrained, "micro queue drain")

    var advanceRows: [[String: Any]] = []
    for run in 0..<3 {
        let plain = try SwiftWorld(count: 1_000_000); try plain.seedFixture()
        var a = try microDrain(plain); a["mode"]="no-state"; a["run"]=run; advanceRows.append(a)
        let installed = try SwiftWorld(count: 1_000_000); try installed.seedFixture()
        installed.stageCInstall(StageCState(world: installed))
        var b = try microDrain(installed); b["mode"]="idle-state"; b["run"]=run; advanceRows.append(b)

        let concurrent = try SwiftWorld(count: 1_000_000); try concurrent.seedFixture()
        concurrent.stageCInstall(StageCState(world: concurrent))
        let path = directory + "/writer-\(run)"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let sink = SnapshotSink(directory: path, epoch: 1, expectedCounts: state.expectedCounts)
        sink.emit(Snapshot.controlRecord(world))
        for i in 0..<state.totalChunks { sink.emit(record(i)) }
        sink.finish()
        var c = try microDrain(concurrent, sink: sink); c["mode"]="idle-with-writer"; c["run"]=run; advanceRows.append(c)
        var spins = 0
        while try sink.resultIfDone() == nil {
            Thread.sleep(forTimeInterval: 0.00005); spins += 1
            try require(spins < 1000000, "micro writer timeout")
        }
    }
    return ["status":"diagnostic","variant":"S","assets":world.count,
            "copy":copyRows,"queue":["pushes":10000,"ns":queueNS,"allocations":queueAlloc.calls],
            "advanceModes":advanceRows,"scope":"bounded components; not Stage C acceptance"]
}
#endif
