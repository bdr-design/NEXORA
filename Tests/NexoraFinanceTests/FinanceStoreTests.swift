import Testing
import NexoraIdentity
@testable import NexoraFinance

func checkFinance(_ condition: Bool, fileID: String = #fileID, filePath: String = #filePath,
                  line: Int = #line, column: Int = #column) {
    #expect(condition, sourceLocation: SourceLocation(fileID: fileID, filePath: filePath,
                                                     line: line, column: column))
}
func origin(_ operation: UInt64 = 1) throws -> InvoiceOrigin {
    var identities = try EntitySpace(capacity: 1)
    return InvoiceOrigin(aircraft: try identities.create(), operationID: operation)
}
func rejectFinance(_ command: FinanceCommand, _ expectedError: FinanceFailure,
                   store: inout FinanceStore, token: FinanceToken? = nil) {
    let before = store.auditForTesting()
    do { _ = try store.apply(command, expected: token ?? store.token); Issue.record("Expected financial rejection") }
    catch { checkFinance(error as? FinanceFailure == expectedError) }
    checkFinance(before == store.auditForTesting())
    checkFinance(store.checkInvariants())
}
@discardableResult
func capital(_ store: inout FinanceStore, _ amount: Int64, at: UInt64 = 0) throws -> FinanceReceipt {
    try store.apply(.contributeCapital(amountMinor: amount, at: at), expected: store.token)
}
@discardableResult
func invoice(_ store: inout FinanceStore, _ source: InvoiceOrigin, _ amount: Int64,
             at: UInt64 = 0) throws -> InvoiceView {
    let result = try store.apply(.issueInvoice(origin: source, amountMinor: amount, at: at), expected: store.token)
    return try #require(result.invoice)
}
@discardableResult
func collect(_ store: inout FinanceStore, _ handle: InvoiceHandle, _ amount: Int64,
             at: UInt64 = 0) throws -> FinanceReceipt {
    try store.apply(.collectInvoice(handle, amountMinor: amount, at: at), expected: store.token)
}

struct FinanceStoreTests {
    @Test(arguments: [-1, 1_000_001, Int.max])
    func F01_invalidCapacity(_ bad: Int) {
        for limits in [FinanceLimits(invoices: bad, journalEntries: 0), FinanceLimits(invoices: 0, journalEntries: bad)] {
            do { _ = try FinanceStore(limits: limits); Issue.record("Expected invalid ledger capacity") }
            catch { checkFinance(error as? FinanceFailure == .invalidCapacity) }
        }
    }

    @Test func F02_zeroCapacityIsReadableButCannotPost() throws {
        var store = try FinanceStore(limits: .disabled)
        checkFinance(store.summary.cashMinor == 0 && store.summary.revenueMinor == 0 && store.checkInvariants())
        checkFinance(try store.invoicePage(offset: 0, limit: 1).isEmpty)
        rejectFinance(.contributeCapital(amountMinor: 1, at: 0), .journalCapacityExhausted, store: &store)
    }

    @Test(arguments: ["", "saR", "S", "SARX", "سار", "1AR", "S A"])
    func F03_currencyShapeIsValidated(_ code: String) {
        do { _ = try CurrencySpec(code: code, minorDigits: 2); Issue.record("Expected invalid currency") }
        catch { checkFinance(error as? FinanceFailure == .invalidCurrency) }
    }

    @Test func F04_currencyScaleAndMinorUnitsAreExplicit() throws {
        do { _ = try CurrencySpec(code: "SAR", minorDigits: 7); Issue.record("Expected invalid minor scale") }
        catch { checkFinance(error as? FinanceFailure == .invalidCurrency) }
        let currency = try CurrencySpec(code: "XYZ", minorDigits: 0)
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 3), currency: currency)
        let issued = try invoice(&store, origin(), 1)
        checkFinance(issued.amountMinor == 1 && issued.currency == currency && store.summary.currency == currency)
        checkFinance(store.summary.revenueMinor == 1 && store.checkInvariants())
    }

    @Test func F05_capitalIsNotRevenue() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 2))
        let receipt = try capital(&store, 12345)
        checkFinance(store.summary.cashMinor == 12345 && store.summary.contributedCapitalMinor == 12345)
        checkFinance(store.summary.revenueMinor == 0 && store.summary.receivablesMinor == 0)
        checkFinance(receipt.entry.debit == .cash && receipt.entry.credit == .capital && receipt.invoice == nil)
        checkFinance(store.checkInvariants())
    }

    @Test func F06_invoiceRecognizesReceivableAndRevenueNotCash() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 3))
        let source = try origin(7)
        let issued = try invoice(&store, source, 24001, at: 11)
        checkFinance(issued.handle.number == 1 && issued.origin == source && issued.issuedAt == 11)
        checkFinance(issued.paidMinor == 0 && issued.dueMinor == 24001)
        checkFinance(store.summary.cashMinor == 0 && store.summary.receivablesMinor == 24001)
        checkFinance(store.summary.revenueMinor == 24001 && store.invoice(for: source) == issued.handle)
        let journal = try store.journalPage(offset: 0, limit: 1)
        checkFinance(journal[0].kind == .invoiceIssued && journal[0].debit == .receivables && journal[0].credit == .revenue)
        checkFinance(store.checkInvariants())
    }

    @Test func F07_collectionDoesNotRecognizeRevenueTwice() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 5))
        let issued = try invoice(&store, origin(), 10000)
        let first = try collect(&store, issued.handle, 2501, at: 1)
        checkFinance(first.invoice?.paidMinor == 2501 && first.invoice?.dueMinor == 7499)
        checkFinance(store.summary.cashMinor == 2501 && store.summary.receivablesMinor == 7499)
        checkFinance(store.summary.revenueMinor == 10000)
        try collect(&store, issued.handle, 7499, at: 2)
        checkFinance(store.summary.cashMinor == 10000 && store.summary.receivablesMinor == 0)
        checkFinance(store.summary.revenueMinor == 10000 && store.journalCount == 3 && store.checkInvariants())
    }

    @Test func F08_overpaymentAndPaidInvoiceAreRejected() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 9))
        let issued = try invoice(&store, origin(), 5)
        rejectFinance(.collectInvoice(issued.handle, amountMinor: 6, at: 0), .overpayment, store: &store)
        try collect(&store, issued.handle, 5)
        rejectFinance(.collectInvoice(issued.handle, amountMinor: 1, at: 0), .overpayment, store: &store)
    }

    @Test func F09_duplicateOriginNeverProducesAnotherInvoice() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 5, journalEntries: 10))
        let source = try origin()
        let issued = try invoice(&store, source, 1)
        rejectFinance(.issueInvoice(origin: source, amountMinor: 99, at: 0), .duplicateOrigin, store: &store)
        try collect(&store, issued.handle, 1)
        rejectFinance(.issueInvoice(origin: source, amountMinor: 99, at: 0), .duplicateOrigin, store: &store)
        checkFinance(store.invoiceCount == 1 && store.summary.revenueMinor == 1)
    }

    @Test func F10_zeroOriginIsRejected() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 1))
        rejectFinance(.issueInvoice(origin: try origin(0), amountMinor: 1, at: 0), .invalidOrigin, store: &store)
    }

    @Test(arguments: [Int64.min, -1, 0])
    func F11_invalidAmountsNeverWrite(_ amount: Int64) throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 8))
        let source = try origin()
        let issued = try invoice(&store, source, 7)
        for command: FinanceCommand in [.contributeCapital(amountMinor: amount, at: 0),
                                       .issueInvoice(origin: source, amountMinor: amount, at: 0),
                                       .collectInvoice(issued.handle, amountMinor: amount, at: 0),
                                       .payExpense(.payroll, amountMinor: amount, at: 0)] {
            rejectFinance(command, .invalidAmount, store: &store)
        }
    }

    @Test func F12_cashExpensesDebitCorrectAccounts() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 4))
        try capital(&store, 100)
        for kind in CashExpenseKind.allCases {
            _ = try store.apply(.payExpense(kind, amountMinor: 17, at: 0), expected: store.token)
        }
        let summary = store.summary
        checkFinance(summary.cashMinor == 49 && summary.payrollExpenseMinor == 17)
        checkFinance(summary.maintenanceExpenseMinor == 17 && summary.operatingExpenseMinor == 17)
        checkFinance(summary.revenueMinor == 0 && summary.contributedCapitalMinor == 100 && store.checkInvariants())
    }

    @Test func F13_insufficientCashDoesNotCreateAnExpense() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 8))
        _ = try invoice(&store, origin(), 10000)
        rejectFinance(.payExpense(.maintenance, amountMinor: 1, at: 0), .insufficientCash, store: &store)
        try capital(&store, 5)
        rejectFinance(.payExpense(.payroll, amountMinor: 6, at: 0), .insufficientCash, store: &store)
        _ = try store.apply(.payExpense(.payroll, amountMinor: 5, at: 0), expected: store.token)
        checkFinance(store.summary.cashMinor == 0 && store.summary.payrollExpenseMinor == 5)
    }

    @Test func F14_foreignAndStaleTokensHaveStablePrecedence() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 3))
        let other = try FinanceStore(limits: .disabled)
        rejectFinance(.contributeCapital(amountMinor: 0, at: 0), .foreignToken, store: &store, token: other.token)
        let old = store.token
        try capital(&store, 5)
        rejectFinance(.contributeCapital(amountMinor: 0, at: 0), .revisionConflict, store: &store, token: old)
    }

    @Test func F15_foreignInvoiceWithSameNumberCannotBeCollected() throws {
        var left = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 3))
        var right = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 3))
        let a = try invoice(&left, origin(), 10), b = try invoice(&right, origin(), 10)
        checkFinance(a.handle.number == b.handle.number && a.handle != b.handle)
        rejectFinance(.collectInvoice(a.handle, amountMinor: 1, at: 0), .foreignInvoice, store: &right)
        do { _ = try right.readInvoice(a.handle); Issue.record("Foreign invoice read succeeded") }
        catch { checkFinance(error as? FinanceFailure == .foreignInvoice) }
    }

    @Test(arguments: [UInt64(0), 2, UInt64.max])
    func F16_unknownInvoiceNumberIsRejected(_ number: UInt64) throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 5))
        _ = try invoice(&store, origin(), 1)
        let unknown = store.invoiceHandleForTesting(number: number)
        rejectFinance(.collectInvoice(unknown, amountMinor: 1, at: 0), .unknownInvoice, store: &store)
        do { _ = try store.readInvoice(unknown); Issue.record("Unknown read succeeded") }
        catch { checkFinance(error as? FinanceFailure == .unknownInvoice) }
    }

    @Test func F17_invoiceCapacityBackpressuresWithoutGrowingHistory() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 5))
        _ = try invoice(&store, origin(), 10)
        rejectFinance(.issueInvoice(origin: try origin(), amountMinor: 10, at: 0), .invoiceCapacityExhausted, store: &store)
        checkFinance(store.invoiceCount == 1 && store.invoiceCapacity == 1 && store.journalCount == 1)
    }

    @Test func F18_journalCapacityDoesNotDropOrOverwriteEntries() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 2, journalEntries: 1))
        let issued = try invoice(&store, origin(), 10)
        rejectFinance(.collectInvoice(issued.handle, amountMinor: 10, at: 0), .journalCapacityExhausted, store: &store)
        checkFinance(store.summary.cashMinor == 0 && store.summary.receivablesMinor == 10)
        checkFinance(store.invoiceCount == 1 && store.journalCount == 1)
    }

    @Test func F19_receivableOverflowPreservesBothSides() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 2, journalEntries: 5))
        _ = try invoice(&store, origin(), .max)
        rejectFinance(.issueInvoice(origin: try origin(), amountMinor: 1, at: 0), .balanceOverflow, store: &store)
        checkFinance(store.summary.receivablesMinor == .max && store.summary.revenueMinor == .max)
    }

    @Test func F20_creditMagnitudeCannotReachUnnegatableMinimum() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 2, journalEntries: 8))
        try capital(&store, .max)
        _ = try store.apply(.payExpense(.operating, amountMinor: 1, at: 0), expected: store.token)
        rejectFinance(.contributeCapital(amountMinor: 1, at: 0), .balanceOverflow, store: &store)
        let issued = try invoice(&store, origin(), .max)
        try collect(&store, issued.handle, 1)
        rejectFinance(.issueInvoice(origin: try origin(), amountMinor: 1, at: 0), .balanceOverflow, store: &store)
        checkFinance(store.summary.contributedCapitalMinor == .max && store.summary.revenueMinor == .max)
    }

    @Test func F21_cashOverflowDoesNotMarkInvoicePaid() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 5))
        try capital(&store, .max)
        let issued = try invoice(&store, origin(), 1)
        rejectFinance(.collectInvoice(issued.handle, amountMinor: 1, at: 0), .balanceOverflow, store: &store)
        checkFinance(try store.readInvoice(issued.handle).paidMinor == 0)
    }

    @Test func F22_expenseOverflowDoesNotDeductCash() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 8))
        try capital(&store, .max)
        _ = try store.apply(.payExpense(.maintenance, amountMinor: .max, at: 0), expected: store.token)
        let issued = try invoice(&store, origin(), 1)
        try collect(&store, issued.handle, 1)
        rejectFinance(.payExpense(.maintenance, amountMinor: 1, at: 0), .balanceOverflow, store: &store)
        checkFinance(store.summary.cashMinor == 1 && store.summary.maintenanceExpenseMinor == .max)
    }

    @Test func F23_revisionExhaustionStillPermitsReads() throws {
        var store = try FinanceStore(testingLimits: FinanceLimits(invoices: 0, journalEntries: 2), initialRevision: .max - 1)
        let old = store.token
        try capital(&store, 1)
        rejectFinance(.contributeCapital(amountMinor: 0, at: 0), .revisionConflict, store: &store, token: old)
        rejectFinance(.contributeCapital(amountMinor: 0, at: 0), .revisionExhausted, store: &store)
        checkFinance(store.summary.cashMinor == 1 && store.token.revision == .max && store.checkInvariants())
    }

    @Test func F24_postingTimeCannotGoBackwardsOrOverflow() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 4))
        try capital(&store, 3, at: .max)
        rejectFinance(.contributeCapital(amountMinor: 1, at: .max - 1), .nonMonotonicTime, store: &store)
        let issued = try invoice(&store, origin(), 1, at: .max)
        checkFinance(issued.issuedAt == .max && store.checkInvariants())
    }

    @Test func F25_preparingAndDiscardingAreSideEffectFree() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 4))
        let source = try origin()
        let before = store.auditForTesting()
        func discardPlan(_ plan: consuming PreparedFinance) {}
        let plan = try store.prepare(.issueInvoice(origin: source, amountMinor: 5, at: 0), expected: store.token)
        checkFinance(before == store.auditForTesting())
        discardPlan(consume plan)
        checkFinance(before == store.auditForTesting())
        let next = try store.prepare(.issueInvoice(origin: source, amountMinor: 5, at: 0), expected: store.token)
        let result = store.commit(consume next)
        checkFinance(result.invoice?.handle.number == 1 && store.invoiceCount == 1 && store.checkInvariants())
    }

    @Test func F26_oldViewsPagesAndAuditsCannotMutateStoredState() throws {
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 4))
        let old = try invoice(&store, origin(), 10)
        let oldPage = try store.invoicePage(offset: 0, limit: 1)
        let oldJournal = try store.journalPage(offset: 0, limit: 4)
        var balances = store.auditForTesting().balances
        balances[0] = 999
        try collect(&store, old.handle, 3)
        checkFinance(old.paidMinor == 0 && oldPage[0].paidMinor == 0 && oldJournal.count == 1)
        checkFinance(store.summary.cashMinor == 3 && store.journalCount == 2 && store.checkInvariants())
    }

    @Test func F27_pageBoundsAreValidatedWithoutIntegerOverflow() throws {
        let store = try FinanceStore(limits: .disabled)
        for (offset, limit) in [(-1,1),(1,1),(Int.max,1),(0,0),(0,-1),(0,257),(0,Int.max)] {
            do { _ = try store.invoicePage(offset: offset, limit: limit); Issue.record("Invalid invoice page") }
            catch { checkFinance(error as? FinanceFailure == .invalidPage) }
            do { _ = try store.journalPage(offset: offset, limit: limit); Issue.record("Invalid journal page") }
            catch { checkFinance(error as? FinanceFailure == .invalidPage) }
        }
        checkFinance(store.checkInvariants())
    }

    @Test func F28_historyRemainsAfterOriginalAircraftIsRetired() throws {
        var ids = try EntitySpace(capacity: 1)
        let h = try ids.create()
        var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 4))
        let source = InvoiceOrigin(aircraft: h, operationID: 7)
        let issued = try invoice(&store, source, 10)
        try ids.destroy(h)
        _ = try ids.create()
        try collect(&store, issued.handle, 10)
        checkFinance(try store.readInvoice(issued.handle).origin == source)
        checkFinance(store.summary.revenueMinor == 10 && store.summary.cashMinor == 10 && store.checkInvariants())
    }

    @Test func F29_movingLedgerPreservesInvoiceAndTokenIdentity() throws {
        var original = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 4))
        let issued = try invoice(&original, origin(), 5)
        let token = original.token
        var moved = consume original
        checkFinance(moved.token == token)
        try collect(&moved, issued.handle, 5)
        checkFinance(moved.summary.cashMinor == 5 && moved.checkInvariants())
    }

    @Test func F30_independentLedgersHaveNoSharedMutableState() async throws {
        try await withThrowingTaskGroup(of: InvoiceHandle.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    var store = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 3))
                    let issued = try invoice(&store, origin(), 123)
                    try collect(&store, issued.handle, 123)
                    checkFinance(store.summary.revenueMinor == 123 && store.summary.cashMinor == 123)
                    checkFinance(store.checkInvariants())
                    return issued.handle
                }
            }
            var seen = Set<InvoiceHandle>()
            for try await handle in group { seen.insert(handle) }
            checkFinance(seen.count == 16)
        }
    }
}
