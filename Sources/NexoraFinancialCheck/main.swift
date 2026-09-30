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
