import Testing
import NexoraIdentity
import NexoraFinance
@testable import NexoraSimulation

// A separately constructed sorted-list oracle. No heap, posting-plan, balance,
// audit or production invariant helper is used to calculate expected outcomes.
private struct ExpectedBill: Equatable {
    let number: UInt64
    let slot: UInt32
    let operation: UInt64
    let at: UInt64
    let amount: Int64
}
private struct ExpectedPosting: Equatable {
    let number: UInt64
    let at: UInt64
    let kind: JournalKind
    let debit: LedgerAccount
    let credit: LedgerAccount
    let amount: Int64
    let invoice: UInt64?
}
private struct ExpectedArrival {
    let ordinal: Int
    let operation: UInt64
    let at: UInt64
    let fare: Int64
}
private struct PartitionEvidence: Equatable {
    let bills: [ExpectedBill]
    let journal: [ExpectedPosting]
    let income: Int64
    let cash: Int64
    let invoiceCount: Int
    let completions: Int
}

private func runFinancialPartition(seed: Int, budget: Int, splitTargets: Bool,
                                   injectFailures: Bool) throws -> PartitionEvidence {
    let count = 97
    let capital: Int64 = 100_000
    var world = try TripSimulation(capacity: count, eventCapacity: count,
        financeLimits: FinanceLimits(invoices: count * 2, journalEntries: count * 6 + 16))
    var handles: [EntityHandle] = []
    var expectedJournal: [ExpectedPosting] = []
    var expectedBills: [ExpectedBill] = []
    var aircraftRevision: UInt64 = 0
    var expectedIncome: Int64 = 0
    var expectedCash = capital
    var totalCompleted = 0
    var injectedStops = 0

    func posting(at: UInt64, kind: JournalKind, debit: LedgerAccount, credit: LedgerAccount,
                 amount: Int64, invoice: UInt64? = nil) -> ExpectedPosting {
        ExpectedPosting(number: UInt64(expectedJournal.count) + 1, at: at,
                        kind: kind, debit: debit, credit: credit, amount: amount, invoice: invoice)
    }
    _ = try world.applyFinance(.contributeCapital(amountMinor: capital), expected: world.inputToken)
    expectedJournal.append(posting(at: 0, kind: .capitalContribution, debit: .cash, credit: .capital,
                                   amount: capital))
    for _ in 0..<count {
        let result = try world.apply(.registerAircraft(at: 1), expected: world.inputToken)
        handles.append(result.handle)
        aircraftRevision += 1
    }

    for wave in 0..<2 {
        let startsAt = UInt64(wave * 20)
        let target = startsAt + 20
        let destination = UInt32(wave + 2)
        var expectedArrivals: [ExpectedArrival] = []
        let billOffset = expectedBills.count
        for index in 0..<count {
            // Repeated timestamps and interspersed unpriced flights are deliberate.
            let duration = UInt64((index * 11 + seed + wave * 3) % 17 + 1)
            let fare: Int64 = (index + seed + wave) % 5 == 0 ? 0 : Int64((index * 37 + seed) % 113 + 1)
            aircraftRevision += 1
            expectedArrivals.append(ExpectedArrival(ordinal: index, operation: aircraftRevision,
                at: startsAt + duration, fare: fare))
            if fare == 0 {
                _ = try world.apply(.depart(handles[index], destination: destination, durationSeconds: duration),
                                    expected: world.inputToken)
            } else {
                _ = try world.departPriced(handles[index], destination: destination, durationSeconds: duration,
                                           fareMinor: fare, expected: world.inputToken)
            }
        }
        expectedArrivals.sort { left, right in
            left.at == right.at ? left.ordinal < right.ordinal : left.at < right.at
        }
        var nextExpected = 0
        var calls = 0
        let targets = splitTargets ? Array((startsAt + 1)...target) : [target]
        for requested in targets {
            while true {
                calls += 1
                try #require(calls < 1_000, "Advance failed to make bounded progress")
                let oldInput = world.inputToken
                let before = world.auditForTesting()
                let result: AdvanceResult
                if injectFailures && calls % 4 == 1 && (world.nextArrival?.arrivesAt ?? .max) <= requested {
                    // Alternate zero-prefix and one-prefix failures; retries use normal advance.
                    result = try world.advanceForTesting(to: requested, eventBudget: budget,
                                                        failAtEventIndex: (calls / 4) % 2)
                } else {
                    result = try world.advance(to: requested, eventBudget: budget)
                }
                verifyTrip(world.inputToken == oldInput && result.processedEvents <= budget)
                for actual in result.completions {
                    try #require(nextExpected < expectedArrivals.count)
                    let wanted = expectedArrivals[nextExpected]
                    verifyTrip(actual.trip.handle == handles[wanted.ordinal])
                    verifyTrip(actual.trip.operationID == wanted.operation && actual.trip.arrivesAt == wanted.at)
                    verifyTrip(actual.trip.destination == destination && actual.completedTrips == UInt64(wave + 1))
                    if wanted.fare == 0 {
                        verifyTrip(actual.invoice == nil)
                    } else {
                        let bill = try #require(actual.invoice)
                        let number = UInt64(expectedBills.count) + 1
                        verifyTrip(bill.handle.number == number && bill.amountMinor == wanted.fare && bill.paidMinor == 0)
                        verifyTrip(bill.origin.aircraft == handles[wanted.ordinal] && bill.origin.operationID == wanted.operation)
                        verifyTrip(bill.issuedAt == wanted.at && bill.currency == .sar)
                        expectedBills.append(ExpectedBill(number: number, slot: handles[wanted.ordinal].slot,
                            operation: wanted.operation, at: wanted.at, amount: wanted.fare))
                        expectedIncome += wanted.fare
                        expectedJournal.append(posting(at: wanted.at, kind: .invoiceIssued, debit: .receivables,
                                                        credit: .revenue, amount: wanted.fare, invoice: number))
                    }
                    nextExpected += 1
                    totalCompleted += 1
                    aircraftRevision += 1
                }
                verifyTrip(world.financialSummary.revenueMinor == expectedIncome && world.checkInvariants())
                switch result.stop {
                case .reachedTarget:
                    verifyTrip(result.reachedTime == requested)
                case .eventBudgetReached:
                    verifyTrip(result.processedEvents == budget && result.nextDueTime != nil)
                case .blocked(let reason):
                    verifyTrip(reason == .injectedPreparationFailure)
                    injectedStops += 1
                    if result.processedEvents == 0 { verifyTrip(before == world.auditForTesting()) }
                }
                if result.stop == .reachedTarget { break }
            }
        }
        verifyTrip(nextExpected == count && world.pendingArrivals == 0 && world.now == target)

        // Two collections per invoice when possible; neither can add revenue.
        for expected in expectedBills.dropFirst(billOffset) {
            let invoicePage = try world.invoicePage(offset: Int(expected.number - 1), limit: 1)
            let bill = try #require(invoicePage.first)
            let pieces = [expected.amount / 2, expected.amount - expected.amount / 2]
            for amount in pieces where amount > 0 {
                _ = try world.applyFinance(.collectInvoice(bill.handle, amountMinor: amount), expected: world.inputToken)
                expectedCash += amount
                expectedJournal.append(posting(at: target, kind: .invoiceCollected, debit: .cash,
                                                credit: .receivables, amount: amount, invoice: expected.number))
                verifyTrip(world.financialSummary.revenueMinor == expectedIncome)
            }
        }
        let expenses: [(CashExpenseKind, LedgerAccount)] = [(.payroll, .payrollExpense),
            (.maintenance, .maintenanceExpense), (.operating, .operatingExpense)]
        for (kind, account) in expenses {
            _ = try world.applyFinance(.payExpense(kind, amountMinor: 13), expected: world.inputToken)
            expectedCash -= 13
            expectedJournal.append(posting(at: target, kind: .cashExpense(kind), debit: account,
                                            credit: .cash, amount: 13))
        }
        for handle in handles {
            let value = try world.read(handle)
            verifyTrip(value.currentAirport == destination && value.activeTrip == nil && value.completedTrips == UInt64(wave + 1))
        }
    }

    var actualJournal: [ExpectedPosting] = []
    var offset = 0
    while offset < world.financialSummary.journalCount {
        let page = try world.journalPage(offset: offset, limit: 37)
        try #require(!page.isEmpty && page.count <= 37)
        actualJournal += page.map { ExpectedPosting(number: $0.number, at: $0.at, kind: $0.kind,
            debit: $0.debit, credit: $0.credit, amount: $0.amountMinor, invoice: $0.invoice?.number) }
        offset += page.count
    }
    verifyTrip(actualJournal == expectedJournal)
    for wanted in expectedBills {
        let invoicePage = try world.invoicePage(offset: Int(wanted.number - 1), limit: 1)
        let actual = try #require(invoicePage.first)
        verifyTrip(actual.handle.number == wanted.number && actual.origin.aircraft.slot == wanted.slot)
        verifyTrip(actual.origin.operationID == wanted.operation && actual.issuedAt == wanted.at)
        verifyTrip(actual.amountMinor == wanted.amount && actual.paidMinor == wanted.amount && actual.dueMinor == 0)
    }
    let summary = world.financialSummary
    verifyTrip(summary.cashMinor == expectedCash && summary.receivablesMinor == 0)
    verifyTrip(summary.revenueMinor == expectedIncome && summary.contributedCapitalMinor == capital)
    verifyTrip(summary.payrollExpenseMinor == 26 && summary.maintenanceExpenseMinor == 26 && summary.operatingExpenseMinor == 26)
    verifyTrip(summary.journalCount == expectedJournal.count && summary.invoiceCount == expectedBills.count)
    verifyTrip(totalCompleted == count * 2 && world.checkInvariants())
    if injectFailures { verifyTrip(injectedStops > 0) }
    return PartitionEvidence(bills: expectedBills, journal: actualJournal, income: expectedIncome,
        cash: expectedCash, invoiceCount: summary.invoiceCount, completions: totalCompleted)
}

struct FinancialPartitionTests {
    @Test(arguments: [19, 401, 1009])
    func D01_budgetsAndTargetPartitionsMatchIndependentFinancialOracle(_ seed: Int) throws {
        let reference = try runFinancialPartition(seed: seed, budget: 1_024, splitTargets: false, injectFailures: false)
        for budget in [1, 7, 31] {
            let actual = try runFinancialPartition(seed: seed, budget: budget, splitTargets: true, injectFailures: false)
            verifyTrip(actual == reference)
        }
    }

    @Test(arguments: [19, 401, 1009])
    func D02_injectedPrefixRetriesMatchUninterruptedFinancialHistory(_ seed: Int) throws {
        let reference = try runFinancialPartition(seed: seed, budget: 1_024, splitTargets: false, injectFailures: false)
        for budget in [7, 31] {
            let actual = try runFinancialPartition(seed: seed, budget: budget, splitTargets: true, injectFailures: true)
            verifyTrip(actual == reference)
        }
    }
}
