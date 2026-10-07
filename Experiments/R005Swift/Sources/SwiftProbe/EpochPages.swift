#if EPOCH_PAGES
import Foundation

// Experimental storage within the existing S/H owners. A live owner is never
// Sendable. Only immutable value roots cross to the snapshot writer.
private typealias EpochPage<T> = ContiguousArray<T>
private typealias EpochLeaf<T> = ContiguousArray<EpochPage<T>>
private typealias EpochRoot<T> = ContiguousArray<EpochLeaf<T>>

struct FrozenEpochBuffer<T: BitwiseCopyable & Sendable>: Sendable {
    fileprivate let root: EpochRoot<T>
    let count: Int
    let pageShift: Int
    let epoch: UInt32

    var pageCount: Int { (count + (1 << pageShift) - 1) >> pageShift }
    func elements(in page: Int) -> Int { min(1 << pageShift, count - (page << pageShift)) }
    @inline(__always) func page(_ index: Int) -> ContiguousArray<T> { root[index >> 6][index & 63] }
}

final class EpochBuffer<T: BitwiseCopyable & Sendable> {
    private var root: EpochRoot<T> = []
    private var spareRoot: EpochRoot<T> = []
    private var spareLeaves: ContiguousArray<EpochLeaf<T>> = []
    private var sparePages: ContiguousArray<EpochPage<T>> = []
    private var leafEpoch: ContiguousArray<UInt32>
    private var pageEpoch: ContiguousArray<UInt32>
    private var rootEpoch: UInt32 = 0
    private(set) var epoch: UInt32 = 0
    private(set) var active = false
    private(set) var prepared = false
    let count: Int
    let pageShift: Int
    let pageCount: Int

    init(count: Int, pageShift: Int, makePage: (Range<Int>) -> ContiguousArray<T>) {
        precondition(count > 0 && (1...16).contains(pageShift))
        self.count = count; self.pageShift = pageShift
        pageCount = (count + (1 << pageShift) - 1) >> pageShift
        let leafCount = (pageCount + 63) >> 6
        leafEpoch = .init(repeating: 0, count: leafCount)
        pageEpoch = .init(repeating: 0, count: pageCount)
        root.reserveCapacity(leafCount)
        for first in stride(from: 0, to: pageCount, by: 64) {
            var leaf = EpochLeaf<T>()
            leaf.reserveCapacity(min(64, pageCount - first))
            for page in first..<min(first + 64, pageCount) {
                let start = page << pageShift
                leaf.append(makePage(start..<min(start + (1 << pageShift), count)))
            }
            root.append(leaf)
        }
    }

    convenience init(repeating value: T, count: Int, pageShift: Int) {
        self.init(count: count, pageShift: pageShift) { .init(repeating: value, count: $0.count) }
    }

    // Pool preparation is measured setup, outside beginSave and advance. Stage A
    // owns only its live image; installing Stage C explicitly reserves another.
    func preparePool() {
        precondition(!active)
        guard !prepared else { return }
        spareRoot = .init(repeating: [], count: root.count)
        spareLeaves.reserveCapacity(root.count)
        sparePages.reserveCapacity(pageCount)
        for leaf in root { spareLeaves.append(.init(repeating: [], count: leaf.count)) }
        for page in 0..<pageCount {
            let source = root[page >> 6][page & 63]
            var spare = EpochPage<T>()
            spare.reserveCapacity(source.count)
            spare.append(contentsOf: source)
            sparePages.append(spare)
        }
        prepared = true
    }

    func canFreeze(epoch value: UInt32) -> Bool { prepared && !active && value > epoch }

    func freeze(epoch value: UInt32) -> FrozenEpochBuffer<T> {
        precondition(canFreeze(epoch: value))
        active = true; epoch = value
        return FrozenEpochBuffer(root: root, count: count, pageShift: pageShift, epoch: value)
    }

    @inline(__always) func elements(in page: Int) -> Int {
        min(1 << pageShift, count - (page << pageShift))
    }
    @inline(__always) func needsCopy(page: Int) -> Bool { active && pageEpoch[page] != epoch }

    // No detached mutable array is returned. Internal setters call this even if
    // a caller omitted the explicit pre-write telemetry hook.
    @inline(__always) @discardableResult func ensureWritable(page: Int) -> Int {
        guard active && pageEpoch[page] != epoch else { return 0 }
        let leaf = page >> 6, slot = page & 63
        if rootEpoch != epoch {
            for i in root.indices { spareRoot[i] = root[i] }
            swap(&root, &spareRoot)
            rootEpoch = epoch
        }
        if leafEpoch[leaf] != epoch {
            for i in root[leaf].indices { spareLeaves[leaf][i] = root[leaf][i] }
            swap(&root[leaf], &spareLeaves[leaf])
            leafEpoch[leaf] = epoch
        }
        sparePages[page].replaceSubrange(0..<root[leaf][slot].count, with: root[leaf][slot])
        swap(&root[leaf][slot], &sparePages[page])
        pageEpoch[page] = epoch
        return root[leaf][slot].count * MemoryLayout<T>.stride
    }

    @inline(__always) func element(at index: Int) -> T {
        precondition(index >= 0 && index < count)
        let page = index >> pageShift
        return root[page >> 6][page & 63][index & ((1 << pageShift) - 1)]
    }
    @inline(__always) func setElement(at index: Int, to value: T) {
        precondition(index >= 0 && index < count)
        let page = index >> pageShift
        ensureWritable(page: page)
        root[page >> 6][page & 63][index & ((1 << pageShift) - 1)] = value
    }
    // One nonescaping, synchronous mutation borrow. The page becomes unique
    // before any inout access; neither storage nor a mutable owner escapes.
    @inline(__always) func updateElement(at index: Int, _ body: (inout T) -> Void) {
        precondition(index >= 0 && index < count)
        let page = index >> pageShift
        ensureWritable(page: page)
        body(&root[page >> 6][page & 63][index & ((1 << pageShift) - 1)])
    }
    @inline(__always) func word(page: Int, index: Int) -> T { root[page >> 6][page & 63][index] }
    @inline(__always) func setWord(page: Int, index: Int, value: T) {
        ensureWritable(page: page)
        root[page >> 6][page & 63][index] = value
    }

    func releaseCompleted(epoch value: UInt32) {
        // The caller has acquired writer completion after the writer dropped
        // every frozen value. An early release is a programmer error.
        precondition(active && epoch == value)
        for i in spareRoot.indices { spareRoot[i] = [] }
        for leaf in spareLeaves.indices {
            for i in spareLeaves[leaf].indices { spareLeaves[leaf][i] = [] }
        }
        active = false
    }

    var ownedBytes: Int {
        var total = (root.capacity + spareRoot.capacity) * MemoryLayout<EpochLeaf<T>>.stride
        total += spareLeaves.capacity * MemoryLayout<EpochLeaf<T>>.stride
        total += sparePages.capacity * MemoryLayout<EpochPage<T>>.stride
        total += (leafEpoch.capacity + pageEpoch.capacity) * MemoryLayout<UInt32>.stride
        for leaf in root {
            total += leaf.capacity * MemoryLayout<EpochPage<T>>.stride
            for page in leaf { total += page.capacity * MemoryLayout<T>.stride }
        }
        for leaf in spareLeaves { total += leaf.capacity * MemoryLayout<EpochPage<T>>.stride }
        for page in sparePages { total += page.capacity * MemoryLayout<T>.stride }
        return total
    }

    var view: EpochRowsView<T> { EpochRowsView(owner: self) }
#if STAGE_C
    func appendRows(_ range: Range<Int>, into bytes: inout [UInt8]) {
        precondition(range.lowerBound >= 0 && range.upperBound <= count)
        var position = range.lowerBound
        while position < range.upperBound {
            let page = position >> pageShift
            let offset = position & ((1 << pageShift) - 1)
            let length = min(elements(in: page) - offset, range.upperBound - position)
            Snapshot.append(root[page >> 6][page & 63], offset..<(offset + length), into: &bytes)
            position += length
        }
    }
    func appendPackedPage(_ page: Int, payloadBytes: Int, into bytes: inout [UInt8]) {
        let values = root[page >> 6][page & 63]
        let padding = values.count * MemoryLayout<T>.stride - payloadBytes
        precondition(padding >= 0 && padding < 8)
        Snapshot.append(values, 0..<values.count, into: &bytes)
        if padding > 0 { bytes.removeLast(padding) }
    }
#endif
}

// Borrowed synchronous reads, deliberately not Sendable and without a setter.
// Copying a view does not grant a second mutation owner or a frozen snapshot.
struct EpochRowsView<T: BitwiseCopyable & Sendable>: RandomAccessCollection {
    typealias Index = Int
    fileprivate let owner: EpochBuffer<T>
    var startIndex: Int { 0 }
    var endIndex: Int { owner.count }
    var count: Int { owner.count }
    var capacity: Int { owner.count }
    func index(after i: Int) -> Int { i + 1 }
    func index(before i: Int) -> Int { i - 1 }
    @inline(__always) subscript(index: Int) -> T { owner.element(at: index) }
#if STAGE_C
    func append(_ range: Range<Int>, into bytes: inout [UInt8]) { owner.appendRows(range, into: &bytes) }
#endif
}

final class EpochWordColumns {
    let buffer: EpochBuffer<UInt64>
    let bytesPerElement: Int
    var count: Int { buffer.count }
    init(count: Int, pageShift: Int, bytesPerElement: Int) {
        self.bytesPerElement = bytesPerElement
        buffer = EpochBuffer(count: count, pageShift: pageShift) {
            .init(repeating: 0, count: ($0.count * bytesPerElement + 7) >> 3)
        }
    }

    @inline(__always) func read<T: FixedWidthInteger>(base: Int, width: Int, index: Int, as: T.Type) -> T {
        precondition(index >= 0 && index < count)
        let page = index >> buffer.pageShift
        let byte = base * buffer.elements(in: page) + (index & ((1 << buffer.pageShift) - 1)) * width
        let word = byte >> 3, shift = (byte & 7) << 3
        var value = buffer.word(page: page, index: word) >> shift
        if shift + width * 8 > 64 { value |= buffer.word(page: page, index: word + 1) << (64 - shift) }
        return T(truncatingIfNeeded: value)
    }
    @inline(__always) func set<T: FixedWidthInteger>(base: Int, width: Int, index: Int, value: T) {
        precondition(index >= 0 && index < count)
        let page = index >> buffer.pageShift
        let byte = base * buffer.elements(in: page) + (index & ((1 << buffer.pageShift) - 1)) * width
        let word = byte >> 3, shift = (byte & 7) << 3
        let mask = width == 8 ? UInt64.max : (UInt64(1) << (width * 8)) - 1
        let bits = UInt64(truncatingIfNeeded: value) & mask
        let first = buffer.word(page: page, index: word)
        buffer.setWord(page: page, index: word, value: (first & ~(mask << shift)) | (bits << shift))
        if shift + width * 8 > 64 {
            let rest = shift + width * 8 - 64
            let highMask = (UInt64(1) << rest) - 1
            let second = buffer.word(page: page, index: word + 1)
            buffer.setWord(page: page, index: word + 1,
                           value: (second & ~highMask) | (bits >> (64 - shift)))
        }
    }
    func column<T: FixedWidthInteger & BitwiseCopyable & Sendable>(base: Int, width: Int, as: T.Type) -> EpochColumn<T> {
        EpochColumn(owner: self, base: base, width: width)
    }
}

struct EpochColumn<T: FixedWidthInteger & BitwiseCopyable & Sendable>: RandomAccessCollection {
    typealias Index = Int
    fileprivate let owner: EpochWordColumns
    fileprivate let base: Int
    fileprivate let width: Int
    var startIndex: Int { 0 }
    var endIndex: Int { owner.count }
    var count: Int { owner.count }
    var capacity: Int { owner.count }
    func index(after i: Int) -> Int { i + 1 }
    func index(before i: Int) -> Int { i - 1 }
    @inline(__always) subscript(index: Int) -> T { owner.read(base: base, width: width, index: index, as: T.self) }
}
#endif
