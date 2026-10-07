#if SEALED_WAL_MICRO
import Foundation
import ProbePlatform
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Preconditions: this disposable study has one process and one exclusive owner
// for its temporary directory.  Its fixture is deliberately small and keeps
// one scalar/root as the live state; WAL frame verification is streaming and
// uses reusable frame/header buffers.  Directory listings and manifest history
// are still dynamically allocated: fixed metadata pools are not implemented.
// It has no second world or full-file Data read.
//
// Limitations: this is not the Stage C WAL, a production checkpoint format, a
// cross-process locking design, a physical power-loss certification, an H1M/C
// result, or permission to redefine savesCommitted.  Crash points below model
// process interruption after individual durable-publication operations; only a
// real device/filesystem campaign can characterize power-loss persistence.
// The modeled I/O failures below are branch injection, not syscall-level fault
// injection.  There is no durable CURRENT pointer, request ID, or status query.

private let sealedHeaderBytes = 192
private let sealedFrameBytes = 128
private let sealedSealBytes = 320
private let sealedManifestBytes = 320
private let sealedBaseBytes = 144
private let sealedFormat: UInt32 = 1
private let sealedSchema: UInt32 = 7
private let sealedEngine: UInt32 = 11
private let sealedLayout: UInt32 = 3
private let sealedNoSegment = UInt64.max

private let sealedHeaderMagic = Array("NXRSWAL1".utf8)
private let sealedFrameMagic = Array("NXRFRM01".utf8)
private let sealedSealMagic = Array("NXRSEAL1".utf8)
private let sealedManifestMagic = Array("NXRMAN01".utf8)
private let sealedBaseMagic = Array("NXRBASE1".utf8)

private struct SealedFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private struct SealedInjectedCrash: Error {
    let phase: SealedCrashPhase
}

@inline(__always)
private func sealedCheck(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    let passed = try condition()
    if !passed { throw SealedFailure(message) }
}

@inline(__always)
private func sealedAdd(_ left: UInt64, _ right: UInt64, _ message: String) throws -> UInt64 {
    let result = left.addingReportingOverflow(right)
    try sealedCheck(!result.overflow, message)
    return result.partialValue
}

@inline(__always)
private func sealedMultiply(_ left: UInt64, _ right: UInt64,
                            _ message: String) throws -> UInt64 {
    let result = left.multipliedReportingOverflow(by: right)
    try sealedCheck(!result.overflow, message)
    return result.partialValue
}

@inline(__always)
private func sealedInt(_ value: UInt64, _ message: String) throws -> Int {
    try sealedCheck(value <= UInt64(Int.max), message)
    return Int(value)
}

private struct SealedDigest: Equatable, Hashable, Sendable {
    var a: UInt64
    var b: UInt64
    var c: UInt64
    var d: UInt64

    static let zero = SealedDigest(a: 0, b: 0, c: 0, d: 0)

    var hex: String {
        String(format: "%016llx%016llx%016llx%016llx", a, b, c, d)
    }
}

@inline(__always)
private func sealedPutU32(_ value: UInt32, _ bytes: inout [UInt8], _ offset: Int) {
    bytes[offset] = UInt8(truncatingIfNeeded: value)
    bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
    bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
}

@inline(__always)
private func sealedPutU64(_ value: UInt64, _ bytes: inout [UInt8], _ offset: Int) {
    for byte in 0..<8 { bytes[offset + byte] = UInt8(truncatingIfNeeded: value >> UInt64(byte * 8)) }
}

@inline(__always)
private func sealedGetU32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
}

@inline(__always)
private func sealedGetU64(_ bytes: [UInt8], _ offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for byte in 0..<8 { value |= UInt64(bytes[offset + byte]) << UInt64(byte * 8) }
    return value
}

private func sealedPutMagic(_ magic: [UInt8], _ bytes: inout [UInt8], _ offset: Int = 0) {
    precondition(magic.count == 8)
    for index in 0..<8 { bytes[offset + index] = magic[index] }
}

private func sealedHasMagic(_ magic: [UInt8], _ bytes: [UInt8], _ offset: Int = 0) -> Bool {
    guard magic.count == 8, bytes.count >= offset + 8 else { return false }
    for index in 0..<8 where bytes[offset + index] != magic[index] { return false }
    return true
}

private func sealedPutDigest(_ digest: SealedDigest, _ bytes: inout [UInt8], _ offset: Int) {
    sealedPutU64(digest.a, &bytes, offset)
    sealedPutU64(digest.b, &bytes, offset + 8)
    sealedPutU64(digest.c, &bytes, offset + 16)
    sealedPutU64(digest.d, &bytes, offset + 24)
}

private func sealedGetDigest(_ bytes: [UInt8], _ offset: Int) -> SealedDigest {
    SealedDigest(a: sealedGetU64(bytes, offset), b: sealedGetU64(bytes, offset + 8),
                 c: sealedGetU64(bytes, offset + 16), d: sealedGetU64(bytes, offset + 24))
}

private func sealedHashBytes(_ bytes: [UInt8], count: Int? = nil) throws -> SealedDigest {
    let selected = count ?? bytes.count
    try sealedCheck(selected >= 0 && selected <= bytes.count, "sealed hash byte bounds")
    let result: NXRHash = bytes.withUnsafeBytes { raw in
        nx_hash_bytes(raw.bindMemory(to: UInt8.self).baseAddress, selected)
    }
    try sealedCheck(result.status == 0, "sealed byte digest")
    return SealedDigest(a: result.a, b: result.b, c: result.c, d: result.d)
}

private func sealedHashFile(_ path: String) throws -> SealedDigest {
    let result: NXRHash = path.withCString { nx_hash_file($0) }
    try sealedCheck(result.status == 0, "sealed file digest: \(path)")
    return SealedDigest(a: result.a, b: result.b, c: result.c, d: result.d)
}

private func sealedOpenExclusive(_ path: String) throws -> Int32 {
    let descriptor = path.withCString { nx_open_exclusive($0) }
    try sealedCheck(descriptor >= 0, "sealed exclusive open: \(path) errno \(-descriptor)")
    return descriptor
}

private func sealedOpenAppend(_ path: String) throws -> Int32 {
    let descriptor = path.withCString { nx_open_append($0) }
    try sealedCheck(descriptor >= 0, "sealed append open: \(path) errno \(-descriptor)")
    return descriptor
}

private func sealedOpenRead(_ path: String) throws -> Int32 {
    let descriptor: Int32 = path.withCString { pointer in
#if canImport(Darwin)
        Darwin.open(pointer, O_RDONLY | O_NOFOLLOW)
#else
        Glibc.open(pointer, O_RDONLY | O_NOFOLLOW)
#endif
    }
    try sealedCheck(descriptor >= 0, "sealed read open: \(path) errno \(errno)")
    return descriptor
}

private func sealedOpenRewrite(_ path: String) throws -> Int32 {
    let descriptor: Int32 = path.withCString { pointer in
#if canImport(Darwin)
        Darwin.open(pointer, O_WRONLY | O_TRUNC | O_NOFOLLOW)
#else
        Glibc.open(pointer, O_WRONLY | O_TRUNC | O_NOFOLLOW)
#endif
    }
    try sealedCheck(descriptor >= 0, "sealed rewrite open: \(path) errno \(errno)")
    return descriptor
}

private func sealedOpenWriteExisting(_ path: String) throws -> Int32 {
    let descriptor: Int32 = path.withCString { pointer in
#if canImport(Darwin)
        Darwin.open(pointer, O_WRONLY | O_NOFOLLOW)
#else
        Glibc.open(pointer, O_WRONLY | O_NOFOLLOW)
#endif
    }
    try sealedCheck(descriptor >= 0, "sealed write-existing open: \(path) errno \(errno)")
    return descriptor
}

@inline(__always)
private func sealedSystemWrite(_ descriptor: Int32, _ pointer: UnsafeRawPointer,
                               _ count: Int) -> Int {
#if canImport(Darwin)
    Darwin.write(descriptor, pointer, count)
#else
    Glibc.write(descriptor, pointer, count)
#endif
}

@inline(__always)
private func sealedSystemPread(_ descriptor: Int32, _ pointer: UnsafeMutableRawPointer,
                               _ count: Int, _ offset: Int64) -> Int {
#if canImport(Darwin)
    Darwin.pread(descriptor, pointer, count, off_t(offset))
#else
    Glibc.pread(descriptor, pointer, count, off_t(offset))
#endif
}

@inline(__always)
private func sealedSystemPwrite(_ descriptor: Int32, _ pointer: UnsafeRawPointer,
                                _ count: Int, _ offset: Int64) -> Int {
#if canImport(Darwin)
    Darwin.pwrite(descriptor, pointer, count, off_t(offset))
#else
    Glibc.pwrite(descriptor, pointer, count, off_t(offset))
#endif
}

private func sealedWriteAll(_ descriptor: Int32, _ bytes: [UInt8], count: Int? = nil) throws {
    let selected = count ?? bytes.count
    try sealedCheck(selected >= 0 && selected <= bytes.count, "sealed write bounds")
    var written = 0
    try bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { throw SealedFailure("sealed write buffer") }
        while written < selected {
            let result = sealedSystemWrite(descriptor, base.advanced(by: written), selected - written)
            if result < 0 && errno == EINTR { continue }
            try sealedCheck(result > 0, "sealed write errno \(errno)")
            written += result
        }
    }
}

private func sealedReadExact(_ descriptor: Int32, offset: UInt64,
                             bytes: inout [UInt8], count: Int) throws {
    try sealedCheck(count >= 0 && count <= bytes.count,
                    "sealed read bounds")
    let lastOffset = try sealedAdd(offset, UInt64(count), "sealed read offset overflow")
    try sealedCheck(lastOffset <= UInt64(Int64.max), "sealed read offset range")
    var received = 0
    try bytes.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { throw SealedFailure("sealed read buffer") }
        while received < count {
            let current = Int64(offset) + Int64(received)
            let result = sealedSystemPread(descriptor, base.advanced(by: received),
                                           count - received, current)
            if result < 0 && errno == EINTR { continue }
            try sealedCheck(result > 0, "sealed short/failed read at \(current)")
            received += result
        }
    }
}

private func sealedPwriteAll(_ descriptor: Int32, offset: UInt64,
                             bytes: [UInt8], count: Int) throws {
    try sealedCheck(count >= 0 && count <= bytes.count,
                    "sealed pwrite bounds")
    let lastOffset = try sealedAdd(offset, UInt64(count), "sealed pwrite offset overflow")
    try sealedCheck(lastOffset <= UInt64(Int64.max), "sealed pwrite offset range")
    var written = 0
    try bytes.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { throw SealedFailure("sealed pwrite buffer") }
        while written < count {
            let current = Int64(offset) + Int64(written)
            let result = sealedSystemPwrite(descriptor, base.advanced(by: written),
                                            count - written, current)
            if result < 0 && errno == EINTR { continue }
            try sealedCheck(result > 0, "sealed pwrite errno \(errno)")
            written += result
        }
    }
}

private func sealedCopyRange(source: String, sourceOffset: UInt64,
                             destination: String, destinationOffset: UInt64,
                             count: Int) throws {
    var buffer = [UInt8](repeating: 0, count: count)
    let sourceDescriptor = try sealedOpenRead(source)
    do {
        try sealedReadExact(sourceDescriptor, offset: sourceOffset, bytes: &buffer, count: count)
        sealedClose(sourceDescriptor)
    } catch {
        sealedClose(sourceDescriptor)
        throw error
    }
    let destinationDescriptor = try sealedOpenWriteExisting(destination)
    do {
        try sealedPwriteAll(destinationDescriptor, offset: destinationOffset,
                            bytes: buffer, count: count)
        try sealedSync(destinationDescriptor, "sealed range-copy sync")
        sealedClose(destinationDescriptor)
    } catch {
        sealedClose(destinationDescriptor)
        throw error
    }
}

private func sealedClose(_ descriptor: Int32) {
    guard descriptor >= 0 else { return }
#if canImport(Darwin)
    _ = Darwin.close(descriptor)
#else
    _ = Glibc.close(descriptor)
#endif
}

private func sealedSync(_ descriptor: Int32, _ message: String) throws {
#if canImport(Darwin)
    let result = Darwin.fsync(descriptor)
#else
    let result = Glibc.fsync(descriptor)
#endif
    try sealedCheck(result == 0, "\(message) errno \(errno)")
}

private func sealedFileSize(_ descriptor: Int32) throws -> UInt64 {
    var value = stat()
#if canImport(Darwin)
    let result = Darwin.fstat(descriptor, &value)
#else
    let result = Glibc.fstat(descriptor, &value)
#endif
    try sealedCheck(result == 0 && value.st_size >= 0, "sealed fstat errno \(errno)")
    return UInt64(value.st_size)
}

private func sealedFileSize(_ path: String) throws -> UInt64 {
    let descriptor = try sealedOpenRead(path)
    defer { sealedClose(descriptor) }
    return try sealedFileSize(descriptor)
}

private func sealedTruncate(_ path: String, bytes: UInt64) throws {
    try sealedCheck(bytes <= UInt64(Int64.max), "sealed truncate offset range")
    let descriptor: Int32 = path.withCString { pointer in
#if canImport(Darwin)
        Darwin.open(pointer, O_WRONLY | O_NOFOLLOW)
#else
        Glibc.open(pointer, O_WRONLY | O_NOFOLLOW)
#endif
    }
    try sealedCheck(descriptor >= 0, "sealed truncate open")
    defer { sealedClose(descriptor) }
#if canImport(Darwin)
    let result = Darwin.ftruncate(descriptor, off_t(bytes))
#else
    let result = Glibc.ftruncate(descriptor, off_t(bytes))
#endif
    try sealedCheck(result == 0, "sealed truncate errno \(errno)")
    try sealedSync(descriptor, "sealed truncate sync")
}

private func sealedSyncDirectory(_ directory: String) throws {
    let result = directory.withCString { nx_sync_dir($0) }
    try sealedCheck(result == 0, "sealed directory sync errno \(result)")
}

private func sealedRename(_ source: String, _ destination: String) throws {
    try sealedCheck(!FileManager.default.fileExists(atPath: destination),
                    "sealed immutable destination already exists")
    let result = source.withCString { sourcePointer in
        destination.withCString { destinationPointer in
            nx_replace_file(sourcePointer, destinationPointer)
        }
    }
    try sealedCheck(result == 0, "sealed rename errno \(result)")
}

private func sealedWriteNew(_ path: String, bytes: [UInt8], count: Int,
                            synchronize: Bool) throws {
    let descriptor = try sealedOpenExclusive(path)
    do {
        try sealedWriteAll(descriptor, bytes, count: count)
        if synchronize { try sealedSync(descriptor, "sealed new-file sync") }
        sealedClose(descriptor)
    } catch {
        sealedClose(descriptor)
        throw error
    }
}

private func sealedRewrite(_ path: String, bytes: [UInt8], count: Int) throws {
    let descriptor = try sealedOpenRewrite(path)
    do {
        try sealedWriteAll(descriptor, bytes, count: count)
        try sealedSync(descriptor, "sealed rewrite sync")
        sealedClose(descriptor)
    } catch {
        sealedClose(descriptor)
        throw error
    }
}

private func sealedAppendBytes(_ path: String, bytes: [UInt8], count: Int) throws {
    let descriptor = try sealedOpenAppend(path)
    do {
        try sealedWriteAll(descriptor, bytes, count: count)
        try sealedSync(descriptor, "sealed append corruption sync")
        sealedClose(descriptor)
    } catch {
        sealedClose(descriptor)
        throw error
    }
}

private func sealedReadFixed(_ path: String, expected: Int, buffer: inout [UInt8]) throws {
    try sealedCheck(expected >= 0 && buffer.count >= expected, "sealed fixed buffer capacity")
    let descriptor = try sealedOpenRead(path)
    defer { sealedClose(descriptor) }
    try sealedCheck(try sealedFileSize(descriptor) == UInt64(expected),
                    "sealed exact file length: \(path)")
    try sealedReadExact(descriptor, offset: 0, bytes: &buffer, count: expected)
}

private func sealedSegmentWAL(_ directory: String, _ segment: UInt64) -> String {
    directory + "/segment-\(segment).wal"
}

private func sealedSegmentSeal(_ directory: String, _ segment: UInt64) -> String {
    directory + "/segment-\(segment).seal"
}

private func sealedManifestPath(_ directory: String, _ generation: UInt64) -> String {
    directory + "/manifest-\(generation).bin"
}

private func sealedParseNumber(_ name: String, prefix: String, suffix: String) -> UInt64? {
    guard name.hasPrefix(prefix), name.hasSuffix(suffix),
          name.count > prefix.count + suffix.count else { return nil }
    let begin = name.index(name.startIndex, offsetBy: prefix.count)
    let end = name.index(name.endIndex, offsetBy: -suffix.count)
    return UInt64(name[begin..<end])
}

private func sealedRootTransition(_ prior: SealedDigest, lsn: UInt64,
                                  delta: Int64, scratch: inout [UInt8]) throws -> SealedDigest {
    try sealedCheck(scratch.count >= 48, "sealed root scratch")
    for index in 0..<scratch.count { scratch[index] = 0 }
    sealedPutDigest(prior, &scratch, 0)
    sealedPutU64(lsn, &scratch, 32)
    sealedPutU64(UInt64(bitPattern: delta), &scratch, 40)
    return try sealedHashBytes(scratch, count: 48)
}

private struct SealedBase: Sendable {
    let store: SealedDigest
    let identifier: SealedDigest
    let initialRoot: SealedDigest
    let initialValue: Int64
}

private struct SealedHeader: Sendable {
    let store: SealedDigest
    let base: SealedDigest
    let parentSeal: SealedDigest
    let initialRoot: SealedDigest
    let segment: UInt64
    let epoch: UInt64
    let firstLSN: UInt64
    let parentSegment: UInt64
    let schema: UInt32
    let engine: UInt32
    let layout: UInt32
}

private struct SealedSeal: Sendable {
    let store: SealedDigest
    let base: SealedDigest
    let parentSeal: SealedDigest
    let walDigest: SealedDigest
    let terminalRoot: SealedDigest
    let headerDigest: SealedDigest
    let segment: UInt64
    let epoch: UInt64
    let firstLSN: UInt64
    let lastLSN: UInt64
    let byteLength: UInt64
    let frameCount: UInt64
    let schema: UInt32
    let engine: UInt32
    let layout: UInt32
    let parentSegment: UInt64
}

private struct SealedManifest: Sendable {
    let store: SealedDigest
    let base: SealedDigest
    let tipSeal: SealedDigest
    let tipRoot: SealedDigest
    let activeHeader: SealedDigest
    let previousManifest: SealedDigest
    let generation: UInt64
    let tipSegment: UInt64
    let activeSegment: UInt64
    let durableLSN: UInt64
    let schema: UInt32
    let engine: UInt32
    let layout: UInt32
    let tipEpoch: UInt64
    let activeFirstLSN: UInt64
}

private func sealedEncodeBase(store: SealedDigest, initialRoot: SealedDigest,
                              initialValue: Int64, into bytes: inout [UInt8]) throws {
    try sealedCheck(bytes.count >= sealedBaseBytes, "sealed base buffer")
    for index in 0..<sealedBaseBytes { bytes[index] = 0 }
    sealedPutMagic(sealedBaseMagic, &bytes)
    sealedPutU32(sealedFormat, &bytes, 8)
    sealedPutU32(UInt32(sealedBaseBytes), &bytes, 12)
    sealedPutDigest(store, &bytes, 16)
    sealedPutU32(sealedSchema, &bytes, 48)
    sealedPutU32(sealedEngine, &bytes, 52)
    sealedPutU32(sealedLayout, &bytes, 56)
    sealedPutDigest(initialRoot, &bytes, 64)
    sealedPutU64(UInt64(bitPattern: initialValue), &bytes, 96)
    let selfDigest = try sealedHashBytes(bytes, count: 112)
    sealedPutDigest(selfDigest, &bytes, 112)
}

private func sealedDecodeBase(_ bytes: [UInt8], identifier: SealedDigest) throws -> SealedBase {
    try sealedCheck(bytes.count >= sealedBaseBytes && sealedHasMagic(sealedBaseMagic, bytes),
                    "sealed base magic")
    try sealedCheck(sealedGetU32(bytes, 8) == sealedFormat &&
                    sealedGetU32(bytes, 12) == UInt32(sealedBaseBytes), "sealed base format")
    try sealedCheck(sealedGetU32(bytes, 48) == sealedSchema &&
                    sealedGetU32(bytes, 52) == sealedEngine &&
                    sealedGetU32(bytes, 56) == sealedLayout && sealedGetU32(bytes, 60) == 0,
                    "sealed base versions")
    for index in 104..<112 where bytes[index] != 0 {
        throw SealedFailure("sealed base reserved")
    }
    try sealedCheck(sealedGetDigest(bytes, 112) == sealedHashBytes(bytes, count: 112),
                    "sealed base self digest")
    return SealedBase(store: sealedGetDigest(bytes, 16), identifier: identifier,
                      initialRoot: sealedGetDigest(bytes, 64),
                      initialValue: Int64(bitPattern: sealedGetU64(bytes, 96)))
}

private func sealedEncodeHeader(_ value: SealedHeader, into bytes: inout [UInt8]) throws {
    try sealedCheck(bytes.count >= sealedHeaderBytes, "sealed header buffer")
    for index in 0..<sealedHeaderBytes { bytes[index] = 0 }
    sealedPutMagic(sealedHeaderMagic, &bytes)
    sealedPutU32(sealedFormat, &bytes, 8)
    sealedPutU32(UInt32(sealedHeaderBytes), &bytes, 12)
    sealedPutDigest(value.store, &bytes, 16)
    sealedPutDigest(value.base, &bytes, 48)
    sealedPutDigest(value.parentSeal, &bytes, 80)
    sealedPutDigest(value.initialRoot, &bytes, 112)
    sealedPutU64(value.segment, &bytes, 144)
    sealedPutU64(value.epoch, &bytes, 152)
    sealedPutU64(value.firstLSN, &bytes, 160)
    sealedPutU64(value.parentSegment, &bytes, 168)
    sealedPutU32(value.schema, &bytes, 176)
    sealedPutU32(value.engine, &bytes, 180)
    sealedPutU32(value.layout, &bytes, 184)
}

private func sealedDecodeHeader(_ bytes: [UInt8]) throws -> SealedHeader {
    try sealedCheck(bytes.count >= sealedHeaderBytes && sealedHasMagic(sealedHeaderMagic, bytes),
                    "sealed header magic")
    try sealedCheck(sealedGetU32(bytes, 8) == sealedFormat &&
                    sealedGetU32(bytes, 12) == UInt32(sealedHeaderBytes), "sealed header format")
    try sealedCheck(sealedGetU32(bytes, 188) == 0, "sealed header reserved")
    return SealedHeader(store: sealedGetDigest(bytes, 16), base: sealedGetDigest(bytes, 48),
        parentSeal: sealedGetDigest(bytes, 80), initialRoot: sealedGetDigest(bytes, 112),
        segment: sealedGetU64(bytes, 144), epoch: sealedGetU64(bytes, 152),
        firstLSN: sealedGetU64(bytes, 160), parentSegment: sealedGetU64(bytes, 168),
        schema: sealedGetU32(bytes, 176), engine: sealedGetU32(bytes, 180),
        layout: sealedGetU32(bytes, 184))
}

private func sealedEncodeFrame(lsn: UInt64, delta: Int64, before: SealedDigest,
                               after: SealedDigest, into bytes: inout [UInt8]) throws {
    try sealedCheck(bytes.count >= sealedFrameBytes, "sealed frame buffer")
    for index in 0..<sealedFrameBytes { bytes[index] = 0 }
    sealedPutMagic(sealedFrameMagic, &bytes)
    sealedPutU32(UInt32(sealedFrameBytes), &bytes, 8)
    sealedPutU32(1, &bytes, 12)
    sealedPutU64(lsn, &bytes, 16)
    sealedPutU64(UInt64(bitPattern: delta), &bytes, 24)
    sealedPutDigest(before, &bytes, 32)
    sealedPutDigest(after, &bytes, 64)
    let frameDigest = try sealedHashBytes(bytes, count: 96)
    sealedPutDigest(frameDigest, &bytes, 96)
}

private func sealedDecodeFrame(_ bytes: [UInt8], expectedLSN: UInt64,
                               expectedRoot: SealedDigest,
                               rootScratch: inout [UInt8]) throws -> (Int64, SealedDigest) {
    try sealedCheck(bytes.count >= sealedFrameBytes && sealedHasMagic(sealedFrameMagic, bytes),
                    "sealed frame magic")
    try sealedCheck(sealedGetU32(bytes, 8) == UInt32(sealedFrameBytes) &&
                    sealedGetU32(bytes, 12) == 1, "sealed frame format/op")
    try sealedCheck(sealedGetU64(bytes, 16) == expectedLSN, "sealed global LSN")
    let delta = Int64(bitPattern: sealedGetU64(bytes, 24))
    try sealedCheck(sealedGetDigest(bytes, 32) == expectedRoot, "sealed root-before")
    let calculated = try sealedRootTransition(expectedRoot, lsn: expectedLSN,
                                              delta: delta, scratch: &rootScratch)
    try sealedCheck(sealedGetDigest(bytes, 64) == calculated, "sealed root-after")
    try sealedCheck(sealedGetDigest(bytes, 96) == sealedHashBytes(bytes, count: 96),
                    "sealed frame digest")
    return (delta, calculated)
}

private func sealedEncodeSeal(_ value: SealedSeal, into bytes: inout [UInt8]) throws {
    try sealedCheck(bytes.count >= sealedSealBytes, "sealed seal buffer")
    for index in 0..<sealedSealBytes { bytes[index] = 0 }
    sealedPutMagic(sealedSealMagic, &bytes)
    sealedPutU32(sealedFormat, &bytes, 8)
    sealedPutU32(UInt32(sealedSealBytes), &bytes, 12)
    sealedPutDigest(value.store, &bytes, 16)
    sealedPutDigest(value.base, &bytes, 48)
    sealedPutDigest(value.parentSeal, &bytes, 80)
    sealedPutDigest(value.walDigest, &bytes, 112)
    sealedPutDigest(value.terminalRoot, &bytes, 144)
    sealedPutDigest(value.headerDigest, &bytes, 176)
    sealedPutU64(value.segment, &bytes, 208)
    sealedPutU64(value.epoch, &bytes, 216)
    sealedPutU64(value.firstLSN, &bytes, 224)
    sealedPutU64(value.lastLSN, &bytes, 232)
    sealedPutU64(value.byteLength, &bytes, 240)
    sealedPutU64(value.frameCount, &bytes, 248)
    sealedPutU32(value.schema, &bytes, 256)
    sealedPutU32(value.engine, &bytes, 260)
    sealedPutU32(value.layout, &bytes, 264)
    sealedPutU64(value.parentSegment, &bytes, 272)
    let selfDigest = try sealedHashBytes(bytes, count: 288)
    sealedPutDigest(selfDigest, &bytes, 288)
}

private func sealedDecodeSeal(_ bytes: [UInt8]) throws -> SealedSeal {
    try sealedCheck(bytes.count >= sealedSealBytes && sealedHasMagic(sealedSealMagic, bytes),
                    "sealed seal magic")
    try sealedCheck(sealedGetU32(bytes, 8) == sealedFormat &&
                    sealedGetU32(bytes, 12) == UInt32(sealedSealBytes), "sealed seal format")
    try sealedCheck(sealedGetU32(bytes, 268) == 0 && sealedGetU64(bytes, 280) == 0,
                    "sealed seal reserved")
    try sealedCheck(sealedGetDigest(bytes, 288) == sealedHashBytes(bytes, count: 288),
                    "sealed seal self digest")
    return SealedSeal(store: sealedGetDigest(bytes, 16), base: sealedGetDigest(bytes, 48),
        parentSeal: sealedGetDigest(bytes, 80), walDigest: sealedGetDigest(bytes, 112),
        terminalRoot: sealedGetDigest(bytes, 144), headerDigest: sealedGetDigest(bytes, 176),
        segment: sealedGetU64(bytes, 208), epoch: sealedGetU64(bytes, 216),
        firstLSN: sealedGetU64(bytes, 224), lastLSN: sealedGetU64(bytes, 232),
        byteLength: sealedGetU64(bytes, 240), frameCount: sealedGetU64(bytes, 248),
        schema: sealedGetU32(bytes, 256), engine: sealedGetU32(bytes, 260),
        layout: sealedGetU32(bytes, 264), parentSegment: sealedGetU64(bytes, 272))
}

private func sealedEncodeManifest(_ value: SealedManifest, into bytes: inout [UInt8]) throws {
    try sealedCheck(bytes.count >= sealedManifestBytes, "sealed manifest buffer")
    for index in 0..<sealedManifestBytes { bytes[index] = 0 }
    sealedPutMagic(sealedManifestMagic, &bytes)
    sealedPutU32(sealedFormat, &bytes, 8)
    sealedPutU32(UInt32(sealedManifestBytes), &bytes, 12)
    sealedPutDigest(value.store, &bytes, 16)
    sealedPutDigest(value.base, &bytes, 48)
    sealedPutDigest(value.tipSeal, &bytes, 80)
    sealedPutDigest(value.tipRoot, &bytes, 112)
    sealedPutDigest(value.activeHeader, &bytes, 144)
    sealedPutDigest(value.previousManifest, &bytes, 176)
    sealedPutU64(value.generation, &bytes, 208)
    sealedPutU64(value.tipSegment, &bytes, 216)
    sealedPutU64(value.activeSegment, &bytes, 224)
    sealedPutU64(value.durableLSN, &bytes, 232)
    sealedPutU32(value.schema, &bytes, 240)
    sealedPutU32(value.engine, &bytes, 244)
    sealedPutU32(value.layout, &bytes, 248)
    sealedPutU64(value.tipEpoch, &bytes, 256)
    sealedPutU64(value.activeFirstLSN, &bytes, 264)
    let selfDigest = try sealedHashBytes(bytes, count: 288)
    sealedPutDigest(selfDigest, &bytes, 288)
}

private func sealedDecodeManifest(_ bytes: [UInt8]) throws -> SealedManifest {
    try sealedCheck(bytes.count >= sealedManifestBytes &&
                    sealedHasMagic(sealedManifestMagic, bytes), "sealed manifest magic")
    try sealedCheck(sealedGetU32(bytes, 8) == sealedFormat &&
                    sealedGetU32(bytes, 12) == UInt32(sealedManifestBytes),
                    "sealed manifest format")
    try sealedCheck(sealedGetU32(bytes, 252) == 0 && sealedGetU64(bytes, 272) == 0 &&
                    sealedGetU64(bytes, 280) == 0, "sealed manifest reserved")
    try sealedCheck(sealedGetDigest(bytes, 288) == sealedHashBytes(bytes, count: 288),
                    "sealed manifest self digest")
    return SealedManifest(store: sealedGetDigest(bytes, 16), base: sealedGetDigest(bytes, 48),
        tipSeal: sealedGetDigest(bytes, 80), tipRoot: sealedGetDigest(bytes, 112),
        activeHeader: sealedGetDigest(bytes, 144), previousManifest: sealedGetDigest(bytes, 176),
        generation: sealedGetU64(bytes, 208), tipSegment: sealedGetU64(bytes, 216),
        activeSegment: sealedGetU64(bytes, 224), durableLSN: sealedGetU64(bytes, 232),
        schema: sealedGetU32(bytes, 240), engine: sealedGetU32(bytes, 244),
        layout: sealedGetU32(bytes, 248), tipEpoch: sealedGetU64(bytes, 256),
        activeFirstLSN: sealedGetU64(bytes, 264))
}

private struct SealedRecoveryResult: Sendable {
    let manifest: SealedManifest
    let value: Int64
    let root: SealedDigest
    let replayedFrames: UInt64
    let activeUnpublishedBytes: UInt64
    let activeFrames: UInt64
    let pendingValue: Int64
    let pendingRoot: SealedDigest
    let pendingLSN: UInt64
}

private enum SealedRecovery {
    private static func numberedFiles(_ directory: String, prefix: String,
                                      suffix: String) throws -> [UInt64] {
        var values: [UInt64] = []
        for name in try FileManager.default.contentsOfDirectory(atPath: directory) {
            if let value = sealedParseNumber(name, prefix: prefix, suffix: suffix) {
                values.append(value)
            }
        }
        return values.sorted()
    }

    static func manifestGenerations(_ directory: String) throws -> [UInt64] {
        try numberedFiles(directory, prefix: "manifest-", suffix: ".bin")
    }

    static func loadManifest(_ directory: String, generation: UInt64,
                             buffer: inout [UInt8]) throws -> SealedManifest {
        let path = sealedManifestPath(directory, generation)
        try sealedReadFixed(path, expected: sealedManifestBytes, buffer: &buffer)
        let manifest = try sealedDecodeManifest(buffer)
        try sealedCheck(manifest.generation == generation, "sealed manifest filename generation")
        return manifest
    }

    static func loadBase(_ directory: String, buffer: inout [UInt8]) throws -> SealedBase {
        let path = directory + "/base.checkpoint"
        try sealedReadFixed(path, expected: sealedBaseBytes, buffer: &buffer)
        return try sealedDecodeBase(buffer, identifier: sealedHashFile(path))
    }

    static func recover(_ directory: String,
                        requestedGeneration: UInt64? = nil) throws -> SealedRecoveryResult {
        var small = [UInt8](repeating: 0, count: sealedManifestBytes)
        var headerBytes = [UInt8](repeating: 0, count: sealedHeaderBytes)
        var sealBytes = [UInt8](repeating: 0, count: sealedSealBytes)
        var frameBytes = [UInt8](repeating: 0, count: sealedFrameBytes)
        var rootScratch = [UInt8](repeating: 0, count: 48)

        let generations = try manifestGenerations(directory)
        try sealedCheck(!generations.isEmpty && generations[0] == 0,
                        "sealed missing manifest generation zero")
        for (index, generation) in generations.enumerated() {
            try sealedCheck(generation == UInt64(index), "sealed missing manifest generation")
        }
        guard let latestGeneration = generations.last else {
            throw SealedFailure("sealed missing latest manifest")
        }
        // This is only the highest contiguous directory entry presently
        // visible.  Without a separately durable CURRENT authority it cannot
        // detect clean deletion of that entry and every visible descendant.
        if let requestedGeneration {
            try sealedCheck(requestedGeneration == latestGeneration,
                            "sealed stale manifest generation")
        }

        let base = try loadBase(directory, buffer: &small)
        var manifests: [SealedManifest] = []
        manifests.reserveCapacity(generations.count)
        var priorManifestDigest = SealedDigest.zero
        for (generationIndex, generation) in generations.enumerated() {
            let manifest = try loadManifest(directory, generation: generation, buffer: &small)
            try sealedCheck(manifest.store == base.store && manifest.base == base.identifier,
                            "sealed manifest store/base")
            try sealedCheck(manifest.schema == sealedSchema && manifest.engine == sealedEngine &&
                            manifest.layout == sealedLayout, "sealed manifest versions")
            try sealedCheck(manifest.previousManifest == priorManifestDigest,
                            "sealed manifest history digest")
            if generation == 0 {
                try sealedCheck(manifest.tipSegment == sealedNoSegment &&
                                manifest.tipSeal == .zero && manifest.tipRoot == base.initialRoot &&
                                manifest.activeSegment == 0 && manifest.durableLSN == 0 &&
                                manifest.activeFirstLSN == 1 && manifest.tipEpoch == 0,
                                "sealed generation-zero authority")
            } else {
                try sealedCheck(manifest.tipSegment == generation - 1 &&
                                manifest.activeSegment == generation &&
                                manifest.tipEpoch == generation,
                                "sealed manifest generation/segment binding")
                let previous = manifests[generationIndex - 1]
                let expectedFirstLSN = try sealedAdd(manifest.durableLSN, 1,
                                                     "sealed manifest LSN overflow")
                try sealedCheck(manifest.durableLSN >= previous.durableLSN &&
                                manifest.activeFirstLSN == expectedFirstLSN,
                                "sealed manifest global watermark")
            }
            manifests.append(manifest)
            priorManifestDigest = try sealedHashFile(sealedManifestPath(directory, generation))
        }
        let manifest = manifests[manifests.count - 1]

        let seals = try numberedFiles(directory, prefix: "segment-", suffix: ".seal")
        if manifest.tipSegment == sealedNoSegment {
            try sealedCheck(seals.isEmpty, "sealed orphan seal before first durable tip")
        } else {
            let expectedSealCount = try sealedInt(
                try sealedAdd(manifest.tipSegment, 1, "sealed seal count overflow"),
                "sealed seal count conversion overflow")
            try sealedCheck(seals.count == expectedSealCount,
                            "sealed missing/orphan seal count")
            for (index, value) in seals.enumerated() {
                try sealedCheck(value == UInt64(index), "sealed seal chain gap/orphan")
            }
        }
        let wals = try numberedFiles(directory, prefix: "segment-", suffix: ".wal")
        let expectedWALCount = try sealedInt(
            try sealedAdd(manifest.activeSegment, 1, "sealed WAL count overflow"),
            "sealed WAL count conversion overflow")
        try sealedCheck(wals.count == expectedWALCount,
                        "sealed missing/orphan WAL count")
        for (index, value) in wals.enumerated() {
            try sealedCheck(value == UInt64(index), "sealed WAL chain gap/orphan")
        }

        var value = base.initialValue
        var root = base.initialRoot
        var nextLSN: UInt64 = 1
        var parentSeal = SealedDigest.zero
        var replayed: UInt64 = 0
        if manifest.tipSegment != sealedNoSegment {
            for segment in 0...manifest.tipSegment {
                let sealPath = sealedSegmentSeal(directory, segment)
                try sealedReadFixed(sealPath, expected: sealedSealBytes, buffer: &sealBytes)
                let seal = try sealedDecodeSeal(sealBytes)
                let expectedEpoch = try sealedAdd(segment, 1, "sealed epoch overflow")
                try sealedCheck(seal.store == base.store && seal.base == base.identifier &&
                                seal.segment == segment && seal.epoch == expectedEpoch &&
                                seal.schema == sealedSchema && seal.engine == sealedEngine &&
                                seal.layout == sealedLayout, "sealed seal identity/version")
                try sealedCheck(seal.parentSeal == parentSeal &&
                                seal.parentSegment == (segment == 0 ? sealedNoSegment : segment - 1),
                                "sealed parent chain")
                try sealedCheck(seal.frameCount > 0, "sealed empty seal")
                let expectedLastLSN = try sealedAdd(nextLSN, seal.frameCount - 1,
                                                    "sealed seal LSN overflow")
                try sealedCheck(seal.firstLSN == nextLSN &&
                                seal.lastLSN == expectedLastLSN,
                                "sealed seal LSN/frame range")
                let payloadBytes = try sealedMultiply(seal.frameCount,
                                                      UInt64(sealedFrameBytes),
                                                      "sealed WAL payload length overflow")
                let expectedBytes = try sealedAdd(UInt64(sealedHeaderBytes), payloadBytes,
                                                  "sealed WAL byte length overflow")
                try sealedCheck(seal.byteLength == expectedBytes, "sealed declared byte length")

                let walPath = sealedSegmentWAL(directory, segment)
                let descriptor = try sealedOpenRead(walPath)
                do {
                    try sealedCheck(try sealedFileSize(descriptor) == seal.byteLength,
                                    "sealed exact WAL byte length")
                    try sealedReadExact(descriptor, offset: 0, bytes: &headerBytes,
                                        count: sealedHeaderBytes)
                    let header = try sealedDecodeHeader(headerBytes)
                    let expectedHeaderEpoch = try sealedAdd(segment, 1,
                                                            "sealed header epoch overflow")
                    try sealedCheck(header.store == base.store && header.base == base.identifier &&
                                    header.segment == segment && header.epoch == expectedHeaderEpoch &&
                                    header.firstLSN == nextLSN && header.initialRoot == root &&
                                    header.parentSeal == parentSeal &&
                                    header.parentSegment == (segment == 0 ? sealedNoSegment : segment - 1) &&
                                    header.schema == sealedSchema && header.engine == sealedEngine &&
                                    header.layout == sealedLayout, "sealed WAL header authority")
                    try sealedCheck(seal.headerDigest == sealedHashBytes(headerBytes),
                                    "sealed WAL header digest")
                    for frame in 0..<seal.frameCount {
                        let frameOffset = try sealedMultiply(frame, UInt64(sealedFrameBytes),
                                                             "sealed frame offset overflow")
                        let offset = try sealedAdd(UInt64(sealedHeaderBytes), frameOffset,
                                                   "sealed frame offset overflow")
                        try sealedReadExact(descriptor, offset: offset, bytes: &frameBytes,
                                            count: sealedFrameBytes)
                        let decoded = try sealedDecodeFrame(frameBytes, expectedLSN: nextLSN,
                                                            expectedRoot: root,
                                                            rootScratch: &rootScratch)
                        let sum = value.addingReportingOverflow(decoded.0)
                        try sealedCheck(!sum.overflow, "sealed recovered value overflow")
                        value = sum.partialValue
                        root = decoded.1
                        nextLSN = try sealedAdd(nextLSN, 1, "sealed recovery LSN overflow")
                        replayed = try sealedAdd(replayed, 1, "sealed replay count overflow")
                    }
                    sealedClose(descriptor)
                } catch {
                    sealedClose(descriptor)
                    throw error
                }
                try sealedCheck(seal.walDigest == sealedHashFile(walPath),
                                "sealed WAL digest mismatch")
                let afterLastLSN = try sealedAdd(seal.lastLSN, 1,
                                                 "sealed terminal LSN overflow")
                try sealedCheck(seal.terminalRoot == root && afterLastLSN == nextLSN,
                                "sealed terminal root/watermark")
                parentSeal = try sealedHashFile(sealPath)
                if segment == manifest.tipSegment {
                    try sealedCheck(parentSeal == manifest.tipSeal,
                                    "sealed manifest tip seal digest")
                }
            }
        }
        let afterDurableLSN = try sealedAdd(manifest.durableLSN, 1,
                                            "sealed durable LSN overflow")
        try sealedCheck(afterDurableLSN == nextLSN &&
                        manifest.tipRoot == root && manifest.tipSeal == parentSeal,
                        "sealed manifest durable tip exactness")

        let activePath = sealedSegmentWAL(directory, manifest.activeSegment)
        let activeDescriptor = try sealedOpenRead(activePath)
        let activeSize: UInt64
        do {
            activeSize = try sealedFileSize(activeDescriptor)
            try sealedCheck(activeSize >= UInt64(sealedHeaderBytes), "sealed active header length")
            try sealedReadExact(activeDescriptor, offset: 0, bytes: &headerBytes,
                                count: sealedHeaderBytes)
            sealedClose(activeDescriptor)
        } catch {
            sealedClose(activeDescriptor)
            throw error
        }
        let active = try sealedDecodeHeader(headerBytes)
        let expectedActiveEpoch = try sealedAdd(manifest.activeSegment, 1,
                                                "sealed active epoch overflow")
        let expectedActiveFirstLSN = try sealedAdd(manifest.durableLSN, 1,
                                                   "sealed active LSN overflow")
        try sealedCheck(active.store == base.store && active.base == base.identifier &&
                        active.segment == manifest.activeSegment &&
                        active.epoch == expectedActiveEpoch &&
                        active.parentSegment == manifest.tipSegment &&
                        active.parentSeal == manifest.tipSeal && active.initialRoot == root &&
                        active.firstLSN == manifest.activeFirstLSN &&
                        active.firstLSN == expectedActiveFirstLSN &&
                        active.schema == sealedSchema && active.engine == sealedEngine &&
                        active.layout == sealedLayout, "sealed active successor authority")
        try sealedCheck(sealedHashBytes(headerBytes) == manifest.activeHeader,
                        "sealed active successor digest")
        let activePayloadBytes = activeSize - UInt64(sealedHeaderBytes)
        try sealedCheck(activePayloadBytes % UInt64(sealedFrameBytes) == 0,
                        "sealed torn active frame")
        let activeFrames = activePayloadBytes / UInt64(sealedFrameBytes)
        var pendingValue = value
        var pendingRoot = root
        var pendingLSN = nextLSN
        if activeFrames > 0 {
            let descriptor = try sealedOpenRead(activePath)
            do {
                for frame in 0..<activeFrames {
                    let frameOffset = try sealedMultiply(frame, UInt64(sealedFrameBytes),
                                                         "sealed active frame offset overflow")
                    let offset = try sealedAdd(UInt64(sealedHeaderBytes), frameOffset,
                                               "sealed active frame offset overflow")
                    try sealedReadExact(descriptor, offset: offset, bytes: &frameBytes,
                                        count: sealedFrameBytes)
                    let decoded = try sealedDecodeFrame(frameBytes, expectedLSN: pendingLSN,
                                                        expectedRoot: pendingRoot,
                                                        rootScratch: &rootScratch)
                    let sum = pendingValue.addingReportingOverflow(decoded.0)
                    try sealedCheck(!sum.overflow, "sealed pending value overflow")
                    pendingValue = sum.partialValue
                    pendingRoot = decoded.1
                    pendingLSN = try sealedAdd(pendingLSN, 1,
                                               "sealed pending LSN overflow")
                }
                sealedClose(descriptor)
            } catch {
                sealedClose(descriptor)
                throw error
            }
        }
        try sealedCheck(pendingLSN > 0, "sealed pending LSN underflow")
        return SealedRecoveryResult(manifest: manifest, value: value, root: root,
            replayedFrames: replayed,
            activeUnpublishedBytes: activePayloadBytes, activeFrames: activeFrames,
            pendingValue: pendingValue, pendingRoot: pendingRoot,
            pendingLSN: pendingLSN - 1)
    }
}

private enum SealedCrashPhase: String, CaseIterable, Sendable {
    case afterWALFsync
    case afterSealTempFsync
    case afterSealRename
    case afterSealDirsync
    case afterSuccessorTempFsync
    case afterSuccessorRename
    case afterSuccessorDirsync
    case afterManifestTempFsync
    case afterManifestRename
    case afterManifestDirsync
    case afterDurableManifestBeforeCallback
}

private enum SealedCommitStatus: String, Sendable {
    case committed = "COMMITTED"
    case committedGCPending = "COMMITTED_GC_PENDING"
}

private enum SealedIOFault: String, Sendable {
    case walEIO
    case walShortWrite
    case sealENOSPC
    case manifestShortWrite
}

private struct SealedTiming: Sendable {
    var advanceNS: UInt64 = 0
    var walEncodeNS: UInt64 = 0
    var walWriteNS: UInt64 = 0
    var rescheduleNS: UInt64 = 0
    var serviceNS: UInt64 = 0
    var sealNS: UInt64 = 0
    var walFsyncNS: UInt64 = 0
    var manifestNS: UInt64 = 0
    var handleSwitchNS: UInt64 = 0
    var durableManifestPublishNS: UInt64 = 0
    var wholeLoopNS: UInt64 = 0

    func json() -> [String: Any] {
        ["advanceNS": advanceNS, "walEncodeNS": walEncodeNS, "walWriteNS": walWriteNS,
         "rescheduleNS": rescheduleNS, "serviceNS": serviceNS, "sealNS": sealNS,
         "walFsyncNS": walFsyncNS, "manifestNS": manifestNS,
         "handleSwitchNS": handleSwitchNS,
         "durableManifestPublishNS": durableManifestPublishNS,
         "wholeLoopNS": wholeLoopNS]
    }
}

private final class SealedStore {
    let directory: String
    private(set) var manifest: SealedManifest
    private(set) var value: Int64
    private(set) var root: SealedDigest
    private(set) var globalLSN: UInt64
    private(set) var timing = SealedTiming()

    private var activeDescriptor: Int32
    private var activeFrameCount: UInt64 = 0
    private var activeHeaderBytes = [UInt8](repeating: 0, count: sealedHeaderBytes)
    private var frameBuffer = [UInt8](repeating: 0, count: sealedFrameBytes)
    private var sealBuffer = [UInt8](repeating: 0, count: sealedSealBytes)
    private var manifestBuffer = [UInt8](repeating: 0, count: sealedManifestBytes)
    private var successorHeader = [UInt8](repeating: 0, count: sealedHeaderBytes)
    private var rootScratch = [UInt8](repeating: 0, count: 48)
    private var serviceScratch = [UInt8](repeating: 0, count: 256)
    private var injectedPhase: SealedCrashPhase?
    private var injectedIOFault: SealedIOFault?
    private var usable = true
    private(set) var recoveryRequired = false

    private init(directory: String, manifest: SealedManifest, value: Int64,
                 root: SealedDigest, descriptor: Int32,
                 header: [UInt8], activeFrameCount: UInt64,
                 globalLSN: UInt64, injectedPhase: SealedCrashPhase?,
                 injectedIOFault: SealedIOFault?) {
        self.directory = directory
        self.manifest = manifest
        self.value = value
        self.root = root
        self.globalLSN = globalLSN
        activeDescriptor = descriptor
        activeHeaderBytes = header
        self.activeFrameCount = activeFrameCount
        self.injectedPhase = injectedPhase
        self.injectedIOFault = injectedIOFault
    }

    deinit { sealedClose(activeDescriptor) }

    private func requireRecovery() {
        sealedClose(activeDescriptor)
        activeDescriptor = -1
        usable = false
        recoveryRequired = true
    }

    private func crashIfRequested(_ phase: SealedCrashPhase) throws {
        if injectedPhase == phase {
            requireRecovery()
            throw SealedInjectedCrash(phase: phase)
        }
    }

    static func create(_ directory: String,
                       crash: SealedCrashPhase? = nil,
                       ioFault: SealedIOFault? = nil,
                       fixtureIdentity: String? = nil) throws -> SealedStore {
        try FileManager.default.createDirectory(atPath: directory,
                                                withIntermediateDirectories: false)
        let identity = fixtureIdentity ?? UUID().uuidString
        var identityBytes = [UInt8](("NEXORA/R005/SEALED-WAL/DISPOSABLE-STORE/" + identity).utf8)
        let store = try sealedHashBytes(identityBytes)
        identityBytes = [UInt8]("NEXORA/R005/SEALED-WAL/INITIAL-ROOT".utf8)
        let rootDomain = try sealedHashBytes(identityBytes)
        var rootSeed = [UInt8](repeating: 0, count: 64)
        sealedPutDigest(store, &rootSeed, 0)
        sealedPutDigest(rootDomain, &rootSeed, 32)
        let initialRoot = try sealedHashBytes(rootSeed)
        var baseBuffer = [UInt8](repeating: 0, count: sealedBaseBytes)
        try sealedEncodeBase(store: store, initialRoot: initialRoot, initialValue: 0,
                             into: &baseBuffer)
        let basePath = directory + "/base.checkpoint"
        try sealedWriteNew(basePath, bytes: baseBuffer, count: sealedBaseBytes, synchronize: true)
        let base = try sealedHashFile(basePath)

        var header = [UInt8](repeating: 0, count: sealedHeaderBytes)
        let firstHeader = SealedHeader(store: store, base: base, parentSeal: .zero,
            initialRoot: initialRoot, segment: 0, epoch: 1, firstLSN: 1,
            parentSegment: sealedNoSegment, schema: sealedSchema,
            engine: sealedEngine, layout: sealedLayout)
        try sealedEncodeHeader(firstHeader, into: &header)
        let activePath = sealedSegmentWAL(directory, 0)
        try sealedWriteNew(activePath, bytes: header, count: sealedHeaderBytes, synchronize: true)
        let initialManifest = SealedManifest(store: store, base: base, tipSeal: .zero,
            tipRoot: initialRoot, activeHeader: try sealedHashBytes(header),
            previousManifest: .zero, generation: 0, tipSegment: sealedNoSegment,
            activeSegment: 0, durableLSN: 0, schema: sealedSchema,
            engine: sealedEngine, layout: sealedLayout, tipEpoch: 0, activeFirstLSN: 1)
        var manifestBuffer = [UInt8](repeating: 0, count: sealedManifestBytes)
        try sealedEncodeManifest(initialManifest, into: &manifestBuffer)
        try sealedWriteNew(sealedManifestPath(directory, 0), bytes: manifestBuffer,
                           count: sealedManifestBytes, synchronize: true)
        try sealedSyncDirectory(directory)
        let descriptor = try sealedOpenAppend(activePath)
        return SealedStore(directory: directory, manifest: initialManifest, value: 0,
                           root: initialRoot, descriptor: descriptor, header: header,
                           activeFrameCount: 0, globalLSN: 0,
                           injectedPhase: crash, injectedIOFault: ioFault)
    }

    static func reopen(_ directory: String,
                       crash: SealedCrashPhase? = nil,
                       ioFault: SealedIOFault? = nil) throws -> SealedStore {
        let recovered = try SealedRecovery.recover(directory)
        var header = [UInt8](repeating: 0, count: sealedHeaderBytes)
        let path = sealedSegmentWAL(directory, recovered.manifest.activeSegment)
        let readDescriptor = try sealedOpenRead(path)
        do {
            try sealedReadExact(readDescriptor, offset: 0, bytes: &header,
                                count: sealedHeaderBytes)
            sealedClose(readDescriptor)
        } catch {
            sealedClose(readDescriptor)
            throw error
        }
        let appendDescriptor = try sealedOpenAppend(path)
        return SealedStore(directory: directory, manifest: recovered.manifest,
                           value: recovered.pendingValue, root: recovered.pendingRoot,
                           descriptor: appendDescriptor, header: header,
                           activeFrameCount: recovered.activeFrames,
                           globalLSN: recovered.pendingLSN, injectedPhase: crash,
                           injectedIOFault: ioFault)
    }

    func append(delta: Int64) throws {
        do {
            try sealedCheck(usable && activeDescriptor >= 0, "sealed append unusable store")
            let nextLSN = try sealedAdd(globalLSN, 1, "sealed global LSN overflow")
            let sum = value.addingReportingOverflow(delta)
            try sealedCheck(!sum.overflow, "sealed live value overflow")

            let advanceStart = nx_now()
            let after = try sealedRootTransition(root, lsn: nextLSN,
                                                 delta: delta, scratch: &rootScratch)
            let advancedValue = sum.partialValue
            timing.advanceNS &+= nx_now() - advanceStart

            let encodeStart = nx_now()
            try sealedEncodeFrame(lsn: nextLSN, delta: delta, before: root,
                                  after: after, into: &frameBuffer)
            timing.walEncodeNS &+= nx_now() - encodeStart
            let writeStart = nx_now()
            if injectedIOFault == .walEIO {
                injectedIOFault = nil
                throw SealedFailure("sealed injected WAL EIO")
            }
            if injectedIOFault == .walShortWrite {
                injectedIOFault = nil
                try sealedWriteAll(activeDescriptor, frameBuffer, count: sealedFrameBytes / 2)
                try sealedSync(activeDescriptor, "sealed injected WAL short write sync")
                throw SealedFailure("sealed injected WAL short write")
            }
            try sealedWriteAll(activeDescriptor, frameBuffer, count: sealedFrameBytes)
            timing.walWriteNS &+= nx_now() - writeStart
            value = advancedValue
            root = after
            globalLSN = nextLSN
            activeFrameCount = try sealedAdd(activeFrameCount, 1,
                                             "sealed active frame count overflow")
        } catch {
            // A possibly partial append invalidates the live handle.  Only a
            // fresh recovery may classify or resume the on-disk suffix.
            requireRecovery()
            throw error
        }
    }

    func rescheduleProbe(_ ordinal: UInt64) throws {
        let start = nx_now()
        var accumulator = ordinal ^ globalLSN
        for step in 0..<32 { accumulator = (accumulator &* 2_862_933_555_777_941_757) &+ UInt64(step) }
        serviceScratch[0] ^= UInt8(truncatingIfNeeded: accumulator)
        timing.rescheduleNS &+= nx_now() - start
    }

    func serviceProbe() throws {
        let start = nx_now()
        sealedPutDigest(root, &serviceScratch, 0)
        sealedPutU64(globalLSN, &serviceScratch, 32)
        sealedPutU64(UInt64(bitPattern: value), &serviceScratch, 40)
        let observed = try sealedHashBytes(serviceScratch, count: 48)
        serviceScratch[63] = UInt8(truncatingIfNeeded: observed.a)
        timing.serviceNS &+= nx_now() - start
    }

    func synchronizeActiveOnly() throws {
        let start = nx_now()
        try sealedSync(activeDescriptor, "sealed active-only WAL sync")
        timing.walFsyncNS &+= nx_now() - start
    }

    func recordWholeLoop(startedAt: UInt64) {
        timing.wholeLoopNS &+= nx_now() - startedAt
    }

    func commit(gcFailure: Bool = false) throws -> SealedCommitStatus {
        var durableManifestPublished = false
        do {
            try sealedCheck(usable && activeDescriptor >= 0 && activeFrameCount > 0,
                            "sealed commit requires active frames")
            let segment = manifest.activeSegment
            try sealedCheck(globalLSN >= manifest.activeFirstLSN,
                            "sealed commit LSN range")

            let walSyncStart = nx_now()
            try sealedSync(activeDescriptor, "sealed WAL fsync")
            timing.walFsyncNS &+= nx_now() - walSyncStart
            try crashIfRequested(.afterWALFsync)

            let sealStart = nx_now()
            let walPath = sealedSegmentWAL(directory, segment)
            let walLength = try sealedFileSize(activeDescriptor)
            let expectedPayloadBytes = try sealedMultiply(activeFrameCount,
                                                           UInt64(sealedFrameBytes),
                                                           "sealed writer payload overflow")
            let expectedWALLength = try sealedAdd(UInt64(sealedHeaderBytes),
                                                  expectedPayloadBytes,
                                                  "sealed writer WAL length overflow")
            try sealedCheck(walLength == expectedWALLength,
                            "sealed writer exact WAL length")
            let sealEpoch = try sealedAdd(segment, 1, "sealed writer epoch overflow")
            let walDigest = try sealedHashFile(walPath)
            let headerDigest = try sealedHashBytes(activeHeaderBytes)
            let seal = SealedSeal(store: manifest.store, base: manifest.base,
                parentSeal: manifest.tipSeal, walDigest: walDigest, terminalRoot: root,
                headerDigest: headerDigest, segment: segment, epoch: sealEpoch,
                firstLSN: manifest.activeFirstLSN, lastLSN: globalLSN,
                byteLength: walLength, frameCount: activeFrameCount,
                schema: sealedSchema, engine: sealedEngine, layout: sealedLayout,
                parentSegment: manifest.tipSegment)
            try sealedEncodeSeal(seal, into: &sealBuffer)
            let sealFinal = sealedSegmentSeal(directory, segment)
            let sealTemporary = sealFinal + ".tmp-" + UUID().uuidString
            if injectedIOFault == .sealENOSPC {
                injectedIOFault = nil
                try sealedWriteNew(sealTemporary, bytes: sealBuffer,
                                   count: sealedSealBytes / 2, synchronize: true)
                throw SealedFailure("sealed injected seal ENOSPC")
            }
            try sealedWriteNew(sealTemporary, bytes: sealBuffer, count: sealedSealBytes,
                               synchronize: true)
            try crashIfRequested(.afterSealTempFsync)
            try sealedRename(sealTemporary, sealFinal)
            try crashIfRequested(.afterSealRename)
            try sealedSyncDirectory(directory)
            try crashIfRequested(.afterSealDirsync)
            let sealDigest = try sealedHashFile(sealFinal)
            timing.sealNS &+= nx_now() - sealStart

            let switchStart = nx_now()
            let successorSegment = try sealedAdd(segment, 1,
                                                  "sealed successor segment overflow")
            let successorEpoch = try sealedAdd(successorSegment, 1,
                                               "sealed successor epoch overflow")
            let successorFirstLSN = try sealedAdd(globalLSN, 1,
                                                   "sealed successor LSN overflow")
            let successor = SealedHeader(store: manifest.store, base: manifest.base,
                parentSeal: sealDigest, initialRoot: root, segment: successorSegment,
                epoch: successorEpoch, firstLSN: successorFirstLSN,
                parentSegment: segment, schema: sealedSchema,
                engine: sealedEngine, layout: sealedLayout)
            try sealedEncodeHeader(successor, into: &successorHeader)
            let successorFinal = sealedSegmentWAL(directory, successorSegment)
            let successorTemporary = successorFinal + ".tmp-" + UUID().uuidString
            try sealedWriteNew(successorTemporary, bytes: successorHeader,
                               count: sealedHeaderBytes, synchronize: true)
            try crashIfRequested(.afterSuccessorTempFsync)
            try sealedRename(successorTemporary, successorFinal)
            try crashIfRequested(.afterSuccessorRename)
            try sealedSyncDirectory(directory)
            try crashIfRequested(.afterSuccessorDirsync)
            sealedClose(activeDescriptor)
            activeDescriptor = -1
            activeDescriptor = try sealedOpenAppend(successorFinal)
            timing.handleSwitchNS &+= nx_now() - switchStart

            let manifestStart = nx_now()
            let nextGeneration = try sealedAdd(manifest.generation, 1,
                                               "sealed manifest generation overflow")
            let previousManifestDigest = try sealedHashFile(
                sealedManifestPath(directory, manifest.generation))
            let nextManifest = SealedManifest(store: manifest.store, base: manifest.base,
                tipSeal: sealDigest, tipRoot: root,
                activeHeader: try sealedHashBytes(successorHeader),
                previousManifest: previousManifestDigest, generation: nextGeneration,
                tipSegment: segment, activeSegment: successorSegment,
                durableLSN: globalLSN, schema: sealedSchema,
                engine: sealedEngine, layout: sealedLayout, tipEpoch: sealEpoch,
                activeFirstLSN: successorFirstLSN)
            try sealedEncodeManifest(nextManifest, into: &manifestBuffer)
            let manifestFinal = sealedManifestPath(directory, nextGeneration)
            let manifestTemporary = manifestFinal + ".tmp-" + UUID().uuidString
            if injectedIOFault == .manifestShortWrite {
                injectedIOFault = nil
                try sealedWriteNew(manifestTemporary, bytes: manifestBuffer,
                                   count: sealedManifestBytes / 2, synchronize: true)
                throw SealedFailure("sealed injected manifest short write")
            }
            try sealedWriteNew(manifestTemporary, bytes: manifestBuffer,
                               count: sealedManifestBytes, synchronize: true)
            try crashIfRequested(.afterManifestTempFsync)
            try sealedRename(manifestTemporary, manifestFinal)
            try crashIfRequested(.afterManifestRename)
            timing.manifestNS &+= nx_now() - manifestStart

            let acknowledgementStart = nx_now()
            try sealedSyncDirectory(directory)
            durableManifestPublished = true
            timing.durableManifestPublishNS &+= nx_now() - acknowledgementStart
            try crashIfRequested(.afterManifestDirsync)
            manifest = nextManifest
            activeHeaderBytes = successorHeader
            activeFrameCount = 0
            try crashIfRequested(.afterDurableManifestBeforeCallback)

            do {
                _ = try SealedGarbageCollector.collect(directory, injectFailure: gcFailure)
                return .committed
            } catch {
                // The manifest is already durably published. Cleanup cannot turn a
                // committed save into a failed save.
                return .committedGCPending
            }
        } catch {
            if !durableManifestPublished { requireRecovery() }
            throw error
        }
    }
}

private enum SealedGarbageCollector {
    static func collect(_ directory: String, injectFailure: Bool) throws -> Int {
        if injectFailure { throw SealedFailure("sealed injected GC failure") }
        let generations = try SealedRecovery.manifestGenerations(directory)
        try sealedCheck(!generations.isEmpty, "sealed GC missing retained manifest")
        var buffer = [UInt8](repeating: 0, count: sealedManifestBytes)
        var reachable = Set<String>()
        reachable.insert("base.checkpoint")
        for generation in generations {
            let manifest = try SealedRecovery.loadManifest(directory, generation: generation,
                                                           buffer: &buffer)
            reachable.insert("manifest-\(generation).bin")
            reachable.insert("segment-\(manifest.activeSegment).wal")
            if manifest.tipSegment != sealedNoSegment {
                for segment in 0...manifest.tipSegment {
                    reachable.insert("segment-\(segment).wal")
                    reachable.insert("segment-\(segment).seal")
                }
            }
        }
        var removed = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: directory) {
            let isWAL = sealedParseNumber(name, prefix: "segment-", suffix: ".wal") != nil
            let isSeal = sealedParseNumber(name, prefix: "segment-", suffix: ".seal") != nil
            guard (isWAL || isSeal) && !reachable.contains(name) else { continue }
            try FileManager.default.removeItem(atPath: directory + "/" + name)
            removed += 1
        }
        if removed > 0 { try sealedSyncDirectory(directory) }
        return removed
    }
}

private enum SealedCompactorAdmissionCheck {
    // Read-only preflight comparison.  This is not an atomic CAS and cannot
    // authorize a later publication without a separate serialization design.
    static func matchesExpectedTip(_ directory: String,
                                   expectedGeneration: UInt64,
                                   expectedTip: SealedDigest) throws -> Bool {
        let recovered = try SealedRecovery.recover(directory)
        return recovered.manifest.generation == expectedGeneration &&
            recovered.manifest.tipSeal == expectedTip
    }
}

private func sealedTemporaryDirectory(_ root: URL, _ label: String) throws -> String {
    let url = root.appendingPathComponent(label + "-" + UUID().uuidString,
                                           isDirectory: true)
    return url.path
}

private func sealedBuildFixture(_ directory: String, segments: Int,
                                framesPerSegment: Int = 2,
                                gcFailureOnLast: Bool = false) throws -> (SealedCommitStatus?, Int64, SealedDigest) {
    try sealedCheck(segments >= 0 && framesPerSegment > 0, "sealed fixture bounds")
    let store = try SealedStore.create(directory)
    var status: SealedCommitStatus? = nil
    if segments > 0 {
        for segment in 0..<segments {
            for frame in 0..<framesPerSegment {
                let delta = Int64((segment + 1) * 101 + frame * 7)
                try store.append(delta: delta)
                if frame & 1 == 1 { try store.rescheduleProbe(UInt64(segment * 100 + frame)) }
                try store.serviceProbe()
            }
            status = try store.commit(gcFailure: gcFailureOnLast && segment == segments - 1)
        }
    }
    return (status, store.value, store.root)
}

private func sealedExpectRecoveryFailure(_ label: String, directory: String,
                                         requestedGeneration: UInt64? = nil) throws -> Bool {
    var failedClosed = false
    do {
        _ = try SealedRecovery.recover(directory, requestedGeneration: requestedGeneration)
    } catch {
        failedClosed = true
    }
    try sealedCheck(failedClosed, "sealed negative case unexpectedly recovered: \(label)")
    return true
}

private func sealedArbitraryDigest(_ label: String) throws -> SealedDigest {
    try sealedHashBytes([UInt8](label.utf8))
}

private func sealedRewriteTipSealAndManifest(
    _ directory: String,
    generation: UInt64,
    mutateSeal: (inout [UInt8]) throws -> Void,
    mutateManifest: ((inout [UInt8]) throws -> Void)? = nil
) throws {
    try sealedCheck(generation > 0, "sealed corruption fixture generation")
    let segment = generation - 1
    let sealPath = sealedSegmentSeal(directory, segment)
    var sealBytes = [UInt8](repeating: 0, count: sealedSealBytes)
    try sealedReadFixed(sealPath, expected: sealedSealBytes, buffer: &sealBytes)
    try mutateSeal(&sealBytes)
    let sealSelfDigest = try sealedHashBytes(sealBytes, count: 288)
    sealedPutDigest(sealSelfDigest, &sealBytes, 288)
    try sealedRewrite(sealPath, bytes: sealBytes, count: sealedSealBytes)
    let newSealDigest = try sealedHashFile(sealPath)

    let manifestPath = sealedManifestPath(directory, generation)
    var manifestBytes = [UInt8](repeating: 0, count: sealedManifestBytes)
    try sealedReadFixed(manifestPath, expected: sealedManifestBytes, buffer: &manifestBytes)
    sealedPutDigest(newSealDigest, &manifestBytes, 80)
    if let mutateManifest { try mutateManifest(&manifestBytes) }
    let manifestSelfDigest = try sealedHashBytes(manifestBytes, count: 288)
    sealedPutDigest(manifestSelfDigest, &manifestBytes, 288)
    try sealedRewrite(manifestPath, bytes: manifestBytes, count: sealedManifestBytes)
    try sealedSyncDirectory(directory)
}

private func sealedCorruptionCases(_ root: URL) throws -> [String: Any] {
    var results: [String: Any] = [:]

    do {
        let directory = try sealedTemporaryDirectory(root, "whole-frame-delete")
        _ = try sealedBuildFixture(directory, segments: 1, framesPerSegment: 3)
        let path = sealedSegmentWAL(directory, 0)
        let size = try sealedFileSize(path)
        try sealedTruncate(path, bytes: size - UInt64(sealedFrameBytes))
        results["wholeFrameSuffixDeletion"] = try sealedExpectRecoveryFailure(
            "whole-frame suffix deletion", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "torn-frame")
        _ = try sealedBuildFixture(directory, segments: 1, framesPerSegment: 2)
        let path = sealedSegmentWAL(directory, 0)
        try sealedTruncate(path, bytes: try sealedFileSize(path) - 7)
        results["tornFrame"] = try sealedExpectRecoveryFailure("torn frame", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "torn-seal")
        _ = try sealedBuildFixture(directory, segments: 1)
        let path = sealedSegmentSeal(directory, 0)
        try sealedTruncate(path, bytes: UInt64(sealedSealBytes - 9))
        results["tornSeal"] = try sealedExpectRecoveryFailure("torn seal", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "wal-seal-mismatch")
        _ = try sealedBuildFixture(directory, segments: 1)
        let wrong = try sealedArbitraryDigest("wrong wal digest")
        try sealedRewriteTipSealAndManifest(directory, generation: 1) { seal in
            sealedPutDigest(wrong, &seal, 112)
        }
        results["sealWALMismatch"] = try sealedExpectRecoveryFailure(
            "seal/WAL mismatch", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "wrong-parent")
        _ = try sealedBuildFixture(directory, segments: 1)
        let wrong = try sealedArbitraryDigest("wrong parent")
        try sealedRewriteTipSealAndManifest(directory, generation: 1) { seal in
            sealedPutDigest(wrong, &seal, 80)
        }
        results["wrongParent"] = try sealedExpectRecoveryFailure("wrong parent", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "wrong-base")
        _ = try sealedBuildFixture(directory, segments: 1)
        let wrong = try sealedArbitraryDigest("wrong base")
        try sealedRewriteTipSealAndManifest(directory, generation: 1) { seal in
            sealedPutDigest(wrong, &seal, 48)
        }
        results["wrongBase"] = try sealedExpectRecoveryFailure("wrong base", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "wrong-version")
        _ = try sealedBuildFixture(directory, segments: 1)
        try sealedRewriteTipSealAndManifest(directory, generation: 1) { seal in
            sealedPutU32(sealedSchema + 1, &seal, 256)
        }
        results["wrongVersion"] = try sealedExpectRecoveryFailure(
            "wrong schema version", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "wrong-root")
        _ = try sealedBuildFixture(directory, segments: 1)
        let wrong = try sealedArbitraryDigest("wrong terminal root")
        try sealedRewriteTipSealAndManifest(directory, generation: 1,
            mutateSeal: { seal in sealedPutDigest(wrong, &seal, 144) },
            mutateManifest: { manifest in sealedPutDigest(wrong, &manifest, 112) })
        results["wrongRoot"] = try sealedExpectRecoveryFailure("wrong root", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "missing-manifest")
        _ = try sealedBuildFixture(directory, segments: 1)
        try FileManager.default.removeItem(atPath: sealedManifestPath(directory, 1))
        try sealedSyncDirectory(directory)
        results["missingLatestManifest"] = try sealedExpectRecoveryFailure(
            "missing latest manifest", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "stale-manifest")
        _ = try sealedBuildFixture(directory, segments: 2)
        results["staleManifestGeneration"] = try sealedExpectRecoveryFailure(
            "stale manifest generation", directory: directory, requestedGeneration: 1)
        try FileManager.default.removeItem(atPath: sealedManifestPath(directory, 2))
        try sealedSyncDirectory(directory)
        results["rolledBackManifestWithDescendant"] = try sealedExpectRecoveryFailure(
            "rolled-back manifest with descendant", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "clean-rollback-deletion")
        _ = try sealedBuildFixture(directory, segments: 2)
        let latest = try SealedRecovery.recover(directory)
        try FileManager.default.removeItem(atPath: sealedManifestPath(directory, 2))
        try FileManager.default.removeItem(atPath: sealedSegmentSeal(directory, 1))
        try FileManager.default.removeItem(atPath: sealedSegmentWAL(directory, 2))
        try sealedSyncDirectory(directory)
        let rolledBack = try SealedRecovery.recover(directory)
        try sealedCheck(latest.manifest.generation == 2 &&
                        rolledBack.manifest.generation == 1 &&
                        rolledBack.manifest.durableLSN < latest.manifest.durableLSN &&
                        rolledBack.root != latest.root &&
                        rolledBack.pendingRoot == latest.root &&
                        rolledBack.pendingLSN == latest.manifest.durableLSN,
                        "sealed clean rollback gap fixture did not expose authority loss")
        results["cleanRollbackDeletion"] = [
            "status": "EXPECTED_KNOWN_GAP",
            "reason": "NO_DURABLE_CURRENT_AUTHORITY",
            "deletedEntries": ["manifest-2.bin", "segment-1.seal", "segment-2.wal"],
            "latestGenerationBeforeDeletion": latest.manifest.generation,
            "acceptedDurableGenerationAfterDeletion": rolledBack.manifest.generation,
            "formerCommittedTailReclassifiedAsPending": true
        ]
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "whole-seal-strip")
        _ = try sealedBuildFixture(directory, segments: 1)
        try FileManager.default.removeItem(atPath: sealedSegmentSeal(directory, 0))
        try sealedSyncDirectory(directory)
        results["wholeSealStrip"] = try sealedExpectRecoveryFailure(
            "whole seal strip", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "append-after-seal")
        _ = try sealedBuildFixture(directory, segments: 1)
        let suffix = [UInt8](repeating: 0x6d, count: sealedFrameBytes)
        try sealedAppendBytes(sealedSegmentWAL(directory, 0), bytes: suffix,
                              count: suffix.count)
        results["appendAfterSeal"] = try sealedExpectRecoveryFailure(
            "append after seal", directory: directory)
    }

    do {
        let first = try sealedTemporaryDirectory(root, "cross-store-first")
        let second = try sealedTemporaryDirectory(root, "cross-store-second")
        _ = try sealedBuildFixture(first, segments: 1, framesPerSegment: 2)
        _ = try sealedBuildFixture(second, segments: 1, framesPerSegment: 2)
        let firstRecovered = try SealedRecovery.recover(first)
        let secondRecovered = try SealedRecovery.recover(second)
        try sealedCheck(firstRecovered.manifest.store != secondRecovered.manifest.store,
                        "sealed cross-store fixtures must be unique")
        try sealedCopyRange(source: sealedSegmentWAL(second, 0),
                            sourceOffset: UInt64(sealedHeaderBytes),
                            destination: sealedSegmentWAL(first, 0),
                            destinationOffset: UInt64(sealedHeaderBytes),
                            count: sealedFrameBytes)
        let newWALDigest = try sealedHashFile(sealedSegmentWAL(first, 0))
        try sealedRewriteTipSealAndManifest(first, generation: 1) { seal in
            sealedPutDigest(newWALDigest, &seal, 112)
        }
        results["crossStoreValidFrameSplice"] = try sealedExpectRecoveryFailure(
            "cross-store valid frame splice", directory: first)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "successor-header-loss")
        _ = try sealedBuildFixture(directory, segments: 1)
        try sealedTruncate(sealedSegmentWAL(directory, 1), bytes: 64)
        results["successorHeaderLoss"] = try sealedExpectRecoveryFailure(
            "successor header loss", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "successor-entry-delete")
        _ = try sealedBuildFixture(directory, segments: 1)
        try FileManager.default.removeItem(atPath: sealedSegmentWAL(directory, 1))
        try sealedSyncDirectory(directory)
        results["successorDirectoryEntryDeletion"] = try sealedExpectRecoveryFailure(
            "successor directory entry deletion", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "fork-successor")
        _ = try sealedBuildFixture(directory, segments: 1)
        try FileManager.default.copyItem(atPath: sealedSegmentWAL(directory, 1),
                                         toPath: sealedSegmentWAL(directory, 2))
        try sealedSyncDirectory(directory)
        results["forkSuccessor"] = try sealedExpectRecoveryFailure(
            "fork successor", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "duplicate-segment")
        _ = try sealedBuildFixture(directory, segments: 1)
        try FileManager.default.copyItem(atPath: sealedSegmentWAL(directory, 1),
                                         toPath: directory + "/segment-01.wal")
        try sealedSyncDirectory(directory)
        results["duplicateSegment"] = try sealedExpectRecoveryFailure(
            "duplicate segment", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "reordered-segment")
        _ = try sealedBuildFixture(directory, segments: 2)
        let first = sealedSegmentWAL(directory, 0)
        let second = sealedSegmentWAL(directory, 1)
        let temporary = directory + "/segment-swap.tmp"
        try FileManager.default.moveItem(atPath: first, toPath: temporary)
        try FileManager.default.moveItem(atPath: second, toPath: first)
        try FileManager.default.moveItem(atPath: temporary, toPath: second)
        try sealedSyncDirectory(directory)
        results["reorderedSegment"] = try sealedExpectRecoveryFailure(
            "reordered segment", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "future-segment")
        _ = try sealedBuildFixture(directory, segments: 1)
        let future = [UInt8](repeating: 0, count: sealedHeaderBytes)
        try sealedWriteNew(sealedSegmentWAL(directory, 99), bytes: future,
                           count: future.count, synchronize: true)
        try sealedSyncDirectory(directory)
        results["futureSegment"] = try sealedExpectRecoveryFailure(
            "future segment", directory: directory)
    }
    return results
}

private func sealedCrashMatrix(_ root: URL) throws -> [[String: Any]] {
    var rows: [[String: Any]] = []
    for phase in SealedCrashPhase.allCases {
        let directory = try sealedTemporaryDirectory(root, "crash-" + phase.rawValue)
        let store = try SealedStore.create(directory, crash: phase)
        let durableRoot = store.manifest.tipRoot
        let durableValue = store.value
        let durableLSN = store.manifest.durableLSN
        let durableGeneration = store.manifest.generation
        try store.append(delta: 41)
        try store.append(delta: -3)
        let candidateRoot = store.root
        let candidateValue = store.value
        let candidateLSN = store.globalLSN
        let candidateGeneration = try sealedAdd(durableGeneration, 1,
                                                "sealed crash candidate generation overflow")
        var injected = false
        do {
            _ = try store.commit()
        } catch let crash as SealedInjectedCrash {
            try sealedCheck(crash.phase == phase, "sealed wrong injected crash phase")
            injected = true
        }
        try sealedCheck(injected, "sealed crash phase not reached: \(phase.rawValue)")
        try sealedCheck(store.recoveryRequired,
                        "sealed crash did not invalidate live store: \(phase.rawValue)")

        var outcome = ""
        var recoveredResult: SealedRecoveryResult?
        do {
            recoveredResult = try SealedRecovery.recover(directory)
        } catch {
            outcome = "FAIL_CLOSED"
        }
        if let recovered = recoveredResult {
            let oldExact = recovered.root == durableRoot &&
                recovered.value == durableValue &&
                recovered.manifest.durableLSN == durableLSN &&
                recovered.manifest.generation == durableGeneration
            let newExact = recovered.root == candidateRoot &&
                recovered.value == candidateValue &&
                recovered.manifest.durableLSN == candidateLSN &&
                recovered.manifest.generation == candidateGeneration
            // This validation deliberately sits outside the recovery catch: an
            // unrelated state must fail the micro instead of being relabeled as
            // an acceptable fail-closed recovery.
            try sealedCheck(oldExact || newExact,
                            "sealed crash recovered unbound root/value/LSN/generation")
            outcome = oldExact ? "OLD_DURABLE_TIP_EXACT" : "NEW_DURABLE_TIP_EXACT"
        }
        let expected: [String]
        switch phase {
        case .afterWALFsync, .afterSealTempFsync:
            expected = ["OLD_DURABLE_TIP_EXACT"]
        case .afterSealRename, .afterSealDirsync, .afterSuccessorTempFsync,
             .afterSuccessorRename, .afterSuccessorDirsync, .afterManifestTempFsync:
            expected = ["FAIL_CLOSED"]
        case .afterManifestRename:
            // A real power loss before directory fsync may expose either the old
            // namespace (which this design rejects due to the orphan seal) or
            // the new manifest. The in-process fault normally observes new.
            expected = ["NEW_DURABLE_TIP_EXACT", "FAIL_CLOSED"]
        case .afterManifestDirsync, .afterDurableManifestBeforeCallback:
            expected = ["NEW_DURABLE_TIP_EXACT"]
        }
        try sealedCheck(expected.contains(outcome),
                        "sealed crash matrix outcome \(phase.rawValue): \(outcome)")
        rows.append(["phase": phase.rawValue, "outcome": outcome,
                     "comparedFields": ["root", "value", "durableLSN", "generation"],
                     "allowedOutcomes": expected])
    }
    return rows
}

private func sealedRequireInvalidatedHandle(_ store: SealedStore,
                                            _ label: String) throws {
    try sealedCheck(store.recoveryRequired, "sealed failure did not require recovery: \(label)")
    var rejectedReuse = false
    do {
        try store.append(delta: 1)
    } catch {
        rejectedReuse = true
    }
    try sealedCheck(rejectedReuse && store.recoveryRequired,
                    "sealed invalidated handle was reusable: \(label)")
}

private func sealedIOFailureCases(_ root: URL) throws -> [String: Any] {
    var results: [String: Any] = [:]

    do {
        let directory = try sealedTemporaryDirectory(root, "io-wal-eio")
        let store = try SealedStore.create(directory, ioFault: .walEIO)
        var failed = false
        do { try store.append(delta: 7) } catch { failed = true }
        try sealedCheck(failed, "sealed WAL EIO not injected")
        try sealedRequireInvalidatedHandle(store, "WAL EIO")
        let recovered = try SealedRecovery.recover(directory)
        try sealedCheck(recovered.manifest.generation == 0 && recovered.value == 0 &&
                        recovered.activeFrames == 0, "sealed WAL EIO recovery")
        results["EIO"] = "NO_COMMIT_OLD_DURABLE_TIP_EXACT"
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "io-wal-short")
        let store = try SealedStore.create(directory, ioFault: .walShortWrite)
        var failed = false
        do { try store.append(delta: 7) } catch { failed = true }
        try sealedCheck(failed, "sealed WAL short write not injected")
        try sealedRequireInvalidatedHandle(store, "WAL short write")
        results["shortWrite"] = try sealedExpectRecoveryFailure(
            "torn active WAL short write", directory: directory)
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "io-seal-enospc")
        let store = try SealedStore.create(directory, ioFault: .sealENOSPC)
        try store.append(delta: 17)
        let pendingRoot = store.root
        var failed = false
        do { _ = try store.commit() } catch { failed = true }
        try sealedCheck(failed, "sealed seal ENOSPC not injected")
        try sealedRequireInvalidatedHandle(store, "seal ENOSPC")
        let recovered = try SealedRecovery.recover(directory)
        try sealedCheck(recovered.manifest.generation == 0 && recovered.value == 0 &&
                        recovered.activeFrames == 1 && recovered.pendingRoot == pendingRoot,
                        "sealed seal ENOSPC recovery")
        results["ENOSPC"] = "NO_COMMIT_OLD_DURABLE_TIP_PLUS_VALID_PENDING_FRAME"
    }

    do {
        let directory = try sealedTemporaryDirectory(root, "io-manifest-short")
        let store = try SealedStore.create(directory, ioFault: .manifestShortWrite)
        try store.append(delta: 23)
        var failed = false
        do { _ = try store.commit() } catch { failed = true }
        try sealedCheck(failed, "sealed manifest short write not injected")
        try sealedRequireInvalidatedHandle(store, "manifest short write")
        results["manifestShortWriteAfterSeal"] = try sealedExpectRecoveryFailure(
            "manifest short write after seal", directory: directory)
    }
    results["modeledPrePublicationFailuresInvalidateLiveHandle"] = true
    return results
}

private func sealedRecoverAppendSealRecover(_ root: URL) throws -> [String: Any] {
    let directory = try sealedTemporaryDirectory(root, "recover-append-seal-recover")
    do {
        let store = try SealedStore.create(directory)
        try store.append(delta: 5)
        try store.append(delta: 8)
        try store.synchronizeActiveOnly()
    }
    let firstRecovery = try SealedRecovery.recover(directory)
    try sealedCheck(firstRecovery.manifest.generation == 0 &&
                    firstRecovery.activeFrames == 2 && firstRecovery.value == 0 &&
                    firstRecovery.pendingValue == 13,
                    "sealed first recover pending tail")
    do {
        let resumed = try SealedStore.reopen(directory)
        try sealedCheck(resumed.globalLSN == 2 && resumed.value == 13 &&
                        resumed.root == firstRecovery.pendingRoot,
                        "sealed reopen append state")
        try resumed.append(delta: -4)
        try sealedCheck(try resumed.commit() == .committed,
                        "sealed resumed commit")
    }
    let secondRecovery = try SealedRecovery.recover(directory)
    try sealedCheck(secondRecovery.manifest.generation == 1 &&
                    secondRecovery.replayedFrames == 3 && secondRecovery.value == 9 &&
                    secondRecovery.activeFrames == 0 &&
                    secondRecovery.pendingRoot == secondRecovery.root,
                    "sealed recover append seal recover exactness")
    return ["firstRecoveryDurableValue": firstRecovery.value,
            "firstRecoveryPendingValue": firstRecovery.pendingValue,
            "resumedAtGlobalLSN": firstRecovery.pendingLSN,
            "secondRecoveryDurableValue": secondRecovery.value,
            "secondRecoveryFrames": secondRecovery.replayedFrames,
            "exact": true]
}

private func sealedRecoveryCadence(_ root: URL) throws -> [[String: Any]] {
    let counts = [0, 1, 5, 10, 25]
    var rows: [[String: Any]] = []
    for count in counts {
        let directory = try sealedTemporaryDirectory(root, "recovery-\(count)")
        let fixture = try sealedBuildFixture(directory, segments: count, framesPerSegment: 1)
        let start = nx_now()
        let recovered = try SealedRecovery.recover(directory)
        let elapsed = nx_now() - start
        try sealedCheck(recovered.manifest.generation == UInt64(count) &&
                        recovered.replayedFrames == UInt64(count) &&
                        recovered.value == fixture.1 && recovered.root == fixture.2 &&
                        recovered.activeUnpublishedBytes == 0,
                        "sealed bounded recovery exactness")
        rows.append(["segments": count, "frames": recovered.replayedFrames,
                     "elapsedNS": elapsed, "selectedPresentTipExact": true,
                     "streaming": true])
    }
    return rows
}

private func sealedAdmissionCheckAndGCCases(_ root: URL) throws -> [String: Any] {
    let admissionDirectory = try sealedTemporaryDirectory(root, "compactor-admission")
    let store = try SealedStore.create(admissionDirectory)
    try store.append(delta: 9)
    try sealedCheck(try store.commit() == .committed,
                    "sealed first admission fixture commit")
    let staleGeneration = store.manifest.generation
    let staleTip = store.manifest.tipSeal
    try store.append(delta: 12)
    try sealedCheck(try store.commit() == .committed,
                    "sealed second admission fixture commit")
    let before = try sealedHashFile(
        sealedManifestPath(admissionDirectory, store.manifest.generation))
    let staleAllowed = try SealedCompactorAdmissionCheck.matchesExpectedTip(
        admissionDirectory, expectedGeneration: staleGeneration, expectedTip: staleTip)
    let currentAllowed = try SealedCompactorAdmissionCheck.matchesExpectedTip(
        admissionDirectory, expectedGeneration: store.manifest.generation,
        expectedTip: store.manifest.tipSeal)
    let after = try sealedHashFile(
        sealedManifestPath(admissionDirectory, store.manifest.generation))
    let admissionRecovery = try SealedRecovery.recover(admissionDirectory)
    try sealedCheck(!staleAllowed && currentAllowed && before == after &&
                    admissionRecovery.manifest.generation == store.manifest.generation,
                    "sealed stale compactor admission check")

    let pendingDirectory = try sealedTemporaryDirectory(root, "gc-pending")
    let pendingStore = try SealedStore.create(pendingDirectory)
    try pendingStore.append(delta: 101)
    try pendingStore.append(delta: 108)
    let pendingStatus = try pendingStore.commit(gcFailure: true)
    let pendingValue = pendingStore.value
    let pendingRoot = pendingStore.root
    try sealedCheck(pendingStatus == .committedGCPending &&
                    !pendingStore.recoveryRequired,
                    "sealed GC pending status poisoned committed handle")
    let pendingRecovery = try SealedRecovery.recover(pendingDirectory)
    try sealedCheck(pendingRecovery.value == pendingValue &&
                    pendingRecovery.root == pendingRoot,
                    "sealed GC failure lost committed tip")

    var stray = [UInt8](repeating: 0xa5, count: 64)
    let strayWAL = sealedSegmentWAL(pendingDirectory, 999)
    let straySeal = sealedSegmentSeal(pendingDirectory, 999)
    try sealedWriteNew(strayWAL, bytes: stray, count: stray.count, synchronize: true)
    stray[0] = 0x5a
    try sealedWriteNew(straySeal, bytes: stray, count: stray.count, synchronize: true)
    try sealedSyncDirectory(pendingDirectory)
    let removed = try SealedGarbageCollector.collect(pendingDirectory, injectFailure: false)
    try sealedCheck(removed == 2 && !FileManager.default.fileExists(atPath: strayWAL) &&
                    !FileManager.default.fileExists(atPath: straySeal) &&
                    FileManager.default.fileExists(atPath: sealedSegmentWAL(pendingDirectory, 0)) &&
                    FileManager.default.fileExists(atPath: sealedSegmentSeal(pendingDirectory, 0)) &&
                    FileManager.default.fileExists(atPath: sealedSegmentWAL(pendingDirectory, 1)),
                    "sealed reachability GC")
    let afterGC = try SealedRecovery.recover(pendingDirectory)
    try sealedCheck(afterGC.root == pendingRoot, "sealed GC changed reachable tip")
    return [
        "staleCompactorAdmissionCheckRejected": !staleAllowed,
        "currentCompactorAdmissionCheckAccepted": currentAllowed,
        "admissionCheckNoManifestMutation": before == after,
        "atomicCAS": "NOT_IMPLEMENTED",
        "compactionPayloadBuild": "NOT_IMPLEMENTED",
        "compactionPublication": "NOT_IMPLEMENTED",
        "cleanupFailureStatus": pendingStatus.rawValue,
        "cleanupFailureKeepsCommittedTip": true,
        "cleanupFailureKeepsLiveHandleUsable": !pendingStore.recoveryRequired,
        "GCReachabilityRemovedUnreferenced": removed,
        "GCUsesRetainedManifestReachability": true,
        "GCDeletesByEpochAlone": false,
        "classification": "NON_ATOMIC_ADMISSION_CHECK_AND_GC_ONLY_NOT_COMPACTION_PROOF"
    ]
}

private func sealedTimedLeg(_ root: URL, label: String, save: Bool,
                            fixtureIdentity: String) throws -> [String: Any] {
    let directory = try sealedTemporaryDirectory(root, "profile-" + label)
    let store = try SealedStore.create(directory, fixtureIdentity: fixtureIdentity)
    let wholeStart = nx_now()
    for call in 0..<32 {
        let sign: Int64 = call & 1 == 0 ? 1 : -1
        try store.append(delta: sign * Int64(call + 3))
        if call % 7 == 0 { try store.rescheduleProbe(UInt64(call)) }
        try store.serviceProbe()
        if save && (call + 1) % 8 == 0 {
            try sealedCheck(try store.commit() == .committed, "sealed profile commit")
        }
    }
    if !save { try store.synchronizeActiveOnly() }
    store.recordWholeLoop(startedAt: wholeStart)
    let recovered = try SealedRecovery.recover(directory)
    if save {
        try sealedCheck(recovered.root == store.root && recovered.value == store.value &&
                        recovered.manifest.generation == 4,
                        "sealed save profile recovery")
    } else {
        try sealedCheck(recovered.manifest.generation == 0 &&
                        recovered.root == store.manifest.tipRoot &&
                        recovered.activeUnpublishedBytes == UInt64(32 * sealedFrameBytes),
                        "sealed no-save profile durable boundary")
    }
    return ["label": label, "save": save, "calls": 32,
            "committedSegments": save ? 4 : 0,
            "liveGlobalLSN": store.globalLSN,
            "liveValue": store.value,
            "liveRoot": store.root.hex,
            "selectedManifestTipExactWithinPresentDirectory": true,
            "components": store.timing.json()]
}

private func sealedMedian(_ values: [UInt64]) -> UInt64 {
    let sorted = values.sorted()
    return sorted[sorted.count / 2]
}

private func sealedPairedABBA(_ root: URL) throws -> [String: Any] {
    let order = [false, true, true, false]
    var legs: [[String: Any]] = []
    var saveWhole: [UInt64] = []
    var noSaveWhole: [UInt64] = []
    var fixtureRoot: String? = nil
    var fixtureValue: Int64? = nil
    let fixtureIdentity = "paired-abba-fixed-fixture-v1"
    for (index, save) in order.enumerated() {
        let leg = try sealedTimedLeg(root, label: "\(index)-" + (save ? "save" : "no-save"),
                                     save: save, fixtureIdentity: fixtureIdentity)
        legs.append(leg)
        guard let components = leg["components"] as? [String: Any],
              let whole = components["wholeLoopNS"] as? UInt64,
              let root = leg["liveRoot"] as? String,
              let value = leg["liveValue"] as? Int64 else {
            throw SealedFailure("sealed profile component shape")
        }
        if let fixtureRoot {
            try sealedCheck(fixtureRoot == root && fixtureValue == value,
                            "sealed ABBA logical fixture drift")
        } else {
            fixtureRoot = root
            fixtureValue = value
        }
        if save { saveWhole.append(whole) } else { noSaveWhole.append(whole) }
    }
    let saveMedian = sealedMedian(saveWhole), noSaveMedian = sealedMedian(noSaveWhole)
    let ratio = noSaveMedian == 0 ? 0.0 : Double(saveMedian) / Double(noSaveMedian)
    return ["order": ["no-save", "save", "save", "no-save"],
            "sameLogicalFixture": true, "finalLiveRoot": fixtureRoot ?? "missing",
            "finalLiveValue": fixtureValue ?? 0, "legs": legs,
            "saveWholeLoopMedianNS": saveMedian,
            "noSaveWholeLoopMedianNS": noSaveMedian,
            "diagnosticWholeLoopRatio": ratio,
            "classification": "BOUNDED_SYNTHETIC_DIAGNOSTIC_NOT_C"]
}

func sealedWALMicro() throws -> [String: Any] {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nxr-sealed-wal-micro-" + UUID().uuidString,
                                isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }

    let happyDirectory = try sealedTemporaryDirectory(root, "happy")
    let happyFixture = try sealedBuildFixture(happyDirectory, segments: 3,
                                              framesPerSegment: 3)
    let happy = try SealedRecovery.recover(happyDirectory)
    try sealedCheck(happyFixture.0 == .committed && happy.value == happyFixture.1 &&
                    happy.root == happyFixture.2 && happy.replayedFrames == 9 &&
                    happy.manifest.generation == 3 &&
                    happy.activeUnpublishedBytes == 0,
                    "sealed happy-chain exactness")

    let corruption = try sealedCorruptionCases(root)
    let crashMatrix = try sealedCrashMatrix(root)
    let ioFailures = try sealedIOFailureCases(root)
    let resumedChain = try sealedRecoverAppendSealRecover(root)
    let recoveryCadence = try sealedRecoveryCadence(root)
    let admissionCheckAndGC = try sealedAdmissionCheckAndGCCases(root)
    let paired = try sealedPairedABBA(root)

    return [
        "status": "diagnostic-partial",
        "acceptance": false,
        "decision": "SEALED_WAL_MICRO_PARTIAL_BLOCKED",
        "integrationDecision": "NO_GO_INTEGRATION_C100",
        "integrationEligible": false,
        "scope": "Disposable bounded disk-native sealed-WAL protocol micro; no runtime source, A/B/K/C, H1M, save-contract, product, UI, IPA, or device qualification.",
        "format": [
            "headerBytes": sealedHeaderBytes,
            "frameBytes": sealedFrameBytes,
            "sealBytes": sealedSealBytes,
            "manifestBytes": sealedManifestBytes,
            "baseBytes": sealedBaseBytes,
            "globalLSN": true, "storeIdentifiersUniqueByDefault": true,
            "initialRootBoundToStore": true,
            "sealBindings": ["exactByteLength", "frameCount", "epoch", "firstLSN",
                             "lastLSN", "globalLSN",
                             "parentSeal", "baseCheckpoint", "store", "schema",
                             "engine", "layout", "terminalRoot", "WALDigest",
                             "headerDigest"],
            "immutableManifestGenerations": true,
            "latestGenerationAuthority": "NOT_PROVED_NO_DURABLE_CURRENT",
            "durableCURRENT": "NOT_IMPLEMENTED"
        ],
        "publicationOrder": ["WAL_fsync", "seal_temp_fsync", "seal_rename",
                             "seal_dirsync", "successor_temp_fsync",
                             "successor_rename", "successor_dirsync",
                             "manifest_temp_fsync", "manifest_rename",
                             "manifest_dirsync", "caller_commit_callback"],
        "happyChain": ["segments": 3, "frames": happy.replayedFrames,
                       "generation": happy.manifest.generation,
                       "selectedManifestTipExactWithinPresentDirectory": true],
        "corruption": corruption,
        "crashMatrix": crashMatrix,
        "modeledIOFailureBranches": ioFailures,
        "syscallLevelFaultInjection": "NOT_IMPLEMENTED",
        "recoverAppendSealRecover": resumedChain,
        "recoveryCadence": recoveryCadence,
        "nonAtomicAdmissionCheckAndGC": admissionCheckAndGC,
        "pairedABBA": paired,
        "pairedMeasurementGaps": ["allocationObserver": "NOT_MEASURED",
                                  "physicalFootprint": "NOT_MEASURED",
                                  "logicalVsAllocatedDisk": "NOT_MEASURED",
                                  "writeAmplification": "NOT_MEASURED",
                                  "backpressure": "NOT_IMPLEMENTED_OR_MEASURED",
                                  "compactorOverlap": "NOT_IMPLEMENTED_OR_MEASURED"],
        "boundedIO": ["fullFileDataReads": 0, "streamedFrameReadBytes": sealedFrameBytes,
                      "streamedHashBlockBytes": 65_536,
                      "writerReusableFrameBytes": sealedFrameBytes,
                      "writerReusableSealBytes": sealedSealBytes,
                      "writerReusableManifestBytes": sealedManifestBytes,
                      "writerReusableHeaderBytes": sealedHeaderBytes,
                      "fixedMetadataPools": "NOT_IMPLEMENTED",
                      "directoryListingAllocation": "DYNAMIC",
                      "manifestHistoryAllocation": "DYNAMIC",
                      "activeTailValidation": "STREAMED_EXACT_FRAME_OR_FAIL_CLOSED",
                      "reopenAppend": true, "secondWorlds": 0,
                      "maximumRecoverySegmentsExecuted": 25],
        "semantics": ["recovery": "HIGHEST_CONTIGUOUS_PRESENT_MANIFEST_EXACT_OR_FAIL_CLOSED_WITH_KNOWN_CLEAN_ROLLBACK_GAP",
                      "prePublicationAppendOrCommitError": "LIVE_HANDLE_INVALIDATED_RECOVERY_REQUIRED",
                      "cleanupFailure": "COMMITTED_GC_PENDING",
                      "staleCompactor": "NON_ATOMIC_ADMISSION_CHECK_ONLY",
                      "activeUnpublishedSuffix": "VALIDATED_BUT_NOT_APPLIED_TO_DURABLE_ROOT",
                      "callbackUncertainty": "DIRSYNC_MAY_COMMIT_BEFORE_CALLER_OBSERVES_RETURN",
                      "requestID": "NOT_IMPLEMENTED",
                      "idempotentStatusQuery": "NOT_IMPLEMENTED"],
        "H1M": "NOT_RUN", "C5": "NOT_RUN", "C100": "NOT_RUN",
        "safeToRunH1M": false, "safeToRunC": false,
        "crossProcessOwnerLock": "NOT_IMPLEMENTED",
        "physicalPowerLoss": "NOT_TESTED",
        "limitations": "Partial single-process exclusive temporary-directory study with a scalar/root fixture. There is no durable CURRENT authority, so clean deletion of the newest manifest and all visible descendant entries can roll durable selection backward and reclassify a formerly committed tail as pending. Request IDs, idempotent status queries, fixed metadata pools, and syscall-level fault injection are not implemented. fsync/rename/dirsync calls and in-process crash boundaries do not certify physical power loss. Allocation observation, physical footprint, filesystem allocated bytes, write amplification, backpressure, compaction payload/publication and compactor overlap are not implemented or measured. Recovery is bounded to 25 segments here; production recovery SLA, authentication, cross-process locking, full H/S memory, Stage A, Stage C overheadRatio<=1.10, application smoothness, and iPhone behavior remain unproved."
    ]
}
#endif
