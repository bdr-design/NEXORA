import Foundation
import ProbePlatform

struct HotAsset: BitwiseCopyable, Equatable {
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

struct EventNode: BitwiseCopyable, Equatable {
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
    private(set) var nodes: ContiguousArray<EventNode>
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

    init(capacity: Int, mutation: Mutation = .none) throws {
        guard capacity > 0, capacity <= 2_000_000 else { throw ProbeError.invalid("wheel capacity") }
        self.mutation = mutation
        nodes = .init(repeating: EventNode(), count: capacity)
        if capacity > 1 {
            for i in 0..<(capacity - 1) { nodes[i].next = UInt32(i + 1) }
        }
        nodes[capacity - 1].next = none
        free = 0
    }

    var capacity: Int { nodes.count }

    var ownedBytes: Int {
        nodes.capacity * MemoryLayout<EventNode>.stride +
        (heads.capacity + tails.capacity) * MemoryLayout<UInt32>.stride +
        sorted.capacity * MemoryLayout<Bool>.stride +
        occupied.capacity * MemoryLayout<UInt64>.stride
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
        nodes[i].next = none
        if tail == none {
            heads[b] = id
            tails[b] = id
            sorted[b] = true
            setOccupied(b, true)
        } else if mutation == .reverseCascade && cascading {
            nodes[i].next = heads[b]
            heads[b] = id
            sorted[b] = true
        } else {
            if nodes[Int(tail)].operation > nodes[i].operation { sorted[b] = false }
            nodes[Int(tail)].next = id
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
        nodes[i] = EventNode(due: event.due, operation: event.operation, asset: event.asset,
                             generation: event.generation, next: none, kind: event.kind, live: 1)
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
                if outTail != none { nodes[Int(outTail)].next = none }
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
            if outTail == none { outHead = picked } else { nodes[Int(outTail)].next = picked }
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
                nodes[Int(id)].next = nodes[Int(b)].next
                nodes[Int(b)].next = id
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
        heads[leaf] = nodes[Int(id)].next
        nodes[Int(id)].live = 0
        nodes[Int(id)].next = free
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
}

final class HybridWorld {
    let count: Int
    let wheel: HybridTimingWheel
    private(set) var hot: ContiguousArray<HotAsset>
    private(set) var entity: ContiguousArray<UInt32>
    private(set) var policy: ContiguousArray<UInt32>
    private(set) var origin: ContiguousArray<UInt32>
    private(set) var departure: ContiguousArray<UInt64>
    private(set) var groupAmounts: ContiguousArray<Int64>
    private var outputs: ContiguousArray<Completion>
    private(set) var now: UInt64 = 0
    private(set) var revenue: Int64 = 0
    private(set) var receivable: Int64 = 0
    private(set) var cash: Int64 = 1_000
    private(set) var processed: UInt64 = 0
    private(set) var sequenceHash: UInt64 = 14695981039346656037
    private(set) var rejectedStale = 0
    private(set) var changeEpoch: UInt32 = 1

    init(count: Int, eventCapacity: Int? = nil, mutation: Mutation = .none) throws {
        guard (1...2_000_000).contains(count) else { throw ProbeError.invalid("asset capacity") }
        self.count = count
        wheel = try HybridTimingWheel(capacity: eventCapacity ?? count, mutation: mutation)
        hot = .init(repeating: HotAsset(), count: count)
        entity = .init(repeating: 0, count: count)
        policy = .init(repeating: 0, count: count)
        origin = .init(repeating: 1, count: count)
        departure = .init(repeating: 0, count: count)
        groupAmounts = .init(repeating: 0, count: (count + 15) / 16)
        outputs = .init(repeating: .empty, count: 1024)
        for i in 0..<count {
            hot[i].contract = UInt32(i / 16)
            entity[i] = UInt32(i % 32)
        }
    }

    var ownedBytes: Int {
        wheel.ownedBytes +
        hot.capacity * MemoryLayout<HotAsset>.stride +
        (entity.capacity + policy.capacity + origin.capacity) * MemoryLayout<UInt32>.stride +
        departure.capacity * MemoryLayout<UInt64>.stride +
        groupAmounts.capacity * MemoryLayout<Int64>.stride +
        outputs.capacity * MemoryLayout<Completion>.stride
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
        _ = try wheel.schedule(Event(due: due, operation: operation, asset: UInt32(i),
                                     generation: hot[i].generation, kind: kind))
        origin[i] = hot[i].airport
        departure[i] = now
        hot[i].fare = amount
        hot[i].active = 1
    }

    func invalidateGeneration(_ i: Int) throws {
        guard i >= 0 && i < count, hot[i].generation < UInt32.max else { throw ProbeError.invalid("generation") }
        hot[i].generation += 1
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
                revenue = r.partialValue
                receivable = d.partialValue
                groupAmounts[g] = s.partialValue
                cash = c.partialValue
                a.accruedOperation = e.operation
                a.completed += 1
                a.active = 0
                a.airport = a.destination
                a.changeEpoch = changeEpoch
                hot[i] = a
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
