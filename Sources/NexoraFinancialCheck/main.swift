import Foundation
import NexoraSimulation
import NexoraFinance
import NexoraIdentity

enum FixtureFailure: Error { case arguments, correctness, blocked }
func elapsed(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> UInt64 {
    let p = start.duration(to: end).components
    return UInt64(p.seconds) * 1_000_000_000 + UInt64(p.attoseconds / 1_000_000_000)
}
struct FinancialSample: Codable {
    let initializationNS: UInt64
    let registerAllNS: UInt64
    let departAllNS: UInt64
    let advanceAllNS: UInt64
    let maximumAdvanceNS: UInt64
    let collectAllNS: UInt64
    let maximumCollectionPageNS: UInt64
    let expensePostsNS: UInt64
    let advanceBatches: Int
    let invoiceCount: Int
    let journalCount: Int
    let revenueMinor: Int64
    let cashMinor: Int64
}
struct FinancialScale: Codable { let aircraft: Int; let samples: [FinancialSample] }
struct FinancialReport: Codable {
    let update: String
    let scope: String
    let eventBudget: Int
    let pageSize: Int
    let warmups: Int
    let repetitions: Int
    let scales: [FinancialScale]
    let limitations: [String]
}
func sample(_ count: Int) throws -> FinancialSample {
    let clock = ContinuousClock()
    let initializing = clock.now
    var world = try TripSimulation(capacity: count, eventCapacity: count,
                                   financeLimits: FinanceLimits(invoices: count, journalEntries: count * 2 + 4))
    let initialized = clock.now
    _ = try world.applyFinance(.contributeCapital(amountMinor: 1_000), expected: world.inputToken)
    var handles: [EntityHandle] = []; handles.reserveCapacity(count)
    let registering = clock.now
    for _ in 0..<count { handles.append(try world.apply(.registerAircraft(at: 1), expected: world.inputToken).handle) }
    let registered = clock.now
    var revenue: Int64 = 0
    for (index, h) in handles.enumerated() {
        let fare = Int64(index % 97 + 101)
        revenue += fare
        _ = try world.departPriced(h, destination: 2, durationSeconds: UInt64(index % 600 + 1),
                                   fareMinor: fare, expected: world.inputToken)
    }
    let departed = clock.now
    var batches = 0, arrivals = 0
    var maximumAdvance: UInt64 = 0
    while world.pendingArrivals > 0 {
        let started = clock.now
        let progress = try world.advance(to: 600, eventBudget: 256)
        let finished = clock.now
        maximumAdvance = max(maximumAdvance, elapsed(started, finished))
        guard progress.stop == .eventBudgetReached || progress.stop == .reachedTarget else { throw FixtureFailure.blocked }
        for completed in progress.completions {
            guard let issued = completed.invoice, issued.amountMinor == completed.trip.fareMinor,
                  issued.origin.operationID == completed.trip.operationID,
                  issued.origin.aircraft == completed.trip.handle else { throw FixtureFailure.correctness }
        }
        batches += 1; arrivals += progress.processedEvents
    }
    let advanced = clock.now
    guard arrivals == count, world.financialSummary.revenueMinor == revenue,
          world.financialSummary.receivablesMinor == revenue, world.financialSummary.cashMinor == 1_000 else {
        throw FixtureFailure.correctness
    }
    var offset = 0
    var maximumPage: UInt64 = 0
    let collecting = clock.now
    while offset < count {
        let started = clock.now
        let page = try world.invoicePage(offset: offset, limit: 256)
        for invoice in page {
            _ = try world.applyFinance(.collectInvoice(invoice.handle, amountMinor: invoice.amountMinor),
                                       expected: world.inputToken)
        }
        offset += page.count
        maximumPage = max(maximumPage, elapsed(started, clock.now))
    }
    let collected = clock.now
    _ = try world.applyFinance(.payExpense(.payroll, amountMinor: 1_000), expected: world.inputToken)
    _ = try world.applyFinance(.payExpense(.maintenance, amountMinor: 2_000), expected: world.inputToken)
    _ = try world.applyFinance(.payExpense(.operating, amountMinor: 3_000), expected: world.inputToken)
    let expensed = clock.now
    let closing = world.financialSummary
    guard closing.revenueMinor == revenue, closing.cashMinor == revenue - 5_000,
          closing.receivablesMinor == 0, closing.invoiceCount == count, closing.journalCount == count * 2 + 4,
          closing.payrollExpenseMinor == 1_000, closing.maintenanceExpenseMinor == 2_000,
          closing.operatingExpenseMinor == 3_000, world.checkInvariants() else { throw FixtureFailure.correctness }
    return FinancialSample(initializationNS: elapsed(initializing, initialized),
        registerAllNS: elapsed(registering, registered), departAllNS: elapsed(registered, departed),
        advanceAllNS: elapsed(departed, advanced), maximumAdvanceNS: maximumAdvance,
        collectAllNS: elapsed(collecting, collected), maximumCollectionPageNS: maximumPage,
        expensePostsNS: elapsed(collected, expensed), advanceBatches: batches,
        invoiceCount: closing.invoiceCount, journalCount: closing.journalCount,
        revenueMinor: revenue, cashMinor: closing.cashMinor)
}
@main enum FinancialCheck {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if try FinancialDiagnostics.dispatch(args) { return }
        guard (args.count == 2 || (args.count == 3 && args[2] == "--quick")), args[0] == "--json" else {
            throw FixtureFailure.arguments
        }
        let repetitions = args.count == 3 ? 1 : 30
        let warmups = args.count == 3 ? 0 : 3
        var scales: [FinancialScale] = []
        for count in [1_000,5_000,20_000,50_000,100_000] {
            for _ in 0..<warmups { _ = try sample(count) }
            var samples: [FinancialSample] = []
            for _ in 0..<repetitions { samples.append(try sample(count)) }
            scales.append(FinancialScale(aircraft: count, samples: samples))
            print("Verified priced trips, invoices and collections: \(count) aircraft, \(repetitions) samples; not full gameplay")
        }
        let report = FinancialReport(update: "NXR-R004", scope: "atomic-priced-arrivals-and-single-currency-ledger",
            eventBudget: 256, pageSize: 256, warmups: warmups, repetitions: repetitions, scales: scales,
            limitations: ["Expenses are posting primitives, not scheduled HR/payroll/maintenance/delivery engines.",
                          "No database, save/load, full document images, real route catalog, UI or map.",
                          "Initialization, capital seeding, deep audits and serialization are outside reported hot phases.",
                          "Loop, result and page processing overhead is included as documented.",
                          "No full-feature asset, device, FPS, memory-footprint, zero-allocation, energy or thermal certification.",
                          "Maximum observed batches are not p99 certification or hard latency limits."])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: args[1]))
    }
}

// BEGIN R004 MEASUREMENT-ONLY EXTENSION
// Check-executable instrumentation only. No dependency from a production library.
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum CounterStatus: String, Codable {
    case ok, syscallFailure, invalidValue, unsupported
}

/// Raw endpoints, not silently clamped deltas. getrusage is PROCESS-wide.
/// These reads enclose a wider, non-atomic interval than the wall-clock bracket.
struct CounterSnapshot: Codable {
    let beginOffsetNS: UInt64
    let endOffsetNS: UInt64
    let threadStatus: CounterStatus
    let threadErrno: Int32?
    let threadCPUNS: UInt64?
    let processStatus: CounterStatus
    let processErrno: Int32?
    let processUserNS: UInt64?
    let processSystemNS: UInt64?
    let processMinorFaults: UInt64?
    let processMajorFaults: UInt64?
    let processVoluntarySwitches: UInt64?
    let processInvoluntarySwitches: UInt64?
}

func checkedNanoseconds(seconds: Int64, fraction: Int64, unitsPerSecond: Int64) -> UInt64? {
    guard seconds >= 0, fraction >= 0, fraction < unitsPerSecond,
          unitsPerSecond == 1_000_000 || unitsPerSecond == 1_000_000_000 else { return nil }
    let (whole, overflow) = UInt64(seconds).multipliedReportingOverflow(by: 1_000_000_000)
    guard !overflow else { return nil }
    let (value, additionOverflow) = whole.addingReportingOverflow(
        UInt64(fraction) * UInt64(1_000_000_000 / unitsPerSecond))
    return additionOverflow ? nil : value
}

func readCounters(origin: ContinuousClock.Instant) -> CounterSnapshot {
    let clock = ContinuousClock()
    let begin = elapsed(origin, clock.now)
    #if canImport(Darwin) || canImport(Glibc)
    var cpu = timespec()
    errno = 0
    let cpuResult = clock_gettime(CLOCK_THREAD_CPUTIME_ID, &cpu)
    let cpuError: Int32? = cpuResult == 0 ? nil : errno
    let cpuNS = cpuResult == 0 ? checkedNanoseconds(seconds: Int64(cpu.tv_sec),
        fraction: Int64(cpu.tv_nsec), unitsPerSecond: 1_000_000_000) : nil
    let cpuStatus: CounterStatus = cpuResult != 0 ? .syscallFailure : (cpuNS == nil ? .invalidValue : .ok)
    var usage = rusage()
    errno = 0
    #if canImport(Darwin)
    let usageResult = getrusage(RUSAGE_SELF, &usage)
    #else
    let usageResult = getrusage(Int32(RUSAGE_SELF.rawValue), &usage)
    #endif
    let usageError: Int32? = usageResult == 0 ? nil : errno
    let user = checkedNanoseconds(seconds: Int64(usage.ru_utime.tv_sec),
        fraction: Int64(usage.ru_utime.tv_usec), unitsPerSecond: 1_000_000)
    let system = checkedNanoseconds(seconds: Int64(usage.ru_stime.tv_sec),
        fraction: Int64(usage.ru_stime.tv_usec), unitsPerSecond: 1_000_000)
    let valid = user != nil && system != nil && usage.ru_minflt >= 0 && usage.ru_majflt >= 0
        && usage.ru_nvcsw >= 0 && usage.ru_nivcsw >= 0
    let status: CounterStatus = usageResult != 0 ? .syscallFailure : (valid ? .ok : .invalidValue)
    return CounterSnapshot(beginOffsetNS: begin, endOffsetNS: elapsed(origin, clock.now),
        threadStatus: cpuStatus, threadErrno: cpuError, threadCPUNS: cpuNS,
        processStatus: status, processErrno: usageError,
        processUserNS: status == .ok ? user : nil, processSystemNS: status == .ok ? system : nil,
        processMinorFaults: status == .ok ? UInt64(usage.ru_minflt) : nil,
        processMajorFaults: status == .ok ? UInt64(usage.ru_majflt) : nil,
        processVoluntarySwitches: status == .ok ? UInt64(usage.ru_nvcsw) : nil,
        processInvoluntarySwitches: status == .ok ? UInt64(usage.ru_nivcsw) : nil)
    #else
    return CounterSnapshot(beginOffsetNS: begin, endOffsetNS: elapsed(origin, clock.now),
        threadStatus: .unsupported, threadErrno: nil, threadCPUNS: nil,
        processStatus: .unsupported, processErrno: nil, processUserNS: nil, processSystemNS: nil,
        processMinorFaults: nil, processMajorFaults: nil,
        processVoluntarySwitches: nil, processInvoluntarySwitches: nil)
    #endif
}

func checkedCounterDelta(_ before: UInt64?, _ after: UInt64?) -> UInt64? {
    guard let before, let after, after >= before else { return nil }
    return after - before
}

import Foundation
import NexoraSimulation
import NexoraFinance
import NexoraIdentity

enum ProbeMode: String, Codable { case wall, counters }
enum ProbePhase: String, Codable { case depart, advance, collect, empty }
struct BatchRecord: Codable {
    let aircraft: Int
    let sample: Int // 1-based, separate from 0-based batch
    let phase: ProbePhase
    let batch: Int
    let operations: Int
    let startOffsetNS: UInt64
    let wallNS: UInt64
    let before: CounterSnapshot?
    let after: CounterSnapshot?
}
struct PhaseRecord: Codable {
    let phase: ProbePhase
    let startOffsetNS: UInt64
    let totalNS: UInt64
    let sumBatchWallNS: UInt64
    let outsideBatchWallNS: UInt64 // arithmetic difference, NOT a causal label
}
struct DiagnosticResult: Encodable {
    let kind = "sample"
    let aircraft: Int
    let sample: Int
    let warmup: Bool
    let mode: String
    let runID: Int
    let executionOrder: Int
    let aggregate: FinancialSample
    let bufferPreparationNS: UInt64?
    let seedAndHandlePreparationNS: UInt64?
    let finalAuditNS: UInt64?
    let explicitWorldReleaseNS: UInt64?
    let workloadNS: UInt64?
    let phases: [PhaseRecord]
    let records: [BatchRecord]
}
struct MeasuredFixture {
    let aggregate: FinancialSample
    let bufferPreparationNS: UInt64
    let seedAndHandlePreparationNS: UInt64
    let finalAuditNS: UInt64
    let explicitWorldReleaseNS: UInt64
    let workloadNS: UInt64
    let phases: [PhaseRecord]
    let records: [BatchRecord]
    let truth: [UInt64] // Only requested by the separate correctness run.
}

// Consuming parameter guarantees that this call owns the world's destruction.
// Detached handles/views can still retain identity stamps; this is not all ARC work.
@inline(never) func releaseDiagnosticWorld(_ world: consuming TripSimulation) {}

func sameEconomics(_ a: FinancialSample, _ b: FinancialSample) -> Bool {
    a.invoiceCount == b.invoiceCount && a.journalCount == b.journalCount
        && a.revenueMinor == b.revenueMinor && a.cashMinor == b.cashMinor
        && a.advanceBatches == b.advanceBatches
}
func invoiceTruth(_ row: InvoiceView) -> [UInt64] {
    [row.handle.number, UInt64(row.origin.aircraft.slot), UInt64(row.origin.aircraft.generation),
     row.origin.operationID, row.issuedAt, UInt64(bitPattern: row.amountMinor),
     UInt64(bitPattern: row.paidMinor), UInt64(row.currency.minorDigits)] + row.currency.code.utf8.map(UInt64.init)
}
func journalTruth(_ row: JournalEntry) -> [UInt64] {
    let kind: UInt64
    switch row.kind {
    case .capitalContribution: kind = 0
    case .invoiceIssued: kind = 1
    case .invoiceCollected: kind = 2
    case .cashExpense(let expense): kind = 3 + UInt64(expense.rawValue)
    }
    return [row.number, row.at, kind, UInt64(row.debit.rawValue), UInt64(row.credit.rawValue),
            UInt64(bitPattern: row.amountMinor), row.invoice?.number ?? 0]
}

/// All allocations for the trace slots occur BEFORE initialization/phase timing.
/// No library code, workload order, fare formula, budget or page size is changed.
func measuredFixture(_ count: Int, sampleIndex: Int, mode: ProbeMode,
                     captureTruth: Bool = false, trace: BatchTrace? = nil) throws -> MeasuredFixture {
    guard (64...100_000).contains(count), sampleIndex > 0 else { throw FixtureFailure.arguments }
    defer { trace?.finish() } // Close an open marker on a thrown diagnostic workload.
    let clock = ContinuousClock()
    let preparing = clock.now
    let batchCapacity = (count + 255) / 256
    var records = [BatchRecord?](repeating: nil, count: batchCapacity * 3)
    var cursor = 0
    var phases: [PhaseRecord] = []; phases.reserveCapacity(3)
    var truth: [UInt64] = []
    // These diagnostic-only normalized values are never built in performance runs.
    if captureTruth { truth.reserveCapacity(count * 50 + batchCapacity * 6 + 41) }
    let initializing = clock.now
    var world = try TripSimulation(capacity: count, eventCapacity: count,
        financeLimits: FinanceLimits(invoices: count, journalEntries: count * 2 + 4))
    let initialized = clock.now
    _ = try world.applyFinance(.contributeCapital(amountMinor: 1_000), expected: world.inputToken)
    var handles: [EntityHandle] = []; handles.reserveCapacity(count)
    let registering = clock.now
    for _ in 0..<count { handles.append(try world.apply(.registerAircraft(at: 1), expected: world.inputToken).handle) }
    let registered = clock.now
    var revenue: Int64 = 0
    var sum: UInt64 = 0
    for batch in 0..<batchCapacity {
        let lower = batch * 256, upper = min(count, lower + 256)
        let before = mode == .counters ? readCounters(origin: initializing) : nil
        trace?.begin(aircraft: count, world: sampleIndex, phase: 0, batch: batch)
        let started = clock.now
        for index in lower..<upper {
            let fare = Int64(index % 97 + 101)
            revenue += fare
            _ = try world.departPriced(handles[index], destination: 2,
                durationSeconds: UInt64(index % 600 + 1), fareMinor: fare, expected: world.inputToken)
        }
        let finished = clock.now
        trace?.finish()
        let after = mode == .counters ? readCounters(origin: initializing) : nil
        let wall = elapsed(started, finished); sum += wall
        records[cursor] = BatchRecord(aircraft: count, sample: sampleIndex, phase: .depart,
            batch: batch, operations: upper - lower, startOffsetNS: elapsed(initializing, started),
            wallNS: wall, before: before, after: after)
        cursor += 1
    }
    let departed = clock.now
    let departTotal = elapsed(registered, departed)
    guard sum <= departTotal else { throw FixtureFailure.correctness }
    phases.append(PhaseRecord(phase: .depart, startOffsetNS: elapsed(initializing, registered),
        totalNS: departTotal, sumBatchWallNS: sum, outsideBatchWallNS: departTotal - sum))
    var batches = 0, arrivals = 0
    var maximumAdvance: UInt64 = 0; sum = 0
    // Includes phase-bookkeeping since `departed`; preserve the legacy outer boundary.
    while world.pendingArrivals > 0 {
        guard batches < batchCapacity else { throw FixtureFailure.correctness }
        let before = mode == .counters ? readCounters(origin: initializing) : nil
        trace?.begin(aircraft: count, world: sampleIndex, phase: 1, batch: batches)
        let started = clock.now
        let progress = try world.advance(to: 600, eventBudget: 256)
        let finished = clock.now
        trace?.finish()
        let after = mode == .counters ? readCounters(origin: initializing) : nil
        let wall = elapsed(started, finished); sum += wall
        maximumAdvance = max(maximumAdvance, wall)
        records[cursor] = BatchRecord(aircraft: count, sample: sampleIndex, phase: .advance,
            batch: batches, operations: progress.processedEvents, startOffsetNS: elapsed(initializing, started),
            wallNS: wall, before: before, after: after)
        cursor += 1
        guard progress.stop == .eventBudgetReached || progress.stop == .reachedTarget,
              progress.processedEvents > 0 else { throw FixtureFailure.blocked }
        if captureTruth {
            truth += [progress.fromTime, progress.requestedTime, progress.reachedTime,
                      progress.nextDueTime ?? UInt64.max, UInt64(progress.processedEvents),
                      progress.stop == .reachedTarget ? 0 : 1]
        }
        for completed in progress.completions {
            guard let issued = completed.invoice, issued.amountMinor == completed.trip.fareMinor,
                  issued.origin.operationID == completed.trip.operationID,
                  issued.origin.aircraft == completed.trip.handle else { throw FixtureFailure.correctness }
            if captureTruth {
                let t = completed.trip
                truth += [UInt64(t.handle.slot), UInt64(t.handle.generation), t.operationID,
                          UInt64(t.origin), UInt64(t.destination), t.departedAt, t.arrivesAt,
                          UInt64(bitPattern: t.fareMinor), completed.completedTrips]
                truth += invoiceTruth(issued)
            }
        }
        batches += 1; arrivals += progress.processedEvents
    }
    let advanced = clock.now
    let advanceTotal = elapsed(departed, advanced)
    guard sum <= advanceTotal else { throw FixtureFailure.correctness }
    phases.append(PhaseRecord(phase: .advance, startOffsetNS: elapsed(initializing, departed),
        totalNS: advanceTotal, sumBatchWallNS: sum, outsideBatchWallNS: advanceTotal - sum))
    guard arrivals == count, world.financialSummary.revenueMinor == revenue,
          world.financialSummary.receivablesMinor == revenue, world.financialSummary.cashMinor == 1_000 else {
        throw FixtureFailure.correctness
    }
    var offset = 0, pageIndex = 0
    var maximumPage: UInt64 = 0; sum = 0
    let collecting = clock.now
    while offset < count {
        guard pageIndex < batchCapacity else { throw FixtureFailure.correctness }
        let before = mode == .counters ? readCounters(origin: initializing) : nil
        trace?.begin(aircraft: count, world: sampleIndex, phase: 2, batch: pageIndex)
        let started = clock.now
        let page = try world.invoicePage(offset: offset, limit: 256)
        for invoice in page {
            _ = try world.applyFinance(.collectInvoice(invoice.handle, amountMinor: invoice.amountMinor),
                                       expected: world.inputToken)
        }
        offset += page.count // Intentionally inside the legacy collection bracket.
        let finished = clock.now
        trace?.finish()
        let after = mode == .counters ? readCounters(origin: initializing) : nil
        let wall = elapsed(started, finished); sum += wall
        maximumPage = max(maximumPage, wall)
        records[cursor] = BatchRecord(aircraft: count, sample: sampleIndex, phase: .collect,
            batch: pageIndex, operations: page.count, startOffsetNS: elapsed(initializing, started),
            wallNS: wall, before: before, after: after)
        cursor += 1; pageIndex += 1
        guard !page.isEmpty else { throw FixtureFailure.correctness }
    }
    let collected = clock.now
    let collectTotal = elapsed(collecting, collected)
    guard sum <= collectTotal else { throw FixtureFailure.correctness }
    phases.append(PhaseRecord(phase: .collect, startOffsetNS: elapsed(initializing, collecting),
        totalNS: collectTotal, sumBatchWallNS: sum, outsideBatchWallNS: collectTotal - sum))
    _ = try world.applyFinance(.payExpense(.payroll, amountMinor: 1_000), expected: world.inputToken)
    _ = try world.applyFinance(.payExpense(.maintenance, amountMinor: 2_000), expected: world.inputToken)
    _ = try world.applyFinance(.payExpense(.operating, amountMinor: 3_000), expected: world.inputToken)
    let expensed = clock.now
    let closing = world.financialSummary
    guard closing.revenueMinor == revenue, closing.cashMinor == revenue - 5_000,
          closing.receivablesMinor == 0, closing.invoiceCount == count, closing.journalCount == count * 2 + 4,
          closing.payrollExpenseMinor == 1_000, closing.maintenanceExpenseMinor == 2_000,
          closing.operatingExpenseMinor == 3_000, world.checkInvariants(), cursor == records.count else {
        throw FixtureFailure.correctness
    }
    if captureTruth {
        // Final normalized public state; identity pointer addresses are deliberately excluded.
        for handle in handles {
            let row = try world.read(handle)
            guard row.activeTrip == nil else { throw FixtureFailure.correctness }
            truth += [UInt64(handle.slot), UInt64(handle.generation), UInt64(row.currentAirport),
                      row.completedTrips, row.inputToken.sequence]
        }
        for start in stride(from: 0, to: closing.invoiceCount, by: 256) {
            for row in try world.invoicePage(offset: start, limit: 256) { truth += invoiceTruth(row) }
        }
        for start in stride(from: 0, to: closing.journalCount, by: 256) {
            for row in try world.journalPage(offset: start, limit: 256) { truth += journalTruth(row) }
        }
        truth += [world.now, UInt64(world.pendingArrivals), world.inputToken.sequence,
                  UInt64(closing.invoiceCount), UInt64(closing.journalCount), closing.token.revision,
                  UInt64(bitPattern: closing.revenueMinor), UInt64(bitPattern: closing.cashMinor),
                  UInt64(bitPattern: closing.receivablesMinor), UInt64(bitPattern: closing.contributedCapitalMinor),
                  UInt64(bitPattern: closing.payrollExpenseMinor), UInt64(bitPattern: closing.maintenanceExpenseMinor),
                  UInt64(bitPattern: closing.operatingExpenseMinor)]
    }
    let audited = clock.now
    releaseDiagnosticWorld(consume world)
    let released = clock.now
    let aggregate = FinancialSample(initializationNS: elapsed(initializing, initialized),
        registerAllNS: elapsed(registering, registered), departAllNS: departTotal,
        advanceAllNS: advanceTotal, maximumAdvanceNS: maximumAdvance, collectAllNS: collectTotal,
        maximumCollectionPageNS: maximumPage, expensePostsNS: elapsed(collected, expensed),
        advanceBatches: batches, invoiceCount: closing.invoiceCount, journalCount: closing.journalCount,
        revenueMinor: revenue, cashMinor: closing.cashMinor)
    // Compact/export only after all measured phases and the explicit world release.
    return MeasuredFixture(aggregate: aggregate, bufferPreparationNS: elapsed(preparing, initializing),
        seedAndHandlePreparationNS: elapsed(initialized, registering), finalAuditNS: elapsed(expensed, audited),
        explicitWorldReleaseNS: elapsed(audited, released), workloadNS: elapsed(initializing, released),
        phases: phases, records: records.compactMap { $0 }, truth: truth)
}

struct Calibration: Encodable {
    let kind = "calibration"
    let mode: ProbeMode
    let iterations: Int
    let loopNS: UInt64 // Includes recording/loop costs, unlike each inner wall bracket.
    let records: [BatchRecord]
}
func calibrate(_ mode: ProbeMode, iterations: Int) -> Calibration {
    let clock = ContinuousClock()
    var records = [BatchRecord?](repeating: nil, count: iterations)
    let origin = clock.now
    for index in 0..<iterations {
        let before = mode == .counters ? readCounters(origin: origin) : nil
        let start = clock.now
        let end = clock.now
        let after = mode == .counters ? readCounters(origin: origin) : nil
        records[index] = BatchRecord(aircraft: 0, sample: 0, phase: .empty, batch: index, operations: 0,
            startOffsetNS: elapsed(origin, start), wallNS: elapsed(start, end), before: before, after: after)
    }
    let loop = elapsed(origin, clock.now)
    return Calibration(mode: mode, iterations: iterations, loopNS: loop, records: records.compactMap { $0 })
}

/// One complete JSON object per line. A failed run retains previous complete lines.
/// No formatting, encoding, I/O, console output or output-buffer growth is in a workload phase.
enum DiagnosticIOFailure: Error { case invalidPath, openFailed(Int32), closed }

final class DiagnosticWriter {
    private var handle: FileHandle?
    private let encoder: JSONEncoder
    init(path: String) throws {
        guard !path.isEmpty, !path.utf8.contains(0) else { throw DiagnosticIOFailure.invalidPath }
        // One atomic exclusive create. No existence check/reopen race and no truncation.
        // Protects the final path component; the caller still owns the parent directory.
        let fd = path.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600)) }
        guard fd >= 0 else { throw DiagnosticIOFailure.openFailed(errno) }
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    }
    func write<T: Encodable>(_ value: T) throws {
        guard let handle else { throw DiagnosticIOFailure.closed }
        var data = try encoder.encode(value)
        data.append(10)
        try handle.write(contentsOf: data)
    }
    func close() throws {
        guard let openHandle = handle else { return }
        handle = nil
        try openHandle.close()
    }
    // FileHandle owns the descriptor and closes it on deallocation, including throws.
}

struct DiagnosticMetadata: Encodable {
    let kind = "metadata"
    let schema = "NXR-R004-BATCH-DIAGNOSTICS-1"
    let runID: Int
    let repetitions: Int
    let warmups: Int
    let sizes = [1_000, 5_000, 20_000, 50_000, 100_000]
    let modes = ["baseline", "wall", "counters"]
    let batchSize = 256
    let sampleIndexing = "1-based within warmup or measured stratum; batch is 0-based; calibration uses sample=0"
    let sourceBase = "5b5599895fa1bdbf00e951104e0cd55dc00f9a56"
    let sourceCommit: String
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let processID = ProcessInfo.processInfo.processIdentifier
    let mainThread = Thread.isMainThread
    let counterDefinitions = [
        "threadCPUNS": "ns; calling thread user+system; clock_gettime(CLOCK_THREAD_CPUTIME_ID); no mach conversion",
        "processUserNS": "ns converted from timeval microseconds; all process threads; getrusage(RUSAGE_SELF)",
        "processSystemNS": "ns converted from timeval microseconds; all process threads; getrusage(RUSAGE_SELF)",
        "processMinorFaults": "count; process; ru_minflt; Apple faults minus pageins, not necessarily allocations",
        "processMajorFaults": "count; process; ru_majflt; Apple task pageins",
        "processVoluntarySwitches": "count; process; ru_nvcsw",
        "processInvoluntarySwitches": "count; process; ru_nivcsw; Apple derives csw minus voluntary, clamps below zero"
    ]
    let notCollected = ["proc_pid_rusage V4 runnable time, instructions and cycles: not implemented in this first probe; not reported as zero or unsupported hardware",
        "thread-local page faults/context switches, physical footprint, allocations, scheduler trace, frequency, thermal/energy: not measured"]
    let limitations = [
        "Counter endpoints surround wider non-atomic intervals than wall brackets and include diagnostic reads; process metrics are not thread/event attribution.",
        "All endpoints, zeros, read failures and spikes are retained. Missing/error readings have status and no numeric value. A decreasing counter has no valid delta.",
        "baseline calls the untouched legacy sample. wall adds departure grouping/timing/recording. counters adds resource reads to the same diagnostic loop.",
        "Order alternates baseline-wall-counters / counters-wall-baseline by sample and run. Separate worlds have randomized identity/hash placement; this is not bit-identical address layout.",
        "Warmup worlds are saved separately. Data is streamed after each completed world, not retained across worlds; serialization can affect the following allocator/cache state.",
        "outsideBatchWallNS includes checks, logging, counter reads, return-value destruction and loop work; it is not automatically external scheduling.",
        "Explicit world-release timing excludes some detached handle/stamp/trace destruction; initialization, audit, trace preparation and workload totals are separate.",
        "Mac/Linux core diagnostic only, no cause certified, no iPhone/FPS/thermal/full-game/under-5ms acceptance."]
}

enum FinancialDiagnostics {
    static func dispatch(_ args: [String]) throws -> Bool {
        guard let first = args.first else { return false }
        if first == "--causal-trace" {
            try CausalTrace.run(args); return true
        }
        if first == "--trace-selftest" {
            guard args.count == 1 else { throw FixtureFailure.arguments }
            try CausalTrace.selfTest(); return true
        }
        if first == "--diagnostic-writer-probe" {
            guard args.count == 2 else { throw FixtureFailure.arguments }
            let writer = try DiagnosticWriter(path: args[1])
            try writer.write(["kind": "writer-probe", "status": "complete"])
            try writer.close()
            try writer.close() // Explicit close is idempotent; deinit must not close a reused fd.
            do {
                _ = try DiagnosticWriter(path: args[1] + "\0suffix")
                throw FixtureFailure.correctness
            } catch DiagnosticIOFailure.invalidPath { }
            do {
                try writer.write(["must": "fail-after-close"])
                throw FixtureFailure.correctness
            } catch DiagnosticIOFailure.closed { }
            return true
        }
        if first == "--diagnostic-selftest" {
            guard args.count == 1 else { throw FixtureFailure.arguments }
            try selfTest(); return true
        }
        guard first == "--diagnostics" else { return false }
        guard args.count == 2 || args.count == 3 || args.count == 4 || args.count == 5 else {
            throw FixtureFailure.arguments
        }
        var quick = false, runID = 1, index = 2
        while index < args.count {
            if args[index] == "--quick", !quick { quick = true; index += 1 }
            else if args[index] == "--run-id", index + 1 < args.count,
                    let value = Int(args[index + 1]), (1...100).contains(value) {
                runID = value; index += 2
            } else { throw FixtureFailure.arguments }
        }
        let repetitions = quick ? 1 : 30, warmups = quick ? 0 : 3
        guard let sourceCommit = ProcessInfo.processInfo.environment["NEXORA_SOURCE_COMMIT"],
              sourceCommit.utf8.count == 40,
              sourceCommit.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw FixtureFailure.arguments
        }
        let writer = try DiagnosticWriter(path: args[1])
        do {
            try writer.write(DiagnosticMetadata(runID: runID, repetitions: repetitions, warmups: warmups,
                sourceCommit: sourceCommit))
            // Both empty-window modes are saved; never subtract calibration from raw values.
            for mode in [ProbeMode.wall, .counters] { try writer.write(calibrate(mode, iterations: 2_000)) }
            for count in [1_000, 5_000, 20_000, 50_000, 100_000] {
                for round in 0..<(warmups + repetitions) {
                    let warmup = round < warmups
                    let sampleIndex = warmup ? round + 1 : round - warmups + 1
                    let order = (round + runID) % 2 == 0 ? ["baseline", "wall", "counters"] : ["counters", "wall", "baseline"]
                    var economics: FinancialSample?
                    for (position, mode) in order.enumerated() {
                        let aggregate: FinancialSample
                        if mode == "baseline" {
                            aggregate = try sample(count)
                            try writer.write(DiagnosticResult(aircraft: count, sample: sampleIndex, warmup: warmup,
                                mode: mode, runID: runID, executionOrder: position, aggregate: aggregate,
                                bufferPreparationNS: nil, seedAndHandlePreparationNS: nil, finalAuditNS: nil,
                                explicitWorldReleaseNS: nil, workloadNS: nil, phases: [], records: []))
                        } else {
                            let result = try measuredFixture(count, sampleIndex: sampleIndex,
                                mode: mode == "wall" ? .wall : .counters)
                            aggregate = result.aggregate
                            try writer.write(DiagnosticResult(aircraft: count, sample: sampleIndex, warmup: warmup,
                                mode: mode, runID: runID, executionOrder: position, aggregate: aggregate,
                                bufferPreparationNS: result.bufferPreparationNS,
                                seedAndHandlePreparationNS: result.seedAndHandlePreparationNS,
                                finalAuditNS: result.finalAuditNS, explicitWorldReleaseNS: result.explicitWorldReleaseNS,
                                workloadNS: result.workloadNS, phases: result.phases, records: result.records))
                        }
                        if let old = economics, !sameEconomics(old, aggregate) { throw FixtureFailure.correctness }
                        economics = aggregate
                    }
                }
                print("R004 measurement only: \(count) aircraft, \(repetitions) alternating triples; raw warmups retained")
            }
            try writer.write(["kind": "complete", "status": "all-fixture-checks-passed"])
            try writer.close()
        } catch {
            try? writer.write(["kind": "failure", "error": String(describing: error)])
            try? writer.close()
            throw error
        }
        return true
    }

    static func selfTest() throws {
        func require(_ condition: Bool) throws { if !condition { throw FixtureFailure.correctness } }
        try require(checkedNanoseconds(seconds: 1, fraction: 23, unitsPerSecond: 1_000_000) == 1_000_023_000)
        try require(checkedNanoseconds(seconds: 1, fraction: 23, unitsPerSecond: 1_000_000_000) == 1_000_000_023)
        try require(checkedNanoseconds(seconds: -1, fraction: 0, unitsPerSecond: 1_000_000) == nil)
        try require(checkedNanoseconds(seconds: 0, fraction: 1_000_000, unitsPerSecond: 1_000_000) == nil)
        try require(checkedNanoseconds(seconds: Int64.max, fraction: 0, unitsPerSecond: 1_000_000) == nil)
        try require(checkedCounterDelta(4, 3) == nil && checkedCounterDelta(nil, 3) == nil)
        try require(checkedCounterDelta(0, 0) == 0 && checkedCounterDelta(4, 9) == 5)
        print("PASS diagnostic conversions: time units, bounds, overflow, missing/decreasing/zero counters")
        for count in [64, 255, 256, 257, 1_000, 5_000, 20_000, 50_000, 100_000] {
            let wall = try measuredFixture(count, sampleIndex: 1, mode: .wall, captureTruth: true)
            let counters = try measuredFixture(count, sampleIndex: 1, mode: .counters, captureTruth: true)
            let baseline = try sample(count)
            try require(wall.truth == counters.truth && !wall.truth.isEmpty)
            try require(sameEconomics(wall.aggregate, counters.aggregate) && sameEconomics(wall.aggregate, baseline))
            try require(wall.records.count == 3 * ((count + 255) / 256))
            for phase in [ProbePhase.depart, .advance, .collect] {
                let rows = counters.records.filter { $0.phase == phase }
                try require(rows.reduce(0) { $0 + $1.operations } == count)
                for (i, row) in rows.enumerated() {
                    try require(row.batch == i && row.operations > 0 && row.operations <= 256)
                    guard let before = row.before, let after = row.after else { throw FixtureFailure.correctness }
                    try require(before.beginOffsetNS <= before.endOffsetNS && before.endOffsetNS <= row.startOffsetNS)
                    try require(row.startOffsetNS + row.wallNS <= after.beginOffsetNS && after.beginOffsetNS <= after.endOffsetNS)
                }
            }
            print("PASS full normalized public transcript wall/counters and legacy economics: \(count) aircraft, \(wall.truth.count) words")
        }
        print("PASS diagnostic selftests; separate from 142 library tests; no performance acceptance")
    }
}


// Causal acquisition is a separate protocol; never masquerades as schema-1 benchmark data.
#if canImport(os)
import os
#endif

enum TraceFailure: Error { case unavailable, markerDisabled }

/// Owned by the serial check executable, never by a production library or each aircraft.
final class BatchTrace {
    let enabled: Bool
    private(set) var begins = 0
    private(set) var ends = 0
    private var active = false
    #if canImport(os)
    private let signposter = OSSignposter(subsystem: "com.nexora.diagnostics", category: .pointsOfInterest)
    private var state: OSSignpostIntervalState?
    #endif
    static var supported: Bool {
        #if canImport(os)
        return true
        #else
        return false
        #endif
    }
    init(enabled: Bool) throws {
        self.enabled = enabled
        guard !enabled || Self.supported else { throw TraceFailure.unavailable }
        #if canImport(os)
        guard !enabled || signposter.isEnabled else { throw TraceFailure.markerDisabled }
        #endif
    }
    func begin(aircraft: Int, world: Int, phase: Int, batch: Int) {
        precondition(!active, "NEXORA_TRACE_INVARIANT: overlapping serial interval")
        guard enabled else { return }
        active = true; begins += 1
        #if canImport(os)
        state = signposter.beginInterval("NEXORA batch", id: .exclusive,
            "n=\(aircraft) world=\(world) phase=\(phase) batch=\(batch)")
        #endif
    }
    func finish() {
        guard active else { return }
        #if canImport(os)
        guard let state else { preconditionFailure("NEXORA_TRACE_INVARIANT: missing begin") }
        signposter.endInterval("NEXORA batch", state)
        self.state = nil
        #endif
        active = false; ends += 1
    }
}

struct TraceMetadata: Encodable {
    let kind = "traceMetadata"
    let schema = "NXR-R004-CAUSAL-1"
    let sourceCommit: String
    let sourceBase = "74d8a7f1d072209aee3d8e7e964d76468890a694"
    let aircraft: Int
    let repetitions: Int
    let warmups = 3
    let processID = ProcessInfo.processInfo.processIdentifier
    let os = ProcessInfo.processInfo.operatingSystemVersionString
    let profileLabel: String
    let counters: DiagnosticMetadata
    let limitations = [
        "A new acquisition protocol, not comparable to old maxima as an optimization result.",
        "world is 1-based including three warmups; each world has alternating unmarked/marked independent instances.",
        "phase 0=depart,1=advance,2=collect. Serial signposts enclose wall brackets; resource reads enclose wider windows including markers.",
        "Marker calibration includes calling and bookkeeping; no subtraction from raw timings.",
        "First warmups are preserved, not a controlled proof of cold origins memory.",
        "profileLabel is the caller's requested acquisition, not proof that a profiler recorded usable samples.",
        "No physical-device, universal cause, under-5ms or full-game acceptance. Source field syntax is not attestation."]
}
struct TraceCalibration: Encodable {
    let kind = "traceCalibration"
    let marked: Bool
    let loopNS: UInt64
    let samplesNS: [UInt64]
    let begins: Int
    let ends: Int
}
struct TraceSample: Encodable {
    let kind = "traceSample"
    let marked: Bool
    let world: Int
    let fixture: DiagnosticResult
    let begins: Int
    let ends: Int
}

enum CausalTrace {
    static func calibration(marked: Bool) throws -> TraceCalibration {
        let trace = try BatchTrace(enabled: marked)
        let clock = ContinuousClock()
        var windows = [UInt64](repeating: 0, count: 2_000)
        let loop = clock.now
        for i in windows.indices {
            let start = clock.now
            trace.begin(aircraft: 0, world: 0, phase: 3, batch: i)
            trace.finish()
            windows[i] = elapsed(start, clock.now)
        }
        return TraceCalibration(marked: marked, loopNS: elapsed(loop, clock.now),
                                samplesNS: windows, begins: trace.begins, ends: trace.ends)
    }
    static func run(_ args: [String]) throws {
        // --causal-trace OUTPUT SOURCE_SHA AIRCRAFT REPETITIONS PROFILE_LABEL
        guard args.count == 6, args[2].utf8.count == 40,
              args[2].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let count = Int(args[3]), [20_000,50_000,100_000].contains(count),
              let repetitions = Int(args[4]), (1...30).contains(repetitions),
              ["unprofiled","time-profiler","system-trace"].contains(args[5]) else {
            throw FixtureFailure.arguments
        }
        // Fail before creating evidence on a platform that cannot emit requested markers.
        _ = try BatchTrace(enabled: true)
        let writer = try DiagnosticWriter(path: args[1])
        do {
            try writer.write(TraceMetadata(sourceCommit: args[2], aircraft: count, repetitions: repetitions,
                profileLabel: args[5], counters: DiagnosticMetadata(runID: 1, repetitions: repetitions,
                    warmups: 3, sourceCommit: args[2])))
            for marked in [false,true] { try writer.write(calibration(marked: marked)) }
            for world in 1...(repetitions + 3) {
                let order = world % 2 == 0 ? [false,true] : [true,false]
                var previous: FinancialSample?
                for (position, marked) in order.enumerated() {
                    let trace = try BatchTrace(enabled: marked)
                    let result = try measuredFixture(count, sampleIndex: world, mode: .counters, trace: trace)
                    guard trace.begins == trace.ends,
                          trace.begins == (marked ? result.records.count : 0) else { throw FixtureFailure.correctness }
                    if let previous, !sameEconomics(previous, result.aggregate) { throw FixtureFailure.correctness }
                    previous = result.aggregate
                    let fixture = DiagnosticResult(aircraft: count, sample: world, warmup: world <= 3,
                        mode: "counters", runID: 1, executionOrder: position, aggregate: result.aggregate,
                        bufferPreparationNS: result.bufferPreparationNS, seedAndHandlePreparationNS: result.seedAndHandlePreparationNS,
                        finalAuditNS: result.finalAuditNS, explicitWorldReleaseNS: result.explicitWorldReleaseNS,
                        workloadNS: result.workloadNS, phases: result.phases, records: result.records)
                    try writer.write(TraceSample(marked: marked, world: world, fixture: fixture,
                                                begins: trace.begins, ends: trace.ends))
                }
            }
            try writer.write(["kind":"traceComplete", "status":"all-fixture-checks-passed"])
            try writer.close()
        } catch {
            try? writer.write(["kind":"traceFailure", "error":String(describing:error)])
            try? writer.close()
            throw error
        }
    }
    static func selfTest() throws {
        for n in [64,257,1_000] {
            let base = try measuredFixture(n, sampleIndex: 1, mode: .counters, captureTruth: true)
            let off = try BatchTrace(enabled: false)
            let unmarked = try measuredFixture(n, sampleIndex: 1, mode: .counters, captureTruth: true, trace: off)
            guard base.truth == unmarked.truth, sameEconomics(base.aggregate, unmarked.aggregate),
                  off.begins == 0, off.ends == 0 else { throw FixtureFailure.correctness }
            if BatchTrace.supported {
                let on = try BatchTrace(enabled: true)
                let marked = try measuredFixture(n, sampleIndex: 1, mode: .counters, captureTruth: true, trace: on)
                guard base.truth == marked.truth, sameEconomics(base.aggregate, marked.aggregate),
                      on.begins == marked.records.count, on.ends == on.begins else { throw FixtureFailure.correctness }
            }
        }
        if !BatchTrace.supported {
            do { _ = try BatchTrace(enabled: true); throw FixtureFailure.correctness }
            catch TraceFailure.unavailable { }
        }
        print("PASS trace transcripts; markers supported=\(BatchTrace.supported); no latency claim")
    }
}
