import Foundation
import ProbePlatform

enum ProbeError: Error, CustomStringConvertible {
    case invalid(String), invariant(String), mismatch(String), blocked, corruption(String)
    var description: String { switch self {
    case .invalid(let s): return "invalid: " + s
    case .invariant(let s): return "invariant: " + s
    case .mismatch(let s): return "mismatch: " + s
    case .blocked: return "blocked"
    case .corruption(let s): return "corruption: " + s
    } }
}
@inline(__always) func require(_ ok: Bool, _ message: @autoclosure () -> String) throws {
    if !ok { throw ProbeError.mismatch(message()) }
}
let none = UInt32.max
struct Event: Equatable, Codable {
    var due: UInt64
    var operation: UInt64
    var asset: UInt32
    var generation: UInt32
    var kind: UInt8
    static let empty = Event(due: 0, operation: 0, asset: none, generation: 0, kind: 0)
}
struct Completion: Equatable, Codable {
    var event: Event
    var amount: Int64
    var completed: UInt64
    static let empty = Completion(event: .empty, amount: 0, completed: 0)
}
enum Mutation: String, CaseIterable, Codable {
    case none, swapTie, omitTieBreaker, slotPlusOne, slotMinusOne
    case reverseCascade, duplicate, missing, acceptStaleGeneration
}
enum WheelStep { case work, ready(UInt32), drained, beyondTarget }

/// Single-owner safe Swift storage. No pointers, unchecked indexing or C state.
/// Hierarchical 8x256 wheel, exact UInt64 times, resumable cascade and linked merge-sort.
/// Bucket order is proved dynamically; an already sorted bucket avoids sorting work.
final class TimingWheel {
    private(set) var due: ContiguousArray<UInt64>
    private(set) var operation: ContiguousArray<UInt64>
    private(set) var asset: ContiguousArray<UInt32>
    private(set) var generation: ContiguousArray<UInt32>
    private(set) var kind: ContiguousArray<UInt8>
    private(set) var live: ContiguousArray<UInt8>
    private var next: ContiguousArray<UInt32>
    private var heads = ContiguousArray(repeating: none, count: 2048)
    private var tails = ContiguousArray(repeating: none, count: 2048)
    private var sorted = ContiguousArray(repeating: true, count: 2048)
    private var occupied = ContiguousArray(repeating: UInt64(0), count: 32)
    private var free: UInt32 = none
    private(set) var pending = 0
    private(set) var cursor: UInt64 = 0
    private var cascade = -1
    private var leaf = -1
    // Fixed scalar continuation for bottom-up stable intrusive merge sort.
    private var sortPhase = 0, width = 1, merges = 0, seek = 0, leftCount = 0, rightCount = 0
    private var pair: UInt32 = none, left: UInt32 = none, right: UInt32 = none
    private var outHead: UInt32 = none, outTail: UInt32 = none
    let mutation: Mutation
    private var fired = false
    private var ghost: Event? = nil
#if STAGE_C
    var stageCState: StageCState? = nil
#endif
    init(capacity: Int, mutation: Mutation = .none) throws {
        guard capacity > 0, capacity <= 2_000_000 else { throw ProbeError.invalid("wheel capacity") }
        self.mutation = mutation
        due = .init(repeating: 0, count: capacity)
        operation = .init(repeating: 0, count: capacity)
        asset = .init(repeating: none, count: capacity)
        generation = .init(repeating: 0, count: capacity)
        kind = .init(repeating: 0, count: capacity)
        live = .init(repeating: 0, count: capacity)
        next = .init(repeating: none, count: capacity)
        for i in 0..<(capacity - 1) { next[i] = UInt32(i + 1) }; free = 0
    }
    var capacity: Int { due.count }
    var ownedBytes: Int {
        (due.capacity + operation.capacity) * 8 +
        (asset.capacity + generation.capacity + next.capacity + heads.capacity + tails.capacity) * 4 +
        kind.capacity + live.capacity + sorted.capacity * MemoryLayout<Bool>.stride + occupied.capacity * 8
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
        let word = b / 64, mask = UInt64(1) << (b % 64)
        if value { occupied[word] |= mask } else { occupied[word] &= ~mask }
    }
    @inline(__always) private func insertNode(_ id: UInt32, into b: Int, cascading: Bool = false) {
        let i = Int(id), tail = tails[b]
#if STAGE_C
        stageCState?.willWriteNode(self, index: i)
#endif
        next[i] = none
        if tail == none {
            heads[b] = id; tails[b] = id; sorted[b] = true; setOccupied(b, true)
        } else if mutation == .reverseCascade && cascading {
            // Real mutation: a head-insertion cascade incorrectly retains its sorted certificate.
#if STAGE_C
            stageCState?.willWriteNode(self, index: i)
#endif
            next[i] = heads[b]; heads[b] = id; sorted[b] = true
        } else {
            if operation[Int(tail)] > operation[i] { sorted[b] = false }
#if STAGE_C
            stageCState?.willWriteNode(self, index: Int(tail))
#endif
            next[Int(tail)] = id; tails[b] = id
        }
        if mutation == .omitTieBreaker { sorted[b] = true }
    }
    func schedule(_ event: Event) throws -> UInt32 {
        guard event.due >= cursor, event.operation > 0, free != none else { throw ProbeError.invalid("schedule") }
        guard sortPhase == 0 && leaf == -1 && cascade == -1 else { throw ProbeError.invalid("schedule during wheel continuation") }
        let id = free, i = Int(id); free = next[i]
#if STAGE_C
        stageCState?.willWriteNode(self, index: i)
#endif
        due[i] = event.due; operation[i] = event.operation; asset[i] = event.asset
        generation[i] = event.generation; kind[i] = event.kind; live[i] = 1
        insertNode(id, into: bucket(event.due)); pending += 1
        return id
    }
    @inline(__always) func event(_ id: UInt32) -> Event {
        let i = Int(id)
        return Event(due: due[i], operation: operation[i], asset: asset[i], generation: generation[i], kind: kind[i])
    }
    func restoreCursor(_ time: UInt64) throws {
        guard pending == 0 else { throw ProbeError.invalid("restore cursor with pending events") }
        cursor = time
    }
    private func startSort() {
        width = 1; pair = heads[leaf]; outHead = none; outTail = none; merges = 0; sortPhase = 1
    }
    /// At most one pointer walk or output-node link per step; large ties cannot hide an unbounded sort.
    private func sortStep() throws {
        switch sortPhase {
        case 1:
            if pair == none {
                if outTail != none {
#if STAGE_C
                    stageCState?.willWriteNode(self, index: Int(outTail))
#endif
                    next[Int(outTail)] = none
                }
                heads[leaf] = outHead; tails[leaf] = outTail
                if merges <= 1 { sorted[leaf] = true; sortPhase = 0; return }
                guard width <= capacity else { throw ProbeError.invariant("sort bound") }
                width *= 2; pair = outHead; outHead = none; outTail = none; merges = 0
                return
            }
            merges += 1; left = pair; right = pair; leftCount = 0; seek = width; sortPhase = 2
        case 2:
            if seek > 0 && right != none {
                right = next[Int(right)]; leftCount += 1; seek -= 1
            } else { rightCount = width; sortPhase = 3 }
        case 3:
            if leftCount == 0 && (rightCount == 0 || right == none) { pair = right; sortPhase = 1; return }
            let chooseLeft = leftCount > 0 && (rightCount == 0 || right == none || operation[Int(left)] <= operation[Int(right)])
            let picked: UInt32
            if chooseLeft { picked = left; left = next[Int(left)]; leftCount -= 1 }
            else { picked = right; right = next[Int(right)]; rightCount -= 1 }
            if outTail == none { outHead = picked } else {
#if STAGE_C
                stageCState?.willWriteNode(self, index: Int(outTail))
#endif
                next[Int(outTail)] = picked
            }
            outTail = picked
        default: throw ProbeError.invariant("sort phase")
        }
    }
    func step(target: UInt64) throws -> WheelStep {
        if sortPhase != 0 { try sortStep(); return .work }
        if cascade >= 0 {
            let id = heads[cascade]
            if id == none { setOccupied(cascade, false); tails[cascade] = none; cascade = -1; return .work }
            heads[cascade] = next[Int(id)]
            let b = bucket(due[Int(id)])
            guard b / 256 < cascade / 256 else { throw ProbeError.invariant("cascade does not lower level") }
            insertNode(id, into: b, cascading: true)
            return .work
        }
        if leaf >= 0 {
            let id = heads[leaf]
            if id == none { setOccupied(leaf, false); tails[leaf] = none; leaf = -1; return .work }
            if !sorted[leaf] { startSort(); return .work }
            if mutation == .swapTie && !fired && next[Int(id)] != none {
                let b = next[Int(id)]
#if STAGE_C
                stageCState?.willWriteNode(self, index: Int(id))
                stageCState?.willWriteNode(self, index: Int(b))
#endif
                next[Int(id)] = next[Int(b)]; next[Int(b)] = id; heads[leaf] = b; fired = true
            }
            let ready = heads[leaf]
            guard due[Int(ready)] == cursor else { throw ProbeError.invariant("wrong wheel slot/time") }
            if mutation == .missing && !fired { _ = try consume(ready); fired = true; return .work }
            return .ready(ready)
        }
        if pending == 0 { return .drained }
        var candidateBucket = -1, candidateTime = UInt64.max
        // Fixed 32-word occupancy query, independent of N or the empty time horizon.
        for level in 0..<8 {
            for word in 0..<4 {
                let bits = occupied[level * 4 + word]
                if bits == 0 { continue }
                let slot = word * 64 + bits.trailingZeroBitCount, shift = level * 8
                let high: UInt64 = level == 7 ? 0 : cursor & (UInt64.max << (shift + 8))
                let start = high | (UInt64(slot) << shift)
                guard start >= cursor else { throw ProbeError.invariant("past occupied bucket") }
                if candidateBucket == -1 || start < candidateTime { candidateBucket = level * 256 + slot; candidateTime = start }
                break
            }
        }
        guard candidateBucket >= 0 else { throw ProbeError.invariant("lost live event") }
        if candidateTime > target { return .beyondTarget }
        cursor = candidateTime
        if candidateBucket / 256 == 0 { leaf = candidateBucket }
        else { cascade = candidateBucket }
        return .work
    }
    func consume(_ id: UInt32) throws -> Event {
        guard leaf >= 0, heads[leaf] == id, live[Int(id)] == 1 else { throw ProbeError.invariant("consume non-head") }
        let value = event(id)
#if STAGE_C
        stageCState?.willWriteNode(self, index: Int(id))
#endif
        heads[leaf] = next[Int(id)]
        live[Int(id)] = 0; next[Int(id)] = free; free = id; pending -= 1
        if mutation == .duplicate && !fired { ghost = value; fired = true }
        return value
    }
    func takeGhost() -> Event? { let value = ghost; ghost = nil; return value }
#if STAGE_C
    func stageCAppendNodeChunk(_ range: Range<Int>, into data: inout [UInt8]) {
        Snapshot.append(due, range, into: &data)
        Snapshot.append(operation, range, into: &data)
        Snapshot.append(asset, range, into: &data)
        Snapshot.append(generation, range, into: &data)
        Snapshot.append(next, range, into: &data)
        Snapshot.append(kind, range, into: &data)
        Snapshot.append(live, range, into: &data)
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
        Snapshot.appendLE(pair, into: &data)
        Snapshot.appendLE(left, into: &data)
        Snapshot.appendLE(right, into: &data)
        Snapshot.appendLE(outHead, into: &data)
        Snapshot.appendLE(outTail, into: &data)
        Snapshot.append(heads, 0..<heads.count, into: &data)
        Snapshot.append(tails, 0..<tails.count, into: &data)
        Snapshot.appendBoolBytes(sorted, 0..<sorted.count, into: &data)
        Snapshot.append(occupied, 0..<occupied.count, into: &data)
    }
    func stageCRestoreControl(_ c: StageCWheelControl) throws {
        guard c.heads.count == 2048, c.tails.count == 2048, c.sorted.count == 2048,
              c.occupied.count == 32, c.pending >= 0, c.pending <= capacity else {
            throw ProbeError.corruption("stage C wheel control")
        }
        cursor = c.cursor; pending = c.pending; free = c.free
        cascade = c.cascade; leaf = c.leaf; sortPhase = c.sortPhase; width = c.width
        merges = c.merges; seek = c.seek; leftCount = c.leftCount; rightCount = c.rightCount
        pair = c.pair; left = c.left; right = c.right; outHead = c.outHead; outTail = c.outTail
        heads = ContiguousArray(c.heads); tails = ContiguousArray(c.tails)
        sorted = ContiguousArray(c.sorted); occupied = ContiguousArray(c.occupied)
        fired = false; ghost = nil
    }
    func stageCRestoreNode(_ i: Int, due valueDue: UInt64, operation valueOperation: UInt64,
                           asset valueAsset: UInt32, generation valueGeneration: UInt32,
                           next valueNext: UInt32, kind valueKind: UInt8, live valueLive: UInt8) throws {
        guard i >= 0 && i < capacity, valueKind <= 2, valueLive <= 1 else {
            throw ProbeError.corruption("stage C node")
        }
        due[i] = valueDue; operation[i] = valueOperation; asset[i] = valueAsset
        generation[i] = valueGeneration; next[i] = valueNext; kind[i] = valueKind; live[i] = valueLive
    }
#endif
}

struct SliceResult {
    enum Stop: String { case budget, time, work, target, blocked }
    var events: Int
    var units: Int
    var reached: UInt64
    var stop: Stop
}
/// State owner's arrays never escape. All snapshots/serialization are explicitly outside advance.
final class SwiftWorld {
    let count: Int
    let wheel: TimingWheel
    private(set) var generations: ContiguousArray<UInt32>
    private(set) var airports: ContiguousArray<UInt32>
    private(set) var destinations: ContiguousArray<UInt32>
    private(set) var departures: ContiguousArray<UInt64>
    private(set) var fares: ContiguousArray<Int64>
    private(set) var completed: ContiguousArray<UInt64>
    private(set) var accruedOperations: ContiguousArray<UInt64>
    private(set) var active: ContiguousArray<UInt8>
    private(set) var contracts: ContiguousArray<UInt32>
    private(set) var changeEpochs: ContiguousArray<UInt32>
    private(set) var entities: ContiguousArray<UInt32>
    private(set) var policies: ContiguousArray<UInt32>
    private(set) var origins: ContiguousArray<UInt32>
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
#if STAGE_C
    var stageCState: StageCState? = nil
#endif
    init(count: Int, eventCapacity: Int? = nil, mutation: Mutation = .none) throws {
        guard (1...2_000_000).contains(count) else { throw ProbeError.invalid("asset capacity") }
        self.count = count; wheel = try TimingWheel(capacity: eventCapacity ?? count, mutation: mutation)
        generations = .init(repeating: 0, count: count); airports = .init(repeating: 1, count: count)
        destinations = .init(repeating: 2, count: count); departures = .init(repeating: 0, count: count)
        fares = .init(repeating: 0, count: count); completed = .init(repeating: 0, count: count)
        accruedOperations = .init(repeating: 0, count: count); active = .init(repeating: 0, count: count)
        contracts = .init(repeating: 0, count: count); changeEpochs = .init(repeating: 0, count: count)
        entities = .init(repeating: 0, count: count); policies = .init(repeating: 0, count: count)
        origins = .init(repeating: 1, count: count)
        groupAmounts = .init(repeating: 0, count: (count + 15) / 16)
        outputs = .init(repeating: .empty, count: 1024)
        for i in 0..<count { contracts[i] = UInt32(i / 16); entities[i] = UInt32(i % 32) }
    }
    var ownedBytes: Int {
        wheel.ownedBytes +
        (generations.capacity + airports.capacity + destinations.capacity + contracts.capacity +
         changeEpochs.capacity + entities.capacity + policies.capacity + origins.capacity) * 4 +
        (departures.capacity + fares.capacity + completed.capacity + accruedOperations.capacity) * 8 +
        active.capacity + groupAmounts.capacity * 8 + outputs.capacity * MemoryLayout<Completion>.stride
    }
    func output(_ index: Int) -> Completion { outputs[index] }
    func seedFixture() throws {
        for i in 0..<count {
            try schedule(asset: i, due: UInt64(i % 600 + 1), operation: UInt64(count + i + 1), amount: Int64(i % 97 + 101))
        }
    }
    func schedule(asset i: Int, due: UInt64, operation: UInt64, amount: Int64, kind: UInt8 = 0) throws {
        guard i >= 0 && i < count, active[i] == 0, due >= now, amount > 0, kind <= 2,
              operation > accruedOperations[i] else { throw ProbeError.invalid("asset schedule") }
#if STAGE_C
        stageCState?.willWriteAsset(self, index: i)
#endif
        _ = try wheel.schedule(Event(due: due, operation: operation, asset: UInt32(i), generation: generations[i], kind: kind))
        origins[i] = airports[i]; departures[i] = now; fares[i] = amount; active[i] = 1
    }
    func invalidateGeneration(_ i: Int) throws {
        guard i >= 0 && i < count, generations[i] < UInt32.max else { throw ProbeError.invalid("generation") }
#if STAGE_C
        stageCState?.willWriteAsset(self, index: i)
#endif
        generations[i] += 1
    }
    func addCash(_ value: Int64) throws {
        let sum = cash.addingReportingOverflow(value)
        guard !sum.overflow, sum.partialValue >= 0 else { throw ProbeError.invalid("cash") }; cash = sum.partialValue
    }
    func restoreScalars(now: UInt64, revenue: Int64, receivable: Int64, cash: Int64, processed: UInt64, hash: UInt64) throws {
        guard wheel.pending == 0, revenue >= 0, receivable >= 0, cash >= 0 else { throw ProbeError.corruption("snapshot balances") }
        self.now = now; self.revenue = revenue; self.receivable = receivable; self.cash = cash
        self.processed = processed; sequenceHash = hash; try wheel.restoreCursor(now)
    }
    func restoreAsset(_ i: Int, gen: UInt32, airport: UInt32, destination: UInt32, departure: UInt64,
                      fare: Int64, trips: UInt64, last: UInt64, active: UInt8,
                      contract: UInt32, assetChangeEpoch: UInt32, entity: UInt32,
                      policy: UInt32, origin: UInt32) throws {
        guard airport > 0, destination > 0, origin > 0, fare >= 0, active <= 1,
              Int(contract) < groupAmounts.count, entity < 32 else { throw ProbeError.corruption("asset columns") }
        generations[i] = gen; airports[i] = airport; destinations[i] = destination; departures[i] = departure
        fares[i] = fare; completed[i] = trips; accruedOperations[i] = last; self.active[i] = active
        contracts[i] = contract; changeEpochs[i] = assetChangeEpoch; entities[i] = entity
        policies[i] = policy; origins[i] = origin
    }
    func restoreGroup(_ i: Int, _ amount: Int64) throws {
        guard amount >= 0 else { throw ProbeError.corruption("group amount") }; groupAmounts[i] = amount
    }
    @inline(__always) private func hash(_ event: Event, _ amount: Int64) {
        sequenceHash = (sequenceHash ^ event.due) &* 1099511628211
        sequenceHash = (sequenceHash ^ event.operation) &* 1099511628211
        sequenceHash = (sequenceHash ^ UInt64(event.asset)) &* 1099511628211
        sequenceHash = (sequenceHash ^ UInt64(event.generation)) &* 1099511628211
        sequenceHash = (sequenceHash ^ UInt64(bitPattern: amount)) &* 1099511628211
    }
    /// Deadline checked between atomic events AND scheduler work units. No allocation in the intended path.
    func advance(to target: UInt64, budget: Int, workBudget: Int = 65536,
                 checkLimit: Int = Int.max, deadlineNS: UInt64 = UInt64.max,
                 injectFailureAt: UInt64? = nil) throws -> SliceResult {
        guard target >= now, (1...1024).contains(budget), workBudget > 0, checkLimit > 0 else { throw ProbeError.invalid("advance budget/target") }
        var emitted = 0, work = 0
        while emitted < budget && work < workBudget {
            if work >= checkLimit || (deadlineNS != UInt64.max && nx_now() >= deadlineNS) {
                return SliceResult(events: emitted, units: work, reached: now, stop: .time)
            }
            work += 1
            if let duplicate = wheel.takeGhost() {
                outputs[emitted] = Completion(event: duplicate, amount: fares[Int(duplicate.asset)], completed: completed[Int(duplicate.asset)])
                emitted += 1; continue
            }
            switch try wheel.step(target: target) {
            case .work: continue
            case .drained, .beyondTarget:
                now = target; return SliceResult(events: emitted, units: work, reached: now, stop: .target)
            case .ready(let node):
                let event = wheel.event(node), i = Int(event.asset)
                guard i < count, active[i] == 1 else { throw ProbeError.invariant("wrong live asset") }
                if event.generation != generations[i] && wheel.mutation != .acceptStaleGeneration {
                    rejectedStale += 1
                    return SliceResult(events: emitted, units: work, reached: now, stop: .blocked)
                }
                if injectFailureAt == processed { return SliceResult(events: emitted, units: work, reached: now, stop: .blocked) }
                guard event.operation > accruedOperations[i], event.due >= now, completed[i] < UInt64.max, processed < UInt64.max else {
                    throw ProbeError.invariant("duplicate/old operation or time")
                }
                let amount = fares[i], g = Int(contracts[i])
                guard g < groupAmounts.count else { throw ProbeError.invariant("contract group") }
                let newRevenue = revenue.addingReportingOverflow(event.kind == 0 ? amount : 0)
                let newDue = receivable.addingReportingOverflow(event.kind == 0 ? amount : 0)
                let newGroup = groupAmounts[g].addingReportingOverflow(event.kind == 0 ? amount : 0)
                let newCash = cash.addingReportingOverflow(event.kind == 1 ? amount : event.kind == 2 ? -amount : 0)
                guard !newRevenue.overflow, !newDue.overflow, !newGroup.overflow, !newCash.overflow else { throw ProbeError.invalid("balance overflow") }
                if newCash.partialValue < 0 { return SliceResult(events: emitted, units: work, reached: now, stop: .blocked) }
                // All recoverable checks precede the first write. Failed event stays queued.
#if STAGE_C
                stageCState?.willWriteAsset(self, index: i)
                stageCState?.willWriteGroup(self, index: g)
#endif
                revenue = newRevenue.partialValue; receivable = newDue.partialValue; groupAmounts[g] = newGroup.partialValue
                cash = newCash.partialValue; accruedOperations[i] = event.operation; completed[i] += 1
                active[i] = 0; airports[i] = destinations[i]; changeEpochs[i] = changeEpoch
                now = event.due; processed += 1
                _ = try wheel.consume(node)
                hash(event, amount)
                outputs[emitted] = Completion(event: event, amount: amount, completed: completed[i]); emitted += 1
            }
        }
        return SliceResult(events: emitted, units: work, reached: now, stop: emitted == budget ? .budget : .work)
    }
#if STAGE_C
    func stageCInstall(_ state: StageCState) {
        stageCState = state
        wheel.stageCState = state
    }
    func stageCUninstall() {
        wheel.stageCState = nil
        stageCState = nil
    }
    func stageCAppendControl(into data: inout [UInt8]) {
        Snapshot.appendLE(UInt32(count), into: &data)
        Snapshot.appendLE(UInt32(wheel.capacity), into: &data)
        Snapshot.appendLE(UInt32(groupAmounts.count), into: &data)
        Snapshot.appendLE(now, into: &data)
        Snapshot.appendLE(revenue, into: &data)
        Snapshot.appendLE(receivable, into: &data)
        Snapshot.appendLE(cash, into: &data)
        Snapshot.appendLE(processed, into: &data)
        Snapshot.appendLE(sequenceHash, into: &data)
        Snapshot.appendLE(UInt64(rejectedStale), into: &data)
        Snapshot.appendLE(changeEpoch, into: &data)
        wheel.stageCAppendControl(into: &data)
    }
    func stageCRestoreExtras(rejected: Int, changeEpoch restoredEpoch: UInt32) throws {
        guard rejected >= 0 else { throw ProbeError.corruption("stage C rejected count") }
        rejectedStale = rejected
        changeEpoch = restoredEpoch
    }
#endif
}
