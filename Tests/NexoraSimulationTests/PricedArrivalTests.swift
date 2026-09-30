import Testing
import NexoraIdentity
import NexoraFinance
@testable import NexoraSimulation

@discardableResult
func pricedDeparture(_ world: inout TripSimulation, _ handle: EntityHandle,
                     destination: UInt32 = 2, seconds: UInt64 = 10, fare: Int64 = 100) throws -> TripInputReceipt {
    try world.departPriced(handle, destination: destination, durationSeconds: seconds,
                           fareMinor: fare, expected: world.inputToken)
}
func rejectFinancialInput(_ command: FinancialInputCommand, _ error: TripFailure,
                          world: inout TripSimulation, token: TripInputToken? = nil) {
    let before = world.auditForTesting()
    do { _ = try world.applyFinance(command, expected: token ?? world.inputToken); Issue.record("Expected finance input rejection") }
    catch let actual as TripFailure { verifyTrip(actual == error) }
    catch { Issue.record("Unexpected financial input error: \(error)") }
    verifyTrip(before == world.auditForTesting() && world.checkInvariants())
}

struct PricedArrivalTests {
    @Test func C01_pricedTripRecognizesNothingUntilArrival() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 3))
        let h = try register(&world, airport: 7)
        let sent = try pricedDeparture(&world, h, destination: 9, seconds: 40, fare: 12301)
        verifyTrip(world.financialSummary.revenueMinor == 0 && world.financialSummary.invoiceCount == 0)
        _ = try world.advance(to: 39, eventBudget: 1)
        verifyTrip(world.financialSummary.revenueMinor == 0 && world.pendingArrivals == 1)
        let result = try world.advance(to: 40, eventBudget: 1)
        let completion = try #require(result.completions.first)
        let issued = try #require(completion.invoice)
        verifyTrip(issued.origin.aircraft == h && issued.origin.operationID == sent.activeTrip?.operationID)
        verifyTrip(issued.amountMinor == 12301 && issued.paidMinor == 0 && issued.issuedAt == 40)
        verifyTrip(world.financialSummary.cashMinor == 0 && world.financialSummary.receivablesMinor == 12301)
        verifyTrip(world.financialSummary.revenueMinor == 12301 && world.pendingArrivals == 0)
        verifyTrip(try world.read(h).currentAirport == 9 && world.checkInvariants())
    }

    @Test func C02_collectionDoesNotAddIncomeAgain() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 5))
        let h = try register(&world)
        try pricedDeparture(&world, h, fare: 101)
        let result = try world.advance(to: 10, eventBudget: 1)
        let issued = try #require(result.completions.first?.invoice)
        _ = try world.applyFinance(.collectInvoice(issued.handle, amountMinor: 40), expected: world.inputToken)
        verifyTrip(world.financialSummary.revenueMinor == 101 && world.financialSummary.cashMinor == 40)
        verifyTrip(world.financialSummary.receivablesMinor == 61)
        _ = try world.applyFinance(.collectInvoice(issued.handle, amountMinor: 61), expected: world.inputToken)
        verifyTrip(world.financialSummary.revenueMinor == 101 && world.financialSummary.cashMinor == 101)
        rejectFinancialInput(.collectInvoice(issued.handle, amountMinor: 1), .finance(.overpayment), world: &world)
        verifyTrip(world.checkInvariants())
    }

    @Test func C03_fullInvoiceStoreBlocksBeforeAnyAircraftOrClockWrite() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 0, journalEntries: 3))
        let h = try register(&world)
        let sent = try pricedDeparture(&world, h)
        let before = world.auditForTesting()
        let result = try world.advance(to: 999, eventBudget: 1)
        verifyTrip(result.stop == .blocked(.finance(.invoiceCapacityExhausted)))
        verifyTrip(result.processedEvents == 0 && result.reachedTime == 0)
        verifyTrip(world.nextArrival == sent.activeTrip && before == world.auditForTesting())
        verifyTrip(world.financialSummary.invoiceCount == 0 && world.checkInvariants())
    }

    @Test func C04_fullJournalBlocksAndRetainsDueEvent() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 3, journalEntries: 1))
        _ = try world.applyFinance(.contributeCapital(amountMinor: 7), expected: world.inputToken)
        let h = try register(&world)
        try pricedDeparture(&world, h)
        let before = world.auditForTesting()
        let result = try world.advance(to: 100, eventBudget: 1)
        verifyTrip(result.stop == .blocked(.finance(.journalCapacityExhausted)))
        verifyTrip(before == world.auditForTesting() && world.financialSummary.cashMinor == 7)
    }

    @Test func C05_capacityFailureReturnsExactlyThePreviouslyCommittedPrefix() throws {
        var world = try TripSimulation(capacity: 2, eventCapacity: 2,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 3))
        let first = try register(&world), second = try register(&world)
        try pricedDeparture(&world, first, seconds: 10, fare: 7)
        try pricedDeparture(&world, second, seconds: 20, fare: 9)
        let result = try world.advance(to: 100, eventBudget: 2)
        verifyTrip(result.processedEvents == 1 && result.completions[0].trip.handle == first)
        verifyTrip(result.stop == .blocked(.finance(.invoiceCapacityExhausted)) && result.reachedTime == 10)
        verifyTrip(world.financialSummary.revenueMinor == 7 && world.financialSummary.invoiceCount == 1)
        verifyTrip(try world.read(second).completedTrips == 0 && world.pendingArrivals == 1)
        let beforeRetry = world.auditForTesting()
        let retry = try world.advance(to: 100, eventBudget: 2)
        verifyTrip(retry.processedEvents == 0 && retry.stop == result.stop && beforeRetry == world.auditForTesting())
        verifyTrip(world.checkInvariants())
    }

    @Test func C06_faultAfterPreparingInvoiceLeavesEverythingUntouched() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 2))
        let h = try register(&world)
        try pricedDeparture(&world, h)
        let before = world.auditForTesting()
        let failed = try world.advanceForTesting(to: 100, eventBudget: 1, failAtEventIndex: 0)
        verifyTrip(failed.stop == .blocked(.injectedPreparationFailure))
        verifyTrip(before == world.auditForTesting())
        let success = try world.advance(to: 100, eventBudget: 1)
        verifyTrip(success.processedEvents == 1 && success.completions[0].invoice?.handle.number == 1)
        verifyTrip(world.financialSummary.revenueMinor == 100 && world.checkInvariants())
    }

    @Test func C07_injectedPrefixRetryNeverDuplicatesInvoices() throws {
        var world = try TripSimulation(capacity: 3, eventCapacity: 3,
                                       financeLimits: FinanceLimits(invoices: 3, journalEntries: 6))
        for seconds: UInt64 in [1,2,3] {
            try pricedDeparture(&world, try register(&world), seconds: seconds, fare: Int64(seconds))
        }
        let first = try world.advanceForTesting(to: 100, eventBudget: 3, failAtEventIndex: 1)
        verifyTrip(first.processedEvents == 1 && world.financialSummary.revenueMinor == 1)
        let second = try world.advance(to: 100, eventBudget: 3)
        verifyTrip(second.processedEvents == 2 && world.financialSummary.revenueMinor == 6)
        verifyTrip(world.financialSummary.invoiceCount == 3 && world.financialSummary.journalCount == 3)
        verifyTrip(try world.advance(to: 100, eventBudget: 3).processedEvents == 0)
        verifyTrip(try world.invoicePage(offset: 0, limit: 3).map { $0.handle.number } == [1,2,3])
        verifyTrip(world.checkInvariants())
    }

    @Test func C08_aircraftFailureDiscardsPreparedFinancialEffects() throws {
        var world = try TripSimulation(testingCapacity: 1, eventCapacity: 1,
                                       initialAircraftRevision: .max - 2,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 3))
        let h = try register(&world)
        try pricedDeparture(&world, h, fare: 1000)
        let before = world.auditForTesting()
        let result = try world.advance(to: 100, eventBudget: 1)
        verifyTrip(result.stop == .blocked(.aircraft(.revisionExhausted)))
        verifyTrip(result.processedEvents == 0 && before == world.auditForTesting())
        verifyTrip(world.financialSummary.invoiceCount == 0 && world.financialSummary.revenueMinor == 0)
        verifyTrip(world.checkInvariants())
    }

    @Test func C09_financeRevisionExhaustionLeavesAircraftActive() throws {
        var world = try TripSimulation(testingCapacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 3),
                                       initialFinanceRevision: .max)
        let h = try register(&world)
        try pricedDeparture(&world, h)
        let before = world.auditForTesting()
        let result = try world.advance(to: 100, eventBudget: 1)
        verifyTrip(result.stop == .blocked(.finance(.revisionExhausted)))
        verifyTrip(before == world.auditForTesting() && world.pendingArrivals == 1)
    }

    @Test func C10_balanceOverflowCannotCompleteItsFlight() throws {
        var world = try TripSimulation(capacity: 2, eventCapacity: 2,
                                       financeLimits: FinanceLimits(invoices: 2, journalEntries: 4))
        let first = try register(&world), second = try register(&world)
        try pricedDeparture(&world, first, seconds: 1, fare: .max)
        try pricedDeparture(&world, second, seconds: 2, fare: 1)
        let result = try world.advance(to: 100, eventBudget: 2)
        verifyTrip(result.processedEvents == 1 && result.stop == .blocked(.finance(.balanceOverflow)))
        verifyTrip(result.reachedTime == 1 && world.financialSummary.revenueMinor == .max)
        verifyTrip(try world.read(first).completedTrips == 1 && world.read(second).completedTrips == 0)
        verifyTrip(world.financialSummary.invoiceCount == 1 && world.checkInvariants())
    }

    @Test func C11_financialInputsAndAirlineInputsShareOnlyManualSequence() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 6))
        let h = try register(&world)
        let beforeCapital = world.inputToken
        _ = try world.applyFinance(.contributeCapital(amountMinor: 100), expected: beforeCapital)
        rejectTrip(.depart(h, destination: 2, durationSeconds: 1), .inputConflict, simulation: &world, token: beforeCapital)
        try pricedDeparture(&world, h)
        let pending = world.inputToken
        let result = try world.advance(to: 10, eventBudget: 1)
        verifyTrip(world.inputToken == pending)
        let issued = try #require(result.completions.first?.invoice)
        _ = try world.applyFinance(.collectInvoice(issued.handle, amountMinor: 100), expected: pending)
        rejectFinancialInput(.collectInvoice(issued.handle, amountMinor: 100), .inputConflict, world: &world, token: pending)
        verifyTrip(world.financialSummary.cashMinor == 200 && world.financialSummary.revenueMinor == 100)
        verifyTrip(world.checkInvariants())
    }

    @Test func C12_injectedManualFinancialFailureHasNoSideEffects() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 10))
        let h = try register(&world)
        try pricedDeparture(&world, h)
        let result = try world.advance(to: 10, eventBudget: 1)
        let issued = try #require(result.completions.first?.invoice)
        _ = try world.applyFinance(.contributeCapital(amountMinor: 100), expected: world.inputToken)
        for command: FinancialInputCommand in [.contributeCapital(amountMinor: 1),
                                               .collectInvoice(issued.handle, amountMinor: 1),
                                               .payExpense(.maintenance, amountMinor: 1)] {
            let before = world.auditForTesting()
            do {
                _ = try world.applyFinanceForTesting(command, expected: world.inputToken)
                Issue.record("Expected financial injection")
            } catch { verifyTrip(error as? TripTestFailure == .beforeInputCommit) }
            verifyTrip(before == world.auditForTesting())
        }
        verifyTrip(world.checkInvariants())
    }

    @Test func C13_oldInvoicesSurviveRetirementAndSlotReuse() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 2, journalEntries: 6))
        let old = try register(&world)
        try pricedDeparture(&world, old)
        let first = try world.advance(to: 10, eventBudget: 1)
        let issued = try #require(first.completions.first?.invoice)
        _ = try world.apply(.retireAircraft(old), expected: world.inputToken)
        let replacement = try register(&world, airport: 5)
        verifyTrip(old.slot == replacement.slot && old.generation != replacement.generation)
        try pricedDeparture(&world, replacement, destination: 6, fare: 200)
        let second = try world.advance(to: 20, eventBudget: 1)
        verifyTrip(second.completions.first?.invoice?.origin.aircraft == replacement)
        _ = try world.applyFinance(.collectInvoice(issued.handle, amountMinor: 100), expected: world.inputToken)
        verifyTrip(try world.readInvoice(issued.handle).origin.aircraft == old)
        verifyTrip(world.financialSummary.revenueMinor == 300 && world.financialSummary.cashMinor == 100)
        verifyTrip(world.financialSummary.receivablesMinor == 200 && world.checkInvariants())
    }

    @Test func C14_recurringTripsHaveDistinctInvoicesAndCorrectOrigins() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 2, journalEntries: 5))
        let h = try register(&world)
        try pricedDeparture(&world, h, destination: 2, seconds: 1, fare: 30)
        let first = try world.advance(to: 1, eventBudget: 1)
        try pricedDeparture(&world, h, destination: 3, seconds: 1, fare: 70)
        let second = try world.advance(to: 2, eventBudget: 1)
        let a = try #require(first.completions.first?.invoice), b = try #require(second.completions.first?.invoice)
        verifyTrip(a.handle != b.handle && a.origin.operationID != b.origin.operationID)
        verifyTrip(a.origin.aircraft == h && b.origin.aircraft == h)
        verifyTrip(world.financialSummary.revenueMinor == 100 && world.financialSummary.invoiceCount == 2)
        verifyTrip(try world.read(h).completedTrips == 2 && world.checkInvariants())
    }

    @Test(arguments: [Int64.min, -1, 0])
    func C15_invalidPricedFareDoesNotStartOrEnqueue(_ amount: Int64) throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 3))
        let h = try register(&world)
        let before = world.auditForTesting()
        do { try pricedDeparture(&world, h, fare: amount); Issue.record("Expected invalid fare") }
        catch { verifyTrip(error as? TripFailure == .finance(.invalidAmount)) }
        verifyTrip(before == world.auditForTesting() && world.checkInvariants())
    }

    @Test func C16_pricedAndUnpricedTripsDoNotConfuseFinancialEffects() throws {
        var world = try TripSimulation(capacity: 2, eventCapacity: 2,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 4))
        let unpriced = try register(&world), priced = try register(&world)
        try depart(&world, unpriced)
        try pricedDeparture(&world, priced, fare: 99)
        let result = try world.advance(to: 10, eventBudget: 2)
        verifyTrip(result.completions.count == 2 && result.completions[0].invoice == nil)
        verifyTrip(result.completions[1].invoice?.amountMinor == 99 && world.financialSummary.invoiceCount == 1)
        verifyTrip(world.financialSummary.revenueMinor == 99 && world.checkInvariants())
    }

    @Test func C17_manualPostBetweenSameTimeArrivalBatchesPreservesOrder() throws {
        var world = try TripSimulation(capacity: 2, eventCapacity: 2,
                                       financeLimits: FinanceLimits(invoices: 2, journalEntries: 5))
        let first = try register(&world), second = try register(&world)
        try pricedDeparture(&world, first, fare: 2)
        try pricedDeparture(&world, second, fare: 3)
        let one = try world.advance(to: 100, eventBudget: 1)
        verifyTrip(one.reachedTime == 10 && one.stop == .eventBudgetReached)
        _ = try world.applyFinance(.contributeCapital(amountMinor: 7), expected: world.inputToken)
        let two = try world.advance(to: 100, eventBudget: 1)
        verifyTrip(two.processedEvents == 1 && world.financialSummary.revenueMinor == 5)
        let journal = try world.journalPage(offset: 0, limit: 5)
        verifyTrip(journal.map(\.at) == [10,10,10])
        verifyTrip(journal.map(\.kind) == [.invoiceIssued,.capitalContribution,.invoiceIssued])
        verifyTrip(world.now == 100 && world.checkInvariants())
    }

    @Test func C18_foreignInvoiceAndCurrencyAreBoundToTheirLedger() throws {
        let currency = try CurrencySpec(code: "ABC", minorDigits: 3)
        var left = try TripSimulation(capacity: 1, eventCapacity: 1,
                                      financeLimits: FinanceLimits(invoices: 1, journalEntries: 3), currency: currency)
        var right = try TripSimulation(capacity: 0, eventCapacity: 0,
                                       financeLimits: FinanceLimits(invoices: 0, journalEntries: 3))
        try pricedDeparture(&left, try register(&left), fare: 2001)
        let result = try left.advance(to: 10, eventBudget: 1)
        let issued = try #require(result.completions.first?.invoice)
        verifyTrip(issued.currency == currency && left.financialSummary.currency == currency)
        rejectFinancialInput(.collectInvoice(issued.handle, amountMinor: 1), .finance(.foreignInvoice), world: &right)
    }

    @Test func C19_cashOverflowCannotMarkCollectedOrAdvanceInput() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 5))
        _ = try world.applyFinance(.contributeCapital(amountMinor: .max), expected: world.inputToken)
        try pricedDeparture(&world, try register(&world), fare: 1)
        let result = try world.advance(to: 10, eventBudget: 1)
        let issued = try #require(result.completions.first?.invoice)
        rejectFinancialInput(.collectInvoice(issued.handle, amountMinor: 1), .finance(.balanceOverflow), world: &world)
        verifyTrip(try world.readInvoice(issued.handle).paidMinor == 0 && world.financialSummary.receivablesMinor == 1)
    }

    @Test func C20_expenseInputsCannotSpendReceivablesOrChangeTripState() throws {
        var world = try TripSimulation(capacity: 1, eventCapacity: 1,
                                       financeLimits: FinanceLimits(invoices: 1, journalEntries: 8))
        try pricedDeparture(&world, try register(&world), fare: 10)
        let result = try world.advance(to: 10, eventBudget: 1)
        let issued = try #require(result.completions.first?.invoice)
        rejectFinancialInput(.payExpense(.payroll, amountMinor: 1), .finance(.insufficientCash), world: &world)
        _ = try world.applyFinance(.collectInvoice(issued.handle, amountMinor: 10), expected: world.inputToken)
        for kind in CashExpenseKind.allCases {
            _ = try world.applyFinance(.payExpense(kind, amountMinor: 2), expected: world.inputToken)
        }
        verifyTrip(world.financialSummary.cashMinor == 4 && world.financialSummary.revenueMinor == 10)
        verifyTrip(world.financialSummary.payrollExpenseMinor == 2 && world.financialSummary.maintenanceExpenseMinor == 2)
        verifyTrip(world.financialSummary.operatingExpenseMinor == 2 && world.checkInvariants())
    }

    @Test func C21_invalidFinanceLimitsCannotConstructAWorld() {
        do {
            _ = try TripSimulation(capacity: 0, eventCapacity: 0,
                                   financeLimits: FinanceLimits(invoices: -1, journalEntries: 0))
            Issue.record("Invalid finance capacity constructed")
        } catch { verifyTrip(error as? TripFailure == .finance(.invalidCapacity)) }
    }

    @Test(arguments: [1_000,5_000,20_000,50_000,100_000])
    func C22_pricedArrivalsAndCollectionsAtScale(_ count: Int) throws {
        var world = try TripSimulation(capacity: count, eventCapacity: count,
                                       financeLimits: FinanceLimits(invoices: count, journalEntries: count * 2))
        var handles: [EntityHandle] = []; handles.reserveCapacity(count)
        for index in 0..<count {
            let h = try register(&world); handles.append(h)
            try pricedDeparture(&world, h, seconds: UInt64(index % 300 + 1), fare: Int64(index % 97 + 1))
        }
        var expectedIncome: Int64 = 0
        var processed = 0
        while world.pendingArrivals > 0 {
            let result = try world.advance(to: 300, eventBudget: 256)
            verifyTrip(result.stop == .reachedTarget || result.stop == .eventBudgetReached)
            for completion in result.completions {
                let issued = try #require(completion.invoice)
                verifyTrip(issued.origin.aircraft == completion.trip.handle && issued.origin.operationID == completion.trip.operationID)
                verifyTrip(issued.amountMinor == completion.trip.fareMinor && issued.paidMinor == 0)
                expectedIncome += issued.amountMinor; processed += 1
            }
        }
        verifyTrip(processed == count && world.financialSummary.revenueMinor == expectedIncome)
        verifyTrip(world.financialSummary.cashMinor == 0 && world.financialSummary.receivablesMinor == expectedIncome)
        var offset = 0
        while offset < count {
            let page = try world.invoicePage(offset: offset, limit: 256)
            for issued in page {
                _ = try world.applyFinance(.collectInvoice(issued.handle, amountMinor: issued.amountMinor), expected: world.inputToken)
            }
            offset += page.count
        }
        verifyTrip(world.financialSummary.cashMinor == expectedIncome && world.financialSummary.receivablesMinor == 0)
        verifyTrip(world.financialSummary.revenueMinor == expectedIncome && world.financialSummary.journalCount == count * 2)
        verifyTrip(world.financialSummary.invoiceCount == count && world.checkInvariants())
        for h in handles { verifyTrip(try world.read(h).completedTrips == 1) }
    }
}
