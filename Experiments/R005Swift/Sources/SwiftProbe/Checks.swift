import Foundation
import ProbePlatform
import NexoraSimulation
import NexoraFinance
import NexoraIdentity

func reference(_ count: Int) -> [Completion] {
    var list: [Completion] = []; list.reserveCapacity(count)
    for i in 0..<count {
        list.append(Completion(event: Event(due: UInt64(i % 600 + 1), operation: UInt64(count + i + 1),
            asset: UInt32(i), generation: 0, kind: 0), amount: Int64(i % 97 + 101), completed: 1))
    }
    list.sort { a, b in a.event.due != b.event.due ? a.event.due < b.event.due : a.event.operation < b.event.operation }
    return list
}
func legacyTranscript(_ count: Int, budget: Int = 256) throws -> [Completion] {
    var world = try TripSimulation(capacity: count, eventCapacity: count,
        financeLimits: FinanceLimits(invoices: count, journalEntries: count * 2 + 4))
    _ = try world.applyFinance(.contributeCapital(amountMinor: 1000), expected: world.inputToken)
    var handles: [EntityHandle] = []; handles.reserveCapacity(count)
    for _ in 0..<count { handles.append(try world.apply(.registerAircraft(at: 1), expected: world.inputToken).handle) }
    for i in 0..<count {
        _ = try world.departPriced(handles[i], destination: 2, durationSeconds: UInt64(i % 600 + 1),
            fareMinor: Int64(i % 97 + 101), expected: world.inputToken)
    }
    var transcript: [Completion] = []; transcript.reserveCapacity(count)
    while world.pendingArrivals > 0 {
        let p = try world.advance(to: 600, eventBudget: budget)
        try require(p.stop == .eventBudgetReached || p.stop == .reachedTarget, "legacy fixture blocked")
        for c in p.completions {
            let t = c.trip
            try require(t.origin == 1 && t.destination == 2 && t.departedAt == 0, "legacy fixture route")
            try require(c.invoice?.origin.operationID == t.operationID && c.invoice?.amountMinor == t.fareMinor,
                        "legacy invoice correspondence")
            transcript.append(Completion(event: Event(due: t.arrivesAt, operation: t.operationID,
                asset: t.handle.slot, generation: t.handle.generation, kind: 0), amount: t.fareMinor, completed: c.completedTrips))
        }
    }
    let revenue = transcript.reduce(Int64(0)) { $0 + $1.amount }
    try require(world.financialSummary.revenueMinor == revenue && world.financialSummary.receivablesMinor == revenue, "legacy accrual")
    // Retain the full original priced-arrival/collection/expense fixture, not just timestamps.
    for offset in stride(from: 0, to: count, by: 256) {
        for invoice in try world.invoicePage(offset: offset, limit: 256) {
            _ = try world.applyFinance(.collectInvoice(invoice.handle, amountMinor: invoice.amountMinor), expected: world.inputToken)
        }
    }
    _ = try world.applyFinance(.payExpense(.payroll, amountMinor: 1000), expected: world.inputToken)
    _ = try world.applyFinance(.payExpense(.maintenance, amountMinor: 2000), expected: world.inputToken)
    _ = try world.applyFinance(.payExpense(.operating, amountMinor: 3000), expected: world.inputToken)
    try require(world.financialSummary.revenueMinor == revenue && world.financialSummary.cashMinor == revenue - 5000
        && world.financialSummary.receivablesMinor == 0 && world.checkInvariants(), "legacy fixture final")
    return transcript
}
func drain(_ world: SwiftWorld, target: UInt64, budget: Int = 256, checks: Int = Int.max,
           expected: [Completion]? = nil, inject: UInt64? = nil) throws -> [Completion] {
    var values: [Completion] = []; values.reserveCapacity(expected?.count ?? world.count)
    var calls = 0
    while true {
        let p = try world.advance(to: target, budget: budget, checkLimit: checks, injectFailureAt: inject)
        for i in 0..<p.events {
            let c = world.output(i)
            if let expected { try require(values.count < expected.count && c == expected[values.count], "ordered event \(values.count)") }
            values.append(c)
        }
        calls += 1
        try require(calls < world.count * 100 + 100_000, "nonterminating wheel")
        if p.stop == .blocked { throw ProbeError.blocked }
        if p.stop == .target { break }
    }
    if let expected { try require(values == expected, "complete ordered transcript") }
    return values
}
func orderChecks(_ count: Int) throws -> [String: Any] {
    let expected = reference(count)
    var legacyCases = 0
    if count <= 100_000 {
        for b in [1,7,31,256,1024] {
            try require(try legacyTranscript(count, budget: b) == expected, "R004 event-by-event b=\(b)")
            legacyCases += 1
        }
    }
    var cases = 0
    for budget in [1,7,31,256,1024] {
        for timed in [false,true] {
            let world = try SwiftWorld(count: count); try world.seedFixture()
            _ = try drain(world, target: 600, budget: budget, checks: timed ? 19 : Int.max, expected: expected)
            try require(world.revenue == expected.reduce(0, { $0 + $1.amount }) && world.receivable == world.revenue, "accrual total")
            cases += 1
        }
    }
    return ["status":"pass", "assets":count, "swiftPartitionCases":cases,
            "legacyExactTranscriptCases":legacyCases, "independentSortedReferenceEvents":count,
            "timedClock":"injected deadline after 19 atomic/scheduler checkpoints; actual clock tested separately"]
}

func custom(_ mutation: Mutation = .none, high: Bool = false) throws -> (SwiftWorld, [Completion]) {
    let w = try SwiftWorld(count: 4, mutation: mutation)
    let times: [UInt64] = high ? [65536,65536,65536,65536] : [9,9,9,9]
    // Deliberately not insertion-order == sequence-order.
    for i in [3,1,2,0] { try w.schedule(asset: i, due: times[i], operation: UInt64(i+1), amount: Int64(i+1)) }
    var e: [Completion] = []
    for i in 0..<4 {
        let ev = Event(due: times[i], operation: UInt64(i+1), asset: UInt32(i), generation: 0, kind: 0)
        e.append(Completion(event: ev, amount: Int64(i+1), completed: 1))
    }
    return (w,e)
}
func mutationChecks() throws -> [[String: Any]] {
    // Negative control: exactly the SAME fixture and oracle must pass without the fault.
    for high in [false,true] { let (w,e) = try custom(high: high); _ = try drain(w, target: high ? 65536 : 9, budget: 1, checks: 3, expected: e) }
    let clean = try SwiftWorld(count: 1)
    try clean.schedule(asset: 0, due: 1, operation: 1, amount: 11); try clean.invalidateGeneration(0)
    do { _ = try drain(clean, target: 1); throw ProbeError.mismatch("negative-control stale acceptance") }
    catch ProbeError.blocked { try require(clean.revenue == 0 && clean.wheel.pending == 1, "clean stale changed state") }
    var results: [[String:Any]] = []
    for fault in Mutation.allCases where fault != .none {
        var killed = false, evidence = ""
        do {
            if fault == .acceptStaleGeneration {
                let mutant = try SwiftWorld(count: 1, mutation: fault)
                try mutant.schedule(asset: 0, due: 1, operation: 1, amount: 11); try mutant.invalidateGeneration(0)
                _ = try drain(mutant, target: 1)
                try require(mutant.revenue == 0 && mutant.wheel.pending == 1, "stale generation illegally committed")
            } else {
                let high = fault == .reverseCascade
                let (w,e) = try custom(fault, high: high)
                _ = try drain(w, target: high ? 65536 : 9, budget: 1, checks: 3, expected: e)
            }
        } catch { killed = true; evidence = String(describing: error) }
        results.append(["fault":fault.rawValue,"detected":killed,"test":fault == .acceptStaleGeneration ? "stale_no_commit" : "exact_sorted_transcript", "evidence":evidence])
        try require(killed, "SURVIVING MUTANT: \(fault.rawValue)")
    }
    return results
}
func boundaryChecks() throws -> [String:Any] {
    var checks = 0
    // Exact UInt64 horizon, occupancy jump, multiple cascades, reversed same-tick insertion.
    let times: [UInt64] = [1,255,256,257,65535,65536,65537,1<<32,1<<48,UInt64.max-1,UInt64.max]
    let w = try SwiftWorld(count: times.count)
    for i in times.indices.reversed() { try w.schedule(asset: i, due: times[i], operation: UInt64(i+1), amount: 1) }
    var expected: [Completion] = []
    for i in times.indices {
        let ev = Event(due: times[i],operation:UInt64(i+1),asset:UInt32(i),generation:0,kind:0)
        expected.append(Completion(event:ev,amount:1,completed:1))
    }
    _ = try drain(w,target:UInt64.max,budget:1,checks:1,expected:expected);checks += 1
    // Actual wall-clock deadline: expired deadline cannot commit or falsely advance logical time.
    let expired = try SwiftWorld(count: 2); try expired.seedFixture()
    let p = try expired.advance(to: 600,budget: 256,deadlineNS: nx_now())
    try require(p.events == 0 && p.stop == .time && expired.processed == 0 && expired.now == 0,"expired deadline");checks += 1
    // Work bound including sort/cascade, not only dispatched events.
    let (largeTie,tieExpected)=try custom(high:true)
    var emitted:[Completion]=[]
    while largeTie.wheel.pending>0 {
        let r=try largeTie.advance(to:65536,budget:1024,workBudget:1)
        try require(r.units<=1,"unbounded work step");for i in 0..<r.events {emitted.append(largeTie.output(i))}
    }
    try require(emitted==tieExpected,"resumable sort/cascade");checks += 1
    // Order-sensitive cash: same tick credit must precede debit even when enqueued in reverse.
    let cash=try SwiftWorld(count:2);try cash.addCash(-995)
    try cash.schedule(asset:1,due:256,operation:2,amount:8,kind:2)
    try cash.schedule(asset:0,due:256,operation:1,amount:5,kind:1)
    _ = try drain(cash,target:256,budget:1,checks:1)
    try require(cash.cash==2,"cash order");checks += 1
    // Blocked event plus explicit already-committed prefix; retry preserves full transcript.
    for failure in [UInt64(0),1,50,256] {
        let model=try SwiftWorld(count:300);try model.seedFixture();let expected=reference(300)
        var seen:[Completion]=[];var blocked=false
        while !blocked {
            let p=try model.advance(to:600,budget:31,injectFailureAt:failure)
            for i in 0..<p.events {seen.append(model.output(i))}; blocked=p.stop == .blocked
        }
        try require(model.processed==failure && model.wheel.pending==300-Int(failure),"committed prefix")
        seen += try drain(model,target:600,budget:7,checks:2)
        try require(seen==expected,"failure retry order");checks += 1
    }
    // Capacity/foreign slots are expected errors, not silent drops.
    do { _ = try SwiftWorld(count:0); throw ProbeError.mismatch("accepted zero capacity") }
    catch ProbeError.invalid { checks += 1 }
    return ["status":"pass","groups":checks]
}

@inline(never) func allocationControl(_ size: Int) -> Int {
    var a=ContiguousArray(repeating:UInt64(7),count:size)
    a[size-1]=9
    return a.reduce(0) { $0 + Int($1) }
}
func benchmark(_ count:Int, budget:Int, legacy:Bool = false, deadline: Bool = false) throws -> [String:Any] {
    // Warm the measurement ABI only, NOT this world or its first advance.
    _ = nx_now();_ = nx_footprint();nx_alloc_begin();_ = nx_alloc_end()
    let cAlloc=nx_alloc_calibrate()
    nx_alloc_begin();let control=allocationControl(8193);let swiftControl=nx_alloc_end()
    try require(control==8193*7+2,"allocation positive control computation")
    #if os(macOS)
    try require(cAlloc>0 && swiftControl.calls>0,"allocator hooks not observing actual C/Swift allocations")
    #endif
    if legacy { return try legacyBenchmark(count,budget:budget,control:swiftControl.calls) }
    let before=nx_footprint(), initStart=nx_now()
    let w=try SwiftWorld(count:count);try w.seedFixture()
    let initialized=nx_now(), after=nx_footprint()
    var calls=0,events=0,steps=0,totalNS:UInt64=0,maxNS:UInt64=0,allocations:UInt64=0,maxAlloc:UInt64=0,firstAlloc:UInt64=0
    var callsWithAlloc=0
    while true {
        let end=deadline ? nx_now()+100_000 : UInt64.max
        nx_alloc_begin();let start=nx_now()
        let p=try w.advance(to:600,budget:budget,deadlineNS:end)
        let finish=nx_now();let a=nx_alloc_end()
        calls += 1;events += p.events;steps += p.units;totalNS += finish-start;maxNS=max(maxNS,finish-start)
        allocations += a.calls;maxAlloc=max(maxAlloc,a.calls);if calls==1 {firstAlloc=a.calls};if a.calls>0 {callsWithAlloc += 1}
        if p.stop == .target {break};try require(p.stop != .blocked,"benchmark blocked")
    }
    let final=nx_footprint()
    try require(events==count && w.processed==UInt64(count),"benchmark events")
    return ["implementation":"Swift6-safe-columns-hierarchical-wheel-accrual", "assets":count,"budget":budget,
        "deadlineNS":deadline ? 100_000 : 0,"events":events,"workUnits":steps,"advanceCalls":calls,
        "initializationAndDepartNS":initialized-initStart,"advanceNS":totalNS,"nsPerEvent":Double(totalNS)/Double(count),"maxAdvanceNS":maxNS,
        "ownedColumnCapacityBytes":w.ownedBytes,"ownedBytesPerAsset":Double(w.ownedBytes)/Double(count),
        "physFootprintStatus":after.status==0 ? "ok":"unavailable", "physBefore":before.status==0 ? before.bytes as Any:NSNull(),
        "physAfter":after.status==0 ? after.bytes as Any:NSNull(),"physAfterAdvance":final.status==0 ? final.bytes as Any:NSNull(),
        "physDeltaPerAsset":after.status==0 && before.status==0 ? Double(Int64(after.bytes)-Int64(before.bytes))/Double(count) as Any:NSNull(),
        "allocationStatus":swiftControl.available==1 ? "interposed-entry-calls-current-thread":"unavailable",
        "allocationTotal":swiftControl.available==1 ? allocations as Any:NSNull(),"maxAllocationsPerAdvance":swiftControl.available==1 ? maxAlloc as Any:NSNull(),
        "firstAdvanceAllocations":swiftControl.available==1 ? firstAlloc as Any:NSNull(),"callsWithAllocations":swiftControl.available==1 ? callsWithAlloc as Any:NSNull(),
        "cAllocationPositiveControl":cAlloc,"swiftAllocationPositiveControl":swiftControl.calls,"sequenceHash":w.sequenceHash,
        "revenue":w.revenue,"scope":"macOS/Linux experiment; not full finance/save/map or iPhone acceptance; elapsed times are observations, not pass/fail gates"]
}
func legacyBenchmark(_ count:Int,budget:Int,control:UInt64) throws -> [String:Any] {
    var w=try TripSimulation(capacity:count,eventCapacity:count,financeLimits:FinanceLimits(invoices:count,journalEntries:count*2+4))
    _ = try w.applyFinance(.contributeCapital(amountMinor:1000),expected:w.inputToken)
    var hs:[EntityHandle]=[];hs.reserveCapacity(count)
    for _ in 0..<count {hs.append(try w.apply(.registerAircraft(at:1),expected:w.inputToken).handle)}
    for i in 0..<count {_ = try w.departPriced(hs[i],destination:2,durationSeconds:UInt64(i%600+1),fareMinor:Int64(i%97+101),expected:w.inputToken)}
    var total:UInt64=0,maxAlloc:UInt64=0,sumAlloc:UInt64=0,calls=0,processed=0
    while w.pendingArrivals>0 {
        nx_alloc_begin();let start=nx_now();let p=try w.advance(to:600,eventBudget:budget);let finish=nx_now();let a=nx_alloc_end()
        total += finish-start;calls += 1;processed += p.processedEvents;maxAlloc=max(maxAlloc,a.calls);sumAlloc += a.calls
    }
    try require(processed==count,"legacy benchmark events")
    return ["implementation":"unchanged-R004-priced-arrivals-invoices", "assets":count,"budget":budget,"events":processed,
            "advanceNS":total,"advanceCalls":calls,"nsPerEvent":Double(total)/Double(count),"allocationTotal":control>0 ? sumAlloc as Any:NSNull(),
            "maxAllocationsPerAdvance":control>0 ? maxAlloc as Any:NSNull(),"scope":"not semantically identical finance: R004 issues individual invoices; Swift candidate accrues; no claimed full-engine speedup"]
}
