#if STAGE_C
import Foundation
import ProbePlatform
import Synchronization

// Existing digest/footer helpers serve as an independent v2 file oracle.
private func stageCMicroWriterFiles(_ directory: String) throws -> [String: Any] {
    let world = try SwiftWorld(count: 4096)
    try world.seedFixture()
    let state = StageCState(world: world)
    let counts = state.expectedCounts
    var records: [(StageCRecordKey, [UInt8])] = [
        (.init(kind: 0, index: 0), Snapshot.controlRecord(world))
    ]
    for chunk in (0..<state.nodeChunks).reversed() {
        records.append((.init(kind: 2, index: UInt32(chunk)), Snapshot.nodeRecord(world.wheel, chunk: chunk)))
    }
    for chunk in (0..<state.assetChunks).reversed() {
        records.append((.init(kind: 1, index: UInt32(chunk)), Snapshot.assetRecord(world, chunk: chunk)))
    }
    for chunk in (0..<state.groupChunks).reversed() {
        records.append((.init(kind: 3, index: UInt32(chunk)), Snapshot.groupRecord(world, chunk: chunk)))
    }
    var expected = Snapshot.filePrefix()
    var referenceDigests: [StageCRecordKey: Data] = [:]
    for (key, record) in records {
        let digest = Snapshot.digestBytes(record, range: 16..<record.count)
        expected.append(contentsOf: record)
        expected.append(digest)
        referenceDigests[key] = digest
    }
    var canonical = Data()
    for kind in UInt16(0)...UInt16(3) {
        for index in UInt32(0)..<counts[Int(kind)] {
            Snapshot.appendLE(kind, into: &canonical)
            Snapshot.appendLE(index, into: &canonical)
            canonical.append(referenceDigests[.init(kind: kind, index: index)]!)
        }
    }
    expected.append(Snapshot.footer(counts: counts, totalBytes: UInt64(expected.count + 64),
                                    canonicalDigestInput: canonical))
    func write(_ bytes: [[UInt8]], name: String) throws -> StageCSnapshotFileResult {
        let path = directory + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let queue = StageCRecordQueue(capacity: max(1, bytes.count))
        let counters = StageCWriterCounters()
        for record in bytes {
            _ = counters.queued.add(record.count + 32, ordering: .relaxed)
            queue.push(record)
        }
        queue.finish()
        let result = try StageCSnapshotWriter.run(queue, counters: counters,
            directory: path, epoch: 1, expectedCounts: counts)
        try require(counters.queued.load(ordering: .relaxed) == 0, "micro drained batch byte count")
        return result
    }
    let result = try write(records.map { $0.1 }, name: "valid")
    let actual = try Data(contentsOf: URL(fileURLWithPath: directory + "/valid/snapshot-1.bin"))
    try require(actual == expected && result.bytes == UInt64(expected.count), "micro exact v2 file oracle")
    try require(result.chunks == records.count, "micro exact writer record count")
    var outOfRange = records[0].1; outOfRange[4] = 1
    var reserved = records[0].1; reserved[2] = 1
    let invalid: [(String, [[UInt8]])] = [
        ("duplicate", [records[0].1, records[0].1]),
        ("missing", [records[0].1]), ("out-of-range", [outOfRange]),
        ("reserved", [reserved]), ("short", [[0, 1, 2]])
    ]
    var rejected = 0
    for (name, bytes) in invalid {
        do { _ = try write(bytes, name: name) }
        catch ProbeError.corruption { rejected += 1 }
        try require(!FileManager.default.fileExists(atPath: directory + "/" + name + "/snapshot-1.commit"),
                    "micro invalid record must not commit")
    }
    try require(rejected == invalid.count, "micro writer record rejection")
    return ["status":"pass", "population":world.count, "exactFileBytes":actual.count,
            "records":records.count, "writerRecordChunks":result.chunks,
            "noncanonicalInputOrder":true, "rejectedRecordCases":rejected]
}

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
    let writerFiles = try stageCMicroWriterFiles(directory + "/writer-files")
    return ["status":"pass","fifoRecords":10000,"emptyFinish":true,
            "exactWrittenBytes":10000,"rejectedMisuse":rejected,
            "knownSHA256":true,"legacyDigestEncoding":true,
            "writerFiles":writerFiles,
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
