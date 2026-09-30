import Testing
import NexoraIdentity
@testable import NexoraFinance

// Independent arithmetic model: positive balances and an invoice dictionary.
// It does not call FinanceStore or its posting/prepare/audit helpers.
private struct RefSource: Equatable, Hashable {
    let owner: Int
    let slot: UInt32
    let generation: UInt32
    let operation: UInt64
}
private struct RefBill: Equatable {
    let source: RefSource
    let at: UInt64
    let amount: Int64
    var paid: Int64
}
private enum RefKind: Equatable { case capital, bill, collect, expense(Int) }
private struct RefEntry: Equatable {
    let number: UInt64
    let at: UInt64
    let kind: RefKind
    let amount: Int64
    let invoice: UInt64?
}
private struct RefBooks {
    var revision: UInt64 = 0
    var lastTime: UInt64 = 0
    var cash: Int64 = 0
    var receivable: Int64 = 0
    var earned: Int64 = 0
    var capital: Int64 = 0
    var expenses: [Int64] = [0,0,0]
    var bills: [UInt64: RefBill] = [:]
    var sources: [RefSource: UInt64] = [:]
    var entries: [RefEntry] = []
    let invoiceLimit: Int
    let journalLimit: Int

    mutating func apply(kind: RefKind, amount: Int64, at: UInt64, source: RefSource?, invoice: UInt64?,
                        expected: UInt64, foreignToken: Bool, foreignInvoice: Bool) throws -> RefEntry {
        if foreignToken { throw FinanceFailure.foreignToken }
        if expected != revision { throw FinanceFailure.revisionConflict }
        if revision == .max { throw FinanceFailure.revisionExhausted }
        if amount <= 0 { throw FinanceFailure.invalidAmount }
        if at < lastTime { throw FinanceFailure.nonMonotonicTime }
        if entries.count == journalLimit { throw FinanceFailure.journalCapacityExhausted }
        var postedInvoice: UInt64?
        switch kind {
        case .capital:
            if amount > .max - cash || amount > .max - capital { throw FinanceFailure.balanceOverflow }
            cash += amount; capital += amount
        case .bill:
            guard let source else { fatalError("Reference source missing") }
            if source.operation == 0 { throw FinanceFailure.invalidOrigin }
            if sources[source] != nil { throw FinanceFailure.duplicateOrigin }
            if bills.count == invoiceLimit { throw FinanceFailure.invoiceCapacityExhausted }
            if amount > .max - receivable || amount > .max - earned { throw FinanceFailure.balanceOverflow }
            let number = UInt64(bills.count) + 1
            bills[number] = RefBill(source: source, at: at, amount: amount, paid: 0)
            sources[source] = number; postedInvoice = number
            receivable += amount; earned += amount
        case .collect:
            if foreignInvoice { throw FinanceFailure.foreignInvoice }
            guard let invoice, var bill = bills[invoice] else { throw FinanceFailure.unknownInvoice }
            if amount > bill.amount - bill.paid { throw FinanceFailure.overpayment }
            if amount > .max - cash { throw FinanceFailure.balanceOverflow }
            cash += amount; receivable -= amount; bill.paid += amount
            bills[invoice] = bill; postedInvoice = invoice
        case .expense(let index):
            if amount > cash { throw FinanceFailure.insufficientCash }
            if amount > .max - expenses[index] { throw FinanceFailure.balanceOverflow }
            cash -= amount; expenses[index] += amount
        }
        revision += 1; lastTime = at
        let entry = RefEntry(number: revision, at: at, kind: kind, amount: amount, invoice: postedInvoice)
        entries.append(entry)
        return entry
    }
}
private struct FinanceRandom {
    var state: UInt64
    mutating func next(_ bound: Int) -> Int {
        state = state &* 3202034522624059733 &+ 1
        return Int((state >> 23) % UInt64(bound))
    }
}
private func normalize(_ entry: JournalEntry) -> RefEntry {
    let kind: RefKind
    switch entry.kind {
    case .capitalContribution: kind = .capital
    case .invoiceIssued: kind = .bill
    case .invoiceCollected: kind = .collect
    case .cashExpense(let expense): kind = .expense(Int(expense.rawValue))
    }
    return RefEntry(number: entry.number, at: entry.at, kind: kind, amount: entry.amountMinor, invoice: entry.invoice?.number)
}

struct FinanceReferenceTests {
    @Test(arguments: [UInt64(19), 1009, 77_777, 888_111])
    func independentAccountingMatchesEveryCommandAndRejection(_ seed: UInt64) throws {
        // A small bounded oracle emphasizes exhaustion/retry interleavings. The
        // separate C22 fixture retains all five sizes through 100,000 aircraft.
        var store = try FinanceStore(limits: FinanceLimits(invoices: 128, journalEntries: 2048))
        var other = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 3))
        let foreignBill = try invoice(&other, origin(), 20)
        var identities = try EntitySpace(capacity: 17)
        var handles: [EntityHandle] = []
        for _ in 0..<17 { handles.append(try identities.create()) }
        let foreignSource = try origin().aircraft
        var model = RefBooks(invoiceLimit: 128, journalLimit: 2048)
        var tokens = [store.token]
        var knownBills: [UInt64: InvoiceHandle] = [:]
        var random = FinanceRandom(state: seed)
        var accepted = 0, rejected = 0, collected = 0
        for step in 0..<5_000 {
            let kindIndex = random.next(5)
            let ownerIndex = random.next(29) == 0 ? 1 : 0
            let h = ownerIndex == 0 ? handles[random.next(handles.count)] : foreignSource
            let operation = UInt64(random.next(1001))
            let source = InvoiceOrigin(aircraft: h, operationID: operation)
            let referenceSource = RefSource(owner: ownerIndex, slot: h.slot, generation: h.generation, operation: operation)
            let foreignToken = random.next(29) == 0
            let token = foreignToken ? other.token : (random.next(7) == 0 ? tokens[random.next(tokens.count)] : store.token)
            let at = model.lastTime > 0 && random.next(13) == 0 ? model.lastTime - 1 : model.lastTime + UInt64(random.next(3))
            let foreignInvoice = random.next(17) == 0
            let invoiceNumber = knownBills.isEmpty ? UInt64(0) : UInt64(random.next(knownBills.count) + 1)
            let invoiceHandle = foreignInvoice ? foreignBill.handle :
                (knownBills[invoiceNumber] ?? store.invoiceHandleForTesting(number: invoiceNumber))
            let amount = Int64(random.next(1402)) - 1
            let kind: RefKind
            let command: FinanceCommand
            switch kindIndex {
            case 0:
                kind = .capital; command = .contributeCapital(amountMinor: amount, at: at)
            case 1,2:
                kind = .bill; command = .issueInvoice(origin: source, amountMinor: amount, at: at)
            case 3:
                kind = .collect; command = .collectInvoice(invoiceHandle, amountMinor: amount, at: at)
            default:
                let index = random.next(3)
                kind = .expense(index)
                let expense = try #require(CashExpenseKind(rawValue: UInt8(index)))
                command = .payExpense(expense, amountMinor: amount, at: at)
            }
            let before = store.auditForTesting()
            var expected: RefEntry?, expectedError: FinanceFailure?
            do {
                expected = try model.apply(kind: kind, amount: amount, at: at, source: referenceSource,
                                           invoice: invoiceHandle.number, expected: token.revision,
                                           foreignToken: foreignToken, foreignInvoice: foreignInvoice)
            } catch { expectedError = error as? FinanceFailure; checkFinance(expectedError != nil) }
            do {
                let actual = try store.apply(command, expected: token)
                checkFinance(normalize(actual.entry) == expected && expectedError == nil)
                if case .bill = kind, let bill = actual.invoice { knownBills[bill.handle.number] = bill.handle }
                if case .collect = kind { collected += 1 }
                tokens.append(actual.token); accepted += 1
            } catch {
                checkFinance(error as? FinanceFailure == expectedError && expected == nil)
                checkFinance(before == store.auditForTesting()); rejected += 1
            }
            let audit = store.auditForTesting()
            checkFinance(audit.token.revision == model.revision && audit.lastTime == model.lastTime)
            checkFinance(audit.balances == [model.cash, model.receivable, -model.earned, -model.capital] + model.expenses)
            checkFinance(audit.invoiceCount == model.bills.count && audit.journalCount == model.entries.count)
            checkFinance(audit.origins.count == model.sources.count)
            // Compare EVERY row on EVERY step. Aggregate the successful assertion
            // bookkeeping instead of constructing millions of Testing source locations.
            var mismatchedInvoice: UInt64?
            for (number, bill) in model.bills {
                guard let actual = audit.invoices[Int(number - 1)] else {
                    mismatchedInvoice = number; break
                }
                let actualOwner = actual.origin.aircraft == foreignSource ? 1 : 0
                let normalized = RefSource(owner: actualOwner, slot: actual.origin.aircraft.slot,
                                           generation: actual.origin.aircraft.generation, operation: actual.origin.operationID)
                guard normalized == bill.source, actual.issuedAt == bill.at,
                      actual.amountMinor == bill.amount, actual.paidMinor == bill.paid,
                      audit.origins[actual.origin] == actual.handle else {
                    mismatchedInvoice = number; break
                }
            }
            checkFinance(mismatchedInvoice == nil)
            if let mismatchedInvoice {
                Issue.record("Finance model mismatch at seed \(seed), step \(step), invoice \(mismatchedInvoice)")
            }
            checkFinance(store.checkInvariants())
            if step % 97 == 0 {
                checkFinance(audit.journal.compactMap { $0 }.map(normalize) == model.entries)
            }
        }
        checkFinance(accepted > 1000 && rejected > 1000 && collected > 50)
        print("Finance reference seed \(seed): 5000 commands, accepted \(accepted), rejected \(rejected), collections \(collected)")
    }
}
