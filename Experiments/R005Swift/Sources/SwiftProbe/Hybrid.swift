import Foundation
import ProbePlatform

struct HotAsset: BitwiseCopyable, Equatable, Sendable {
    var accruedOperation: UInt64
    var completed: UInt64
    var fare: Int64
    var generation: UInt32
    var destination: UInt32
    var airport: UInt32
    var contract: UInt32
    var changeEpoch: UInt32
    var active: UInt8
    var reserved0: UInt8
    var reserved1: UInt16

    init() {
        accruedOperation = 0
        completed = 0
        fare = 0
        generation = 0
        destination = 2
        airport = 1
        contract = 0
        changeEpoch = 0
        active = 0
        reserved0 = 0
        reserved1 = 0
    }
}

struct EventNode: BitwiseCopyable, Equatable, Sendable {
    var due: UInt64
    var operation: UInt64
    var asset: UInt32
    var generation: UInt32
    var next: UInt32
    var kind: UInt8
    var live: UInt8
    var reserved: UInt16

    init(due: UInt64 = 0, operation: UInt64 = 0, asset: UInt32 = none,
         generation: UInt32 = 0, next: UInt32 = none, kind: UInt8 = 0, live: UInt8 = 0) {
        self.due = due
        self.operation = operation
        self.asset = asset
        self.generation = generation
        self.next = next
        self.kind = kind
        self.live = live
        self.reserved = 0
    }

    var asEvent: Event {
        Event(due: due, operation: operation, asset: asset, generation: generation, kind: kind)
    }
}

func hybridLayoutSelftest() throws -> [String: Any] {
    try require(MemoryLayout<HotAsset>.size == 48 && MemoryLayout<HotAsset>.stride == 48,
                "HotAsset layout")
    try require(MemoryLayout<EventNode>.size == 32 && MemoryLayout<EventNode>.stride == 32,
                "EventNode layout")
    let a = HotAsset()
    let n = EventNode()
    try require(a.reserved0 == 0 && a.reserved1 == 0 && n.reserved == 0, "explicit padding zero")
    return ["status":"pass", "hotAssetSize":MemoryLayout<HotAsset>.size,
            "hotAssetStride":MemoryLayout<HotAsset>.stride,
            "eventNodeSize":MemoryLayout<EventNode>.size,
            "eventNodeStride":MemoryLayout<EventNode>.stride]
}

final class HybridTimingWheel {
#if EPOCH_PAGES
    private let nodePages: EpochBuffer<EventNode>
    var nodes: EpochRowsView<EventNode> { nodePages.view }
#else
    private(set) var nodes: ContiguousArray<EventNode>
#endif
    private var heads = ContiguousArray(repeating: none, count: 2048)
    private var tails = ContiguousArray(repeating: none, count: 2048)
    private var sorted = ContiguousArray(repeating: true, count: 2048)
    private var occupied = ContiguousArray(repeating: UInt64(0), count: 32)
    private var free: UInt32 = none
    private(set) var pending = 0
    private(set) var cursor: UInt64 = 0
    private var cascade = -1
    private var leaf = -1
    private var sortPhase = 0
    private var width = 1
    private var merges = 0
    private var seek = 0
    private var leftCount = 0
    private var rightCount = 0
    private var pair: UInt32 = none
    private var left: UInt32 = none
    private var right: UInt32 = none
    private var outHead: UInt32 = none
    private var outTail: UInt32 = none
    let mutation: Mutation
    private var fired = false
    private var ghost: Event? = nil
#if STAGE_C
    var stageCState: StageCState? = nil
#endif

    init(capacity: Int, mutation: Mutation = .none) throws {
        guard capacity > 0, capacity <= 2_000_000 else { throw ProbeError.invalid("wheel capacity") }
        self.mutation = mutation
#if EPOCH_PAGES
        nodePages = EpochBuffer(repeating: EventNode(), count: capacity, pageShift: 9)
#else
        nodes = .init(repeating: EventNode(), count: capacity)
#endif
        if capacity > 1 {
            for i in 0..<(capacity - 1) { writeNodeNext(i, UInt32(i + 1))}
        }
        writeNodeNext(capacity - 1, none)
        free = 0
    }

    var capacity: Int { nodes.count }

    var ownedBytes: Int {
#if EPOCH_PAGES
        let storage = nodePages.ownedBytes
#else
        let storage = nodes.capacity * MemoryLayout<EventNode>.stride
#endif
        return storage + (heads.capacity + tails.capacity) * MemoryLayout<UInt32>.stride +
        sorted.capacity * MemoryLayout<Bool>.stride +
        occupied.capacity * MemoryLayout<UInt64>.stride
    }

    @inline(__always) private func writeNode(_ index: Int, _ value: EventNode) {
#if EPOCH_PAGES
        nodePages.setElement(at: index, to: value)
#else
        nodes[index] = value
#endif
    }
    @inline(__always) private func writeNodeNext(_ index: Int, _ value: UInt32) {
#if EPOCH_PAGES
        nodePages.updateElement(at: index) { $0.next = value }
#else
        var row = nodes[index]; row.next = value; writeNode(index, row)
#endif
    }
    @inline(__always) private func writeNodeLive(_ index: Int, _ value: UInt8) {
#if EPOCH_PAGES
        nodePages.updateElement(at: index) { $0.live = value }
#else
        var row = nodes[index]; row.live = value; writeNode(index, row)
#endif
    }
    @inline(__always) private func bucket(_ time: UInt64) -> Int {
        let difference = time ^ cursor
        let level = difference == 0 ? 0 : (63 - difference.leadingZeroBitCount) / 8
        var slot = Int((time >> (level * 8)) & 255)
        if mutation == .slotPlusOne { slot = (slot + 1) & 255 }
        if mutation == .slotMinusOne { slot = (slot + 255) & 255 }
        return level * 256 + slot
    }

    @inline(__always) private func setOccupied(_ b: Int, _ value: Bool) {
        let word = b / 64
        let mask = UInt64(1) << (b % 64)
        if value { occupied[word] |= mask } else { occupied[word] &= ~mask }
    }

    @inline(__always) private func insertNode(_ id: UInt32, into b: Int, cascading: Bool = false) {
        let i = Int(id)
        let tail = tails[b]
#if STAGE_C
        stageCState?.willWriteNode(self, index: i)
#endif
        writeNodeNext(i, none)
        if tail == none {
            heads[b] = id
            tails[b] = id
            sorted[b] = true
            setOccupied(b, true)
        } else if mutation == .reverseCascade && cascading {
#if STAGE_C
            stageCState?.willWriteNode(self, index: i)
#endif
            writeNodeNext(i, heads[b])
            heads[b] = id
            sorted[b] = true
        } else {
            if nodes[Int(tail)].operation > nodes[i].operation { sorted[b] = false }
#if STAGE_C
            stageCState?.willWriteNode(self, index: Int(tail))
#endif
            writeNodeNext(Int(tail), id)
            tails[b] = id
        }
        if mutation == .omitTieBreaker { sorted[b] = true }
    }

    func schedule(_ event: Event) throws -> UInt32 {
        guard event.due >= cursor, event.operation > 0, free != none else { throw ProbeError.invalid("schedule") }
        guard sortPhase == 0 && leaf == -1 && cascade == -1 else { throw ProbeError.invalid("schedule during wheel continuation") }
        let id = free
        let i = Int(id)
        free = nodes[i].next
#if STAGE_C
        stageCState?.willWriteNode(self, index: i)
#endif
        writeNode(i, EventNode(due: event.due, operation: event.operation, asset: event.asset,
                             generation: event.generation, next: none, kind: event.kind, live: 1))
        insertNode(id, into: bucket(event.due))
        pending += 1
        return id
    }

    @inline(__always) func event(_ id: UInt32) -> Event { nodes[Int(id)].asEvent }

    func restoreCursor(_ time: UInt64) throws {
        guard pending == 0 else { throw ProbeError.invalid("restore cursor with pending events") }
        cursor = time
    }

    private func startSort() {
        width = 1
        pair = heads[leaf]
        outHead = none
        outTail = none
        merges = 0
        sortPhase = 1
    }

    private func sortStep() throws {
        switch sortPhase {
        case 1:
            if pair == none {
                if outTail != none {
#if STAGE_C
                    stageCState?.willWriteNode(self, index: Int(outTail))
#endif
                    writeNodeNext(Int(outTail), none)
                }
                heads[leaf] = outHead
                tails[leaf] = outTail
                if merges <= 1 {
                    sorted[leaf] = true
                    sortPhase = 0
                    return
                }
                guard width <= capacity else { throw ProbeError.invariant("sort bound") }
                width *= 2
                pair = outHead
                outHead = none
                outTail = none
                merges = 0
                return
            }
            merges += 1
            left = pair
            right = pair
            leftCount = 0
            seek = width
            sortPhase = 2
        case 2:
            if seek > 0 && right != none {
                right = nodes[Int(right)].next
                leftCount += 1
                seek -= 1
            } else {
                rightCount = width
                sortPhase = 3
            }
        case 3:
            if leftCount == 0 && (rightCount == 0 || right == none) {
                pair = right
                sortPhase = 1
                return
            }
            let chooseLeft = leftCount > 0 && (rightCount == 0 || right == none ||
                nodes[Int(left)].operation <= nodes[Int(right)].operation)
            let picked: UInt32
            if chooseLeft {
                picked = left
                left = nodes[Int(left)].next
                leftCount -= 1
            } else {
                picked = right
                right = nodes[Int(right)].next
                rightCount -= 1
            }
            if outTail == none { outHead = picked } else {
#if STAGE_C
                stageCState?.willWriteNode(self, index: Int(outTail))
#endif
                writeNodeNext(Int(outTail), picked)
            }
            outTail = picked
        default:
            throw ProbeError.invariant("sort phase")
        }
    }

    func step(target: UInt64) throws -> WheelStep {
        if sortPhase != 0 { try sortStep(); return .work }
        if cascade >= 0 {
            let id = heads[cascade]
            if id == none {
                setOccupied(cascade, false)
                tails[cascade] = none
                cascade = -1
                return .work
            }
            heads[cascade] = nodes[Int(id)].next
            let b = bucket(nodes[Int(id)].due)
            guard b / 256 < cascade / 256 else { throw ProbeError.invariant("cascade does not lower level") }
            insertNode(id, into: b, cascading: true)
            return .work
        }
        if leaf >= 0 {
            let id = heads[leaf]
            if id == none {
                setOccupied(leaf, false)
                tails[leaf] = none
                leaf = -1
                return .work
            }
            if !sorted[leaf] { startSort(); return .work }
            if mutation == .swapTie && !fired && nodes[Int(id)].next != none {
                let b = nodes[Int(id)].next
#if STAGE_C
                stageCState?.willWriteNode(self, index: Int(id))
                stageCState?.willWriteNode(self, index: Int(b))
#endif
                writeNodeNext(Int(id), nodes[Int(b)].next)
                writeNodeNext(Int(b), id)
                heads[leaf] = b
                fired = true
            }
            let ready = heads[leaf]
            guard nodes[Int(ready)].due == cursor else { throw ProbeError.invariant("wrong wheel slot/time") }
            if mutation == .missing && !fired {
                _ = try consume(ready)
                fired = true
                return .work
            }
            return .ready(ready)
        }
        if pending == 0 { return .drained }
        var candidateBucket = -1
        var candidateTime = UInt64.max
        for level in 0..<8 {
            for word in 0..<4 {
                let bits = occupied[level * 4 + word]
                if bits == 0 { continue }
                let slot = word * 64 + bits.trailingZeroBitCount
                let shift = level * 8
                let high: UInt64 = level == 7 ? 0 : cursor & (UInt64.max << (shift + 8))
                let start = high | (UInt64(slot) << shift)
                guard start >= cursor else { throw ProbeError.invariant("past occupied bucket") }
                if candidateBucket == -1 || start < candidateTime {
                    candidateBucket = level * 256 + slot
                    candidateTime = start
                }
                break
            }
        }
        guard candidateBucket >= 0 else { throw ProbeError.invariant("lost live event") }
        if candidateTime > target { return .beyondTarget }
        cursor = candidateTime
        if candidateBucket / 256 == 0 { leaf = candidateBucket } else { cascade = candidateBucket }
        return .work
    }

    func consume(_ id: UInt32) throws -> Event {
        guard leaf >= 0, heads[leaf] == id, nodes[Int(id)].live == 1 else { throw ProbeError.invariant("consume non-head") }
        let value = nodes[Int(id)].asEvent
#if STAGE_C
        stageCState?.willWriteNode(self, index: Int(id))
#endif
        heads[leaf] = nodes[Int(id)].next
#if EPOCH_PAGES
        let nextFree = free
        nodePages.updateElement(at: Int(id)) { row in
            row.live = 0; row.next = nextFree
        }
#else
        writeNodeLive(Int(id), 0)
        writeNodeNext(Int(id), free)
#endif
        free = id
        pending -= 1
        if mutation == .duplicate && !fired { ghost = value; fired = true }
        return value
    }

    func takeGhost() -> Event? {
        let value = ghost
        ghost = nil
        return value
    }
#if STAGE_C
#if EPOCH_PAGES
    func stageCPreparePages() { nodePages.preparePool() }
    func stageCCanFreezePages(_ epoch: UInt32) -> Bool { nodePages.canFreeze(epoch: epoch) }
    func stageCFreezePages(_ epoch: UInt32) -> FrozenEpochBuffer<EventNode> { nodePages.freeze(epoch: epoch) }
    @inline(__always) func stageCNeedsNodeCopy(_ index: Int) -> Bool { nodePages.needsCopy(page: index >> 9) }
    func stageCClonePage(_ index: Int) -> Int { nodePages.ensureWritable(page: index >> 9) }
    func stageCReleasePages(_ epoch: UInt32) { nodePages.releaseCompleted(epoch: epoch) }
#endif
    func stageCAppendNodeChunk(_ range: Range<Int>, into data: inout [UInt8]) {
        Snapshot.append(nodes, range, into: &data)
    }
    func stageCAppendControl(into data: inout [UInt8]) {
        Snapshot.appendLE(cursor, into: &data)
        Snapshot.appendLE(UInt32(pending), into: &data)
        Snapshot.appendLE(free, into: &data)
        Snapshot.appendLE(UInt32(bitPattern: Int32(cascade)), into: &data)
        Snapshot.appendLE(UInt32(bitPattern: Int32(leaf)), into: &data)
        Snapshot.appendLE(UInt32(bitPattern: Int32(sortPhase)), into: &data)
        Snapshot.appendLE(UInt32(bitPattern: Int32(width)), into: &data)
        Snapshot.appendLE(UInt32(bitPattern: Int32(merges)), into: &data)
        Snapshot.appendLE(UInt32(bitPattern: Int32(seek)), into: &data)
        Snapshot.appendLE(UInt32(bitPattern: Int32(leftCount)), into: &data)
        Snapshot.appendLE(UInt32(bitPattern: Int32(rightCount)), into: &data)
        Snapshot.appendLE(pair, into: &data); Snapshot.appendLE(left, into: &data)
        Snapshot.appendLE(right, into: &data); Snapshot.appendLE(outHead, into: &data)
        Snapshot.appendLE(outTail, into: &data)
        Snapshot.append(heads, 0..<heads.count, into: &data)
        Snapshot.append(tails, 0..<tails.count, into: &data)
        Snapshot.appendBoolBytes(sorted, 0..<sorted.count, into: &data)
        Snapshot.append(occupied, 0..<occupied.count, into: &data)
    }
    func stageCRestoreControl(_ c: StageCWheelControl) throws {
        guard c.heads.count == 2048, c.tails.count == 2048, c.sorted.count == 2048,
              c.occupied.count == 32, c.pending >= 0, c.pending <= capacity else {
            throw ProbeError.corruption("stage C hybrid wheel control")
        }
        cursor=c.cursor; pending=c.pending; free=c.free; cascade=c.cascade; leaf=c.leaf
        sortPhase=c.sortPhase; width=c.width; merges=c.merges; seek=c.seek
        leftCount=c.leftCount; rightCount=c.rightCount; pair=c.pair; left=c.left; right=c.right
        outHead=c.outHead; outTail=c.outTail
        heads=ContiguousArray(c.heads); tails=ContiguousArray(c.tails)
        sorted=ContiguousArray(c.sorted); occupied=ContiguousArray(c.occupied)
        fired=false; ghost=nil
    }
    func stageCRestoreNode(_ i:Int,due:UInt64,operation:UInt64,asset:UInt32,generation:UInt32,
                           next:UInt32,kind:UInt8,live:UInt8,reserved:UInt16) throws {
        guard i>=0 && i<capacity,kind<=2,live<=1,reserved==0 else {
            throw ProbeError.corruption("stage C hybrid node")
        }
        writeNode(i, EventNode(due:due,operation:operation,asset:asset,generation:generation,next:next,kind:kind,live:live))
    }
#endif
}

final class HybridWorld {
    let count: Int
    let wheel: HybridTimingWheel
#if EPOCH_PAGES
    private let hotPages: EpochBuffer<HotAsset>
    private let coldPages: EpochWordColumns
    private let groupPages: EpochBuffer<Int64>
    var hot: EpochRowsView<HotAsset> { hotPages.view }
    var entity: EpochColumn<UInt32> { coldPages.column(base: 0, width: 4, as: UInt32.self) }
    var policy: EpochColumn<UInt32> { coldPages.column(base: 4, width: 4, as: UInt32.self) }
    var origin: EpochColumn<UInt32> { coldPages.column(base: 8, width: 4, as: UInt32.self) }
    var departure: EpochColumn<UInt64> { coldPages.column(base: 12, width: 8, as: UInt64.self) }
    var groupAmounts: EpochRowsView<Int64> { groupPages.view }
#else
    private(set) var hot: ContiguousArray<HotAsset>
    private(set) var entity: ContiguousArray<UInt32>
    private(set) var policy: ContiguousArray<UInt32>
    private(set) var origin: ContiguousArray<UInt32>
    private(set) var departure: ContiguousArray<UInt64>
    private(set) var groupAmounts: ContiguousArray<Int64>
#endif
    private var outputs: ContiguousArray<Completion>
    private(set) var now: UInt64 = 0
    private(set) var revenue: Int64 = 0
    private(set) var receivable: Int64 = 0
    private(set) var cash: Int64 = 1_000
    private(set) var processed: UInt64 = 0
    private(set) var sequenceHash: UInt64 = 14695981039346656037
    private(set) var rejectedStale = 0
    private(set) var changeEpoch: UInt32 = 1
#if STAGE_C
    var stageCState: StageCState? = nil
#endif

    init(count: Int, eventCapacity: Int? = nil, mutation: Mutation = .none) throws {
        guard (1...2_000_000).contains(count) else { throw ProbeError.invalid("asset capacity") }
        self.count = count
        wheel = try HybridTimingWheel(capacity: eventCapacity ?? count, mutation: mutation)
#if EPOCH_PAGES
        hotPages = EpochBuffer(repeating: HotAsset(), count: count, pageShift: 8)
        coldPages = EpochWordColumns(count: count, pageShift: 8, bytesPerElement: 20)
        groupPages = EpochBuffer(repeating: 0, count: (count + 15) / 16, pageShift: 11)
#else
        hot = .init(repeating: HotAsset(), count: count)
        entity = .init(repeating: 0, count: count)
        policy = .init(repeating: 0, count: count)
        origin = .init(repeating: 1, count: count)
        departure = .init(repeating: 0, count: count)
        groupAmounts = .init(repeating: 0, count: (count + 15) / 16)
#endif
        outputs = .init(repeating: .empty, count: 1024)
#if EPOCH_PAGES
        for i in 0..<count { writeOrigin(i, 1) }
#endif
        for i in 0..<count {
            writeHotContract(i, UInt32(i / 16))
            writeEntity(i, UInt32(i % 32))
        }
    }

    var ownedBytes: Int {
#if EPOCH_PAGES
        return wheel.ownedBytes + hotPages.ownedBytes + coldPages.buffer.ownedBytes + groupPages.ownedBytes +
        outputs.capacity * MemoryLayout<Completion>.stride
#else
        wheel.ownedBytes +
        hot.capacity * MemoryLayout<HotAsset>.stride +
        (entity.capacity + policy.capacity + origin.capacity) * MemoryLayout<UInt32>.stride +
        departure.capacity * MemoryLayout<UInt64>.stride +
        groupAmounts.capacity * MemoryLayout<Int64>.stride +
        outputs.capacity * MemoryLayout<Completion>.stride
#endif
    }
    @inline(__always) private func writeEntity(_ index: Int, _ value: UInt32) {
#if EPOCH_PAGES
#if STAGE_C
        stageCState?.willWriteColdAsset(self, index: index)
#endif
        coldPages.set(base: 0, width: 4, index: index, value: value)
#else
        entity[index] = value
#endif
    }
    @inline(__always) private func writePolicy(_ index: Int, _ value: UInt32) {
#if EPOCH_PAGES
#if STAGE_C
        stageCState?.willWriteColdAsset(self, index: index)
#endif
        coldPages.set(base: 4, width: 4, index: index, value: value)
#else
        policy[index] = value
#endif
    }
    @inline(__always) private func writeOrigin(_ index: Int, _ value: UInt32) {
#if EPOCH_PAGES
#if STAGE_C
        stageCState?.willWriteColdAsset(self, index: index)
#endif
        coldPages.set(base: 8, width: 4, index: index, value: value)
#else
        origin[index] = value
#endif
    }
    @inline(__always) private func writeDeparture(_ index: Int, _ value: UInt64) {
#if EPOCH_PAGES
#if STAGE_C
        stageCState?.willWriteColdAsset(self, index: index)
#endif
        coldPages.set(base: 12, width: 8, index: index, value: value)
#else
        departure[index] = value
#endif
    }
    @inline(__always) private func writeGroupAmounts(_ index: Int, _ value: Int64) {
#if EPOCH_PAGES
        groupPages.setElement(at: index, to: value)
#else
        groupAmounts[index] = value
#endif
    }
    @inline(__always) private func writeHot(_ index: Int, _ value: HotAsset) {
#if EPOCH_PAGES
        hotPages.setElement(at: index, to: value)
#else
        hot[index] = value
#endif
    }
    @inline(__always) private func writeHotContract(_ index: Int, _ value: UInt32) {
#if EPOCH_PAGES
        hotPages.updateElement(at: index) { $0.contract = value }
#else
        var row = hot[index]; row.contract = value; writeHot(index, row)
#endif
    }
    @inline(__always) private func writeHotFare(_ index: Int, _ value: Int64) {
#if EPOCH_PAGES
        hotPages.updateElement(at: index) { $0.fare = value }
#else
        var row = hot[index]; row.fare = value; writeHot(index, row)
#endif
    }
    @inline(__always) private func writeHotActive(_ index: Int, _ value: UInt8) {
#if EPOCH_PAGES
        hotPages.updateElement(at: index) { $0.active = value }
#else
        var row = hot[index]; row.active = value; writeHot(index, row)
#endif
    }
    @inline(__always) private func writeHotGeneration(_ index: Int, _ value: UInt32) {
#if EPOCH_PAGES
        hotPages.updateElement(at: index) { $0.generation = value }
#else
        var row = hot[index]; row.generation = value; writeHot(index, row)
#endif
    }
    func output(_ index: Int) -> Completion { outputs[index] }

    func seedFixture() throws {
        for i in 0..<count {
            try schedule(asset: i, due: UInt64(i % 600 + 1), operation: UInt64(count + i + 1),
                         amount: Int64(i % 97 + 101))
        }
    }

    func schedule(asset i: Int, due: UInt64, operation: UInt64, amount: Int64, kind: UInt8 = 0) throws {
        guard i >= 0 && i < count, hot[i].active == 0, due >= now, amount > 0, kind <= 2,
              operation > hot[i].accruedOperation else { throw ProbeError.invalid("asset schedule") }
#if STAGE_C
        stageCState?.willWriteAsset(self, index: i)
#endif
        _ = try wheel.schedule(Event(due: due, operation: operation, asset: UInt32(i),
                                     generation: hot[i].generation, kind: kind))
        writeOrigin(i, hot[i].airport)
        writeDeparture(i, now)
#if EPOCH_PAGES
        hotPages.updateElement(at: i) { row in row.fare = amount; row.active = 1 }
#else
        writeHotFare(i, amount)
        writeHotActive(i, 1)
#endif
    }

    func invalidateGeneration(_ i: Int) throws {
        guard i >= 0 && i < count, hot[i].generation < UInt32.max else { throw ProbeError.invalid("generation") }
#if STAGE_C
        stageCState?.willWriteAsset(self, index: i)
#endif
        writeHotGeneration(i, hot[i].generation + 1)
    }

    func addCash(_ value: Int64) throws {
        let sum = cash.addingReportingOverflow(value)
        guard !sum.overflow, sum.partialValue >= 0 else { throw ProbeError.invalid("cash") }
        cash = sum.partialValue
    }

    @inline(__always) private func hash(_ event: Event, _ amount: Int64) {
        sequenceHash = (sequenceHash ^ event.due) &* 1099511628211
        sequenceHash = (sequenceHash ^ event.operation) &* 1099511628211
        sequenceHash = (sequenceHash ^ UInt64(event.asset)) &* 1099511628211
        sequenceHash = (sequenceHash ^ UInt64(event.generation)) &* 1099511628211
        sequenceHash = (sequenceHash ^ UInt64(bitPattern: amount)) &* 1099511628211
    }

    func advance(to target: UInt64, budget: Int, workBudget: Int = 65536,
                 checkLimit: Int = Int.max, deadlineNS: UInt64 = UInt64.max,
                 injectFailureAt: UInt64? = nil) throws -> SliceResult {
        guard target >= now, (1...1024).contains(budget), workBudget > 0, checkLimit > 0 else {
            throw ProbeError.invalid("advance budget/target")
        }
        var emitted = 0
        var work = 0
        while emitted < budget && work < workBudget {
            if work >= checkLimit || (deadlineNS != UInt64.max && nx_now() >= deadlineNS) {
                return SliceResult(events: emitted, units: work, reached: now, stop: .time)
            }
            work += 1
            if let duplicate = wheel.takeGhost() {
                let a = hot[Int(duplicate.asset)]
                outputs[emitted] = Completion(event: duplicate, amount: a.fare, completed: a.completed)
                emitted += 1
                continue
            }
            switch try wheel.step(target: target) {
            case .work:
                continue
            case .drained, .beyondTarget:
                now = target
                return SliceResult(events: emitted, units: work, reached: now, stop: .target)
            case .ready(let id):
                let e = wheel.nodes[Int(id)]
                let i = Int(e.asset)
                guard i < count else { throw ProbeError.invariant("wrong live asset") }
                var a = hot[i]
                guard a.active == 1 else { throw ProbeError.invariant("wrong live asset") }
                if e.generation != a.generation && wheel.mutation != .acceptStaleGeneration {
                    rejectedStale += 1
                    return SliceResult(events: emitted, units: work, reached: now, stop: .blocked)
                }
                if injectFailureAt == processed {
                    return SliceResult(events: emitted, units: work, reached: now, stop: .blocked)
                }
                guard e.operation > a.accruedOperation, e.due >= now,
                      a.completed < UInt64.max, processed < UInt64.max else {
                    throw ProbeError.invariant("duplicate/old operation or time")
                }
                let g = Int(a.contract)
                guard g < groupAmounts.count else { throw ProbeError.invariant("contract group") }
                let credit: Int64 = e.kind == 0 ? a.fare : 0
                let r = revenue.addingReportingOverflow(credit)
                let d = receivable.addingReportingOverflow(credit)
                let s = groupAmounts[g].addingReportingOverflow(credit)
                let c = cash.addingReportingOverflow(e.kind == 1 ? a.fare : e.kind == 2 ? -a.fare : 0)
                guard !r.overflow, !d.overflow, !s.overflow, !c.overflow else {
                    throw ProbeError.invalid("balance overflow")
                }
                if c.partialValue < 0 {
                    return SliceResult(events: emitted, units: work, reached: now, stop: .blocked)
                }
#if STAGE_C
                stageCState?.willWriteAsset(self, index: i)
                stageCState?.willWriteGroup(self, index: g)
#endif
                revenue = r.partialValue
                receivable = d.partialValue
                writeGroupAmounts(g, s.partialValue)
                cash = c.partialValue
                a.accruedOperation = e.operation
                a.completed += 1
                a.active = 0
                a.airport = a.destination
                a.changeEpoch = changeEpoch
                writeHot(i, a)
                now = e.due
                processed += 1
                _ = try wheel.consume(id)
                hash(e.asEvent, a.fare)
                outputs[emitted] = Completion(event: e.asEvent, amount: a.fare, completed: a.completed)
                emitted += 1
            }
        }
        return SliceResult(events: emitted, units: work, reached: now,
                           stop: emitted == budget ? .budget : .work)
    }
#if STAGE_C
#if EPOCH_PAGES
    func stageCPreparePages() { hotPages.preparePool(); coldPages.buffer.preparePool(); groupPages.preparePool(); wheel.stageCPreparePages() }
    func stageCCanFreezePages(_ epoch: UInt32) -> Bool {
        hotPages.canFreeze(epoch: epoch) && coldPages.buffer.canFreeze(epoch: epoch) &&
        groupPages.canFreeze(epoch: epoch) && wheel.stageCCanFreezePages(epoch)
    }
    func stageCFreezePages(_ epoch: UInt32) -> FrozenStageCSnapshot {
        precondition(stageCCanFreezePages(epoch))
        let control = Snapshot.controlRecord(self)
        return FrozenStageCSnapshot(epoch: epoch, control: control,
            layout: .h(hot: hotPages.freeze(epoch: epoch), cold: coldPages.buffer.freeze(epoch: epoch),
                       nodes: wheel.stageCFreezePages(epoch), groups: groupPages.freeze(epoch: epoch)))
    }
    func stageCAppendAssetPage(_ chunk: Int, into bytes: inout [UInt8]) {
        let start = chunk << 8, elements = min(256, count - start)
        hotPages.appendRows(start..<(start + elements), into: &bytes)
        coldPages.buffer.appendPackedPage(chunk, payloadBytes: elements * 20, into: &bytes)
    }
    @inline(__always) func stageCNeedsAssetCopy(_ index: Int) -> Bool { hotPages.needsCopy(page: index >> 8) }
    @inline(__always) func stageCNeedsColdAssetCopy(_ index: Int) -> Bool { coldPages.buffer.needsCopy(page: index >> 8) }
    @inline(__always) func stageCNeedsGroupCopy(_ index: Int) -> Bool { groupPages.needsCopy(page: index >> 11) }
    func stageCCloneAsset(_ index: Int) -> Int {
        hotPages.ensureWritable(page: index >> 8)
    }
    func stageCCloneColdAsset(_ index: Int) -> Int { coldPages.buffer.ensureWritable(page: index >> 8) }
    func stageCCloneGroup(_ index: Int) -> Int { groupPages.ensureWritable(page: index >> 11) }
    func stageCReleasePages(_ completion: StageCEpochCompletion) {
        precondition(completion.ownerID == ObjectIdentifier(self))
        let epoch = completion.epoch
        hotPages.releaseCompleted(epoch: epoch); coldPages.buffer.releaseCompleted(epoch: epoch)
        groupPages.releaseCompleted(epoch: epoch); wheel.stageCReleasePages(epoch)
    }
#endif
    func stageCInstall(_ state: StageCState) { stageCState=state; wheel.stageCState=state }
    func stageCUninstall() { wheel.stageCState=nil; stageCState=nil }
    func restoreScalars(now:UInt64,revenue:Int64,receivable:Int64,cash:Int64,processed:UInt64,hash:UInt64) throws {
        guard wheel.pending==0,revenue>=0,receivable>=0,cash>=0 else { throw ProbeError.corruption("stage C hybrid snapshot balances") }
        self.now=now;self.revenue=revenue;self.receivable=receivable;self.cash=cash
        self.processed=processed;sequenceHash=hash;try wheel.restoreCursor(now)
    }
    func stageCRestoreAsset(_ i:Int,hot value:HotAsset,entity:UInt32,policy:UInt32,origin:UInt32,departure:UInt64) throws {
        guard i>=0 && i<count,value.airport>0,value.destination>0,origin>0,value.fare>=0,value.active<=1,
              value.reserved0==0,value.reserved1==0,Int(value.contract)<groupAmounts.count,entity<32 else {
            throw ProbeError.corruption("stage C hybrid asset")
        }
        writeHot(i, value);writeEntity(i, entity);writePolicy(i, policy);writeOrigin(i, origin);writeDeparture(i, departure)
    }
    func restoreGroup(_ i:Int,_ amount:Int64) throws {
        guard i>=0 && i<groupAmounts.count,amount>=0 else { throw ProbeError.corruption("stage C hybrid group") }
        writeGroupAmounts(i, amount)
    }
    func stageCAppendControl(into data:inout [UInt8]) {
        Snapshot.appendLE(UInt32(count),into:&data);Snapshot.appendLE(UInt32(wheel.capacity),into:&data)
        Snapshot.appendLE(UInt32(groupAmounts.count),into:&data);Snapshot.appendLE(now,into:&data)
        Snapshot.appendLE(revenue,into:&data);Snapshot.appendLE(receivable,into:&data);Snapshot.appendLE(cash,into:&data)
        Snapshot.appendLE(processed,into:&data);Snapshot.appendLE(sequenceHash,into:&data)
        Snapshot.appendLE(UInt64(rejectedStale),into:&data);Snapshot.appendLE(changeEpoch,into:&data)
        wheel.stageCAppendControl(into:&data)
    }
    func stageCRestoreExtras(rejected:Int,changeEpoch restoredEpoch:UInt32) throws {
        guard rejected>=0 else { throw ProbeError.corruption("stage C hybrid rejected count") }
        rejectedStale=rejected;changeEpoch=restoredEpoch
    }
#endif
}

func drainHybrid(_ world: HybridWorld, target: UInt64, budget: Int = 256,
                 checks: Int = Int.max, expected: [Completion]? = nil,
                 inject: UInt64? = nil) throws -> [Completion] {
    var values: [Completion] = []
    values.reserveCapacity(expected?.count ?? world.count)
    var calls = 0
    while true {
        let p = try world.advance(to: target, budget: budget, checkLimit: checks, injectFailureAt: inject)
        for i in 0..<p.events {
            let c = world.output(i)
            if let expected {
                try require(values.count < expected.count && c == expected[values.count],
                            "hybrid ordered event \(values.count)")
            }
            values.append(c)
        }
        calls += 1
        try require(calls < world.count * 100 + 100_000, "hybrid nonterminating wheel")
        if p.stop == .blocked { throw ProbeError.blocked }
        if p.stop == .target { break }
    }
    if let expected { try require(values == expected, "hybrid complete ordered transcript") }
    return values
}

func hybridOrderChecks(_ count: Int) throws -> [String: Any] {
    let expected = reference(count)
    var legacyCases = 0
    if count <= 100_000 {
        for b in [1, 7, 31, 256, 1024] {
            try require(try legacyTranscript(count, budget: b) == expected, "hybrid/R004 event-by-event b=\(b)")
            legacyCases += 1
        }
    }
    var countCases = 0
    var injectedCases = 0
    var actualCases = 0
    for budget in [1, 7, 31, 256, 1024] {
        let countWorld = try HybridWorld(count: count)
        try countWorld.seedFixture()
        _ = try drainHybrid(countWorld, target: 600, budget: budget, expected: expected)
        countCases += 1

        let injectedWorld = try HybridWorld(count: count)
        try injectedWorld.seedFixture()
        _ = try drainHybrid(injectedWorld, target: 600, budget: budget, checks: 19, expected: expected)
        injectedCases += 1

        let actualWorld = try HybridWorld(count: count)
        try actualWorld.seedFixture()
        var position = 0
        var calls = 0
        var timeStops = 0
        while true {
            let p = try actualWorld.advance(to: 600, budget: budget, deadlineNS: nx_now() + 10_000)
            for i in 0..<p.events {
                try require(position < expected.count && actualWorld.output(i) == expected[position],
                            "hybrid actual-clock event \(position)")
                position += 1
            }
            calls += 1
            if p.stop == .time { timeStops += 1 }
            try require(p.stop != .blocked && calls < count * 100 + 100_000,
                        "hybrid actual-clock liveness")
            if p.stop == .target { break }
        }
        try require(position == count && actualWorld.revenue == expected.reduce(0, { $0 + $1.amount }),
                    "hybrid actual-clock transcript/state")
        actualCases += 1
        _ = timeStops
    }
    return ["status":"pass", "assets":count, "countCases":countCases,
            "injectedClockCases":injectedCases, "actualClockCases":actualCases,
            "partitionCases":countCases + injectedCases + actualCases,
            "legacyExactTranscriptCases":legacyCases,
            "independentSortedReferenceEvents":count]
}

func hybridCustom(_ mutation: Mutation = .none, high: Bool = false) throws -> (HybridWorld, [Completion]) {
    let w = try HybridWorld(count: 4, mutation: mutation)
    let times: [UInt64] = high ? [65536, 65536, 65536, 65536] : [9, 9, 9, 9]
    for i in [3, 1, 2, 0] {
        try w.schedule(asset: i, due: times[i], operation: UInt64(i + 1), amount: Int64(i + 1))
    }
    var e: [Completion] = []
    for i in 0..<4 {
        let ev = Event(due: times[i], operation: UInt64(i + 1), asset: UInt32(i), generation: 0, kind: 0)
        e.append(Completion(event: ev, amount: Int64(i + 1), completed: 1))
    }
    return (w, e)
}

func hybridMutationChecks() throws -> [[String: Any]] {
    for high in [false, true] {
        let (w, e) = try hybridCustom(high: high)
        _ = try drainHybrid(w, target: high ? 65536 : 9, budget: 1, checks: 3, expected: e)
    }
    let clean = try HybridWorld(count: 1)
    try clean.schedule(asset: 0, due: 1, operation: 1, amount: 11)
    try clean.invalidateGeneration(0)
    do {
        _ = try drainHybrid(clean, target: 1)
        throw ProbeError.mismatch("hybrid negative-control stale acceptance")
    } catch ProbeError.blocked {
        try require(clean.revenue == 0 && clean.wheel.pending == 1, "hybrid clean stale changed state")
    }
    var results: [[String: Any]] = []
    for fault in Mutation.allCases where fault != .none {
        var killed = false
        var evidence = ""
        do {
            if fault == .acceptStaleGeneration {
                let mutant = try HybridWorld(count: 1, mutation: fault)
                try mutant.schedule(asset: 0, due: 1, operation: 1, amount: 11)
                try mutant.invalidateGeneration(0)
                _ = try drainHybrid(mutant, target: 1)
                try require(mutant.revenue == 0 && mutant.wheel.pending == 1,
                            "hybrid stale generation illegally committed")
            } else {
                let high = fault == .reverseCascade
                let (w, e) = try hybridCustom(fault, high: high)
                _ = try drainHybrid(w, target: high ? 65536 : 9, budget: 1, checks: 3, expected: e)
            }
        } catch {
            killed = true
            evidence = String(describing: error)
        }
        results.append(["fault":fault.rawValue, "detected":killed,
                        "test":fault == .acceptStaleGeneration ? "stale_no_commit" : "exact_sorted_transcript",
                        "evidence":evidence])
        try require(killed, "HYBRID SURVIVING MUTANT: \(fault.rawValue)")
    }
    return results
}

private func quantile(_ values: [UInt64], numerator: Int, denominator: Int) -> UInt64 {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, (sorted.count * numerator) / denominator)
    return sorted[index]
}

private func benchSOnce(_ count: Int, budget: Int) throws -> [String: Any] {
    let before = nx_footprint()
    let w = try SwiftWorld(count: count)
    try w.seedFixture()
    let after = nx_footprint()
    var calls = 0
    var events = 0
    var totalNS: UInt64 = 0
    var maxAlloc: UInt64 = 0
    var times: [UInt64] = []
    times.reserveCapacity(count / budget + 16)
    while true {
        nx_alloc_begin()
        let start = nx_now()
        let p = try w.advance(to: 600, budget: budget)
        let finish = nx_now()
        let a = nx_alloc_end()
        let elapsed = finish - start
        times.append(elapsed)
        calls += 1
        events += p.events
        totalNS += elapsed
        maxAlloc = max(maxAlloc, a.calls)
        if p.stop == .target { break }
        try require(p.stop != .blocked, "S benchmark blocked")
    }
    try require(events == count && w.processed == UInt64(count), "S benchmark events")
    return ["variant":"S", "assets":count, "events":events, "advanceCalls":calls,
            "ownedBytes":w.ownedBytes, "ownedBytesPerAsset":Double(w.ownedBytes) / Double(count),
            "physDeltaPerAsset":after.status == 0 && before.status == 0 ?
                Double(Int64(after.bytes) - Int64(before.bytes)) / Double(count) as Any : NSNull(),
            "nsPerEvent":Double(totalNS) / Double(count),
            "advanceCallNS":["p50":quantile(times, numerator: 50, denominator: 100),
                             "p99":quantile(times, numerator: 99, denominator: 100),
                             "max":times.max() ?? 0],
            "maxAllocationsPerAdvance":maxAlloc,
            "sequenceHash":w.sequenceHash,
            "revenue":w.revenue]
}

private func benchHOnce(_ count: Int, budget: Int) throws -> [String: Any] {
    let before = nx_footprint()
    let w = try HybridWorld(count: count)
    try w.seedFixture()
    let after = nx_footprint()
    var calls = 0
    var events = 0
    var totalNS: UInt64 = 0
    var maxAlloc: UInt64 = 0
    var times: [UInt64] = []
    times.reserveCapacity(count / budget + 16)
    while true {
        nx_alloc_begin()
        let start = nx_now()
        let p = try w.advance(to: 600, budget: budget)
        let finish = nx_now()
        let a = nx_alloc_end()
        let elapsed = finish - start
        times.append(elapsed)
        calls += 1
        events += p.events
        totalNS += elapsed
        maxAlloc = max(maxAlloc, a.calls)
        if p.stop == .target { break }
        try require(p.stop != .blocked, "H benchmark blocked")
    }
    try require(events == count && w.processed == UInt64(count), "H benchmark events")
    return ["variant":"H", "assets":count, "events":events, "advanceCalls":calls,
            "ownedBytes":w.ownedBytes, "ownedBytesPerAsset":Double(w.ownedBytes) / Double(count),
            "physDeltaPerAsset":after.status == 0 && before.status == 0 ?
                Double(Int64(after.bytes) - Int64(before.bytes)) / Double(count) as Any : NSNull(),
            "nsPerEvent":Double(totalNS) / Double(count),
            "advanceCallNS":["p50":quantile(times, numerator: 50, denominator: 100),
                             "p99":quantile(times, numerator: 99, denominator: 100),
                             "max":times.max() ?? 0],
            "maxAllocationsPerAdvance":maxAlloc,
            "sequenceHash":w.sequenceHash,
            "revenue":w.revenue]
}

func stageABenchmark(variant: String, count: Int, measuredRuns: Int) throws -> [String: Any] {
    guard ["S", "H"].contains(variant), [100_000, 1_000_000, 2_000_000].contains(count),
          measuredRuns == 10 else { throw ProbeError.invalid("stage A benchmark arguments") }
    _ = nx_now()
    _ = nx_footprint()
    nx_alloc_begin()
    _ = nx_alloc_end()
    let cAlloc = nx_alloc_calibrate()
    nx_alloc_begin()
    let control = allocationControl(8193)
    let swiftControl = nx_alloc_end()
    try require(control == 8193 * 7 + 2, "allocation positive control computation")
    #if os(macOS)
    try require(cAlloc > 0 && swiftControl.calls > 0, "allocator hooks not observing actual C/Swift allocations")
    #endif

    for _ in 0..<2 {
        if variant == "S" { _ = try benchSOnce(count, budget: 256) }
        else { _ = try benchHOnce(count, budget: 256) }
    }
    var samples: [[String: Any]] = []
    samples.reserveCapacity(measuredRuns)
    for run in 1...measuredRuns {
        var value = variant == "S" ? try benchSOnce(count, budget: 256) : try benchHOnce(count, budget: 256)
        value["run"] = run
        samples.append(value)
    }
    return ["status":"pass", "variant":variant, "assets":count,
            "warmups":2, "measuredRuns":measuredRuns,
            "cAllocationPositiveControl":cAlloc,
            "swiftAllocationPositiveControl":swiftControl.calls,
            "samples":samples]
}
