import NexoraIdentity

public enum FinanceFailure: Error, Equatable, Sendable {
    case invalidCapacity, invalidCurrency, foreignToken, revisionConflict, revisionExhausted
    case invalidAmount, nonMonotonicTime, journalCapacityExhausted, invoiceCapacityExhausted
    case invalidOrigin, duplicateOrigin, foreignInvoice, unknownInvoice, overpayment
    case insufficientCash, balanceOverflow, invalidPage
}

/// Validated shape, not a claim that every three-letter code is an ISO currency.
public struct CurrencySpec: Equatable, Sendable {
    public let code: String
    public let minorDigits: UInt8
    public static var sar: CurrencySpec { CurrencySpec(validatedCode: "SAR", minorDigits: 2) }
    public init(code: String, minorDigits: UInt8) throws {
        let bytes = Array(code.utf8)
        guard bytes.count == 3, bytes.allSatisfy({ (65...90).contains($0) }), minorDigits <= 6 else {
            throw FinanceFailure.invalidCurrency
        }
        self.code = code
        self.minorDigits = minorDigits
    }
    private init(validatedCode: String, minorDigits: UInt8) {
        code = validatedCode
        self.minorDigits = minorDigits
    }
}

public struct FinanceLimits: Equatable, Sendable {
    public let invoices: Int
    public let journalEntries: Int
    public static var disabled: FinanceLimits { FinanceLimits(invoices: 0, journalEntries: 0) }
    public init(invoices: Int, journalEntries: Int) {
        self.invoices = invoices
        self.journalEntries = journalEntries
    }
}

private final class LedgerStamp: Sendable {}

public struct FinanceToken: Equatable, Sendable {
    fileprivate let stamp: LedgerStamp
    public let revision: UInt64
    fileprivate init(stamp: LedgerStamp, revision: UInt64) { self.stamp = stamp; self.revision = revision }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stamp === rhs.stamp && lhs.revision == rhs.revision
    }
}

/// Local capability, not the persistent invoice identity required by save/load.
public struct InvoiceHandle: Equatable, Hashable, Sendable {
    fileprivate let stamp: LedgerStamp
    public let number: UInt64
    fileprivate init(stamp: LedgerStamp, number: UInt64) { self.stamp = stamp; self.number = number }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stamp === rhs.stamp && lhs.number == rhs.number
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(stamp)); hasher.combine(number)
    }
}

/// The coordinator authenticates the live aircraft; the ledger enforces uniqueness.
public struct InvoiceOrigin: Equatable, Hashable, Sendable {
    public let aircraft: EntityHandle
    public let operationID: UInt64
    public init(aircraft: EntityHandle, operationID: UInt64) {
        self.aircraft = aircraft; self.operationID = operationID
    }
}

public enum LedgerAccount: UInt8, CaseIterable, Sendable {
    case cash, receivables, revenue, capital, payrollExpense, maintenanceExpense, operatingExpense
}
public enum CashExpenseKind: UInt8, Sendable, CaseIterable {
    case payroll, maintenance, operating
    fileprivate var account: LedgerAccount {
        switch self {
        case .payroll: .payrollExpense
        case .maintenance: .maintenanceExpense
        case .operating: .operatingExpense
        }
    }
}
public enum JournalKind: Equatable, Sendable {
    case capitalContribution, invoiceIssued, invoiceCollected
    case cashExpense(CashExpenseKind)
}
public enum FinanceCommand: Equatable, Sendable {
    case contributeCapital(amountMinor: Int64, at: UInt64)
    case issueInvoice(origin: InvoiceOrigin, amountMinor: Int64, at: UInt64)
    case collectInvoice(InvoiceHandle, amountMinor: Int64, at: UInt64)
    case payExpense(CashExpenseKind, amountMinor: Int64, at: UInt64)
}

public struct InvoiceView: Equatable, Sendable {
    public let handle: InvoiceHandle
    public let origin: InvoiceOrigin
    public let issuedAt: UInt64
    public let amountMinor: Int64
    public let paidMinor: Int64
    public let currency: CurrencySpec
    public var dueMinor: Int64 { amountMinor - paidMinor }
}
public struct JournalEntry: Equatable, Sendable {
    public let number: UInt64
    public let at: UInt64
    public let kind: JournalKind
    public let debit: LedgerAccount
    public let credit: LedgerAccount
    public let amountMinor: Int64
    public let invoice: InvoiceHandle?
}
public struct FinanceSummary: Equatable, Sendable {
    public let currency: CurrencySpec
    public let cashMinor: Int64
    public let receivablesMinor: Int64
    public let revenueMinor: Int64
    public let contributedCapitalMinor: Int64
    public let payrollExpenseMinor: Int64
    public let maintenanceExpenseMinor: Int64
    public let operatingExpenseMinor: Int64
    public let invoiceCount: Int
    public let journalCount: Int
    public let token: FinanceToken
}
public struct FinanceReceipt: Equatable, Sendable {
    public let entry: JournalEntry
    public let invoice: InvoiceView?
    public let token: FinanceToken
}

private struct InvoiceRecord: Equatable, Sendable {
    let handle: InvoiceHandle
    let origin: InvoiceOrigin
    let issuedAt: UInt64
    let amount: Int64
    let paid: Int64
}

/// Opaque and consumed exactly once; only this module can construct a plan.
package struct PreparedFinance: ~Copyable, Sendable {
    fileprivate let stamp: LedgerStamp
    fileprivate let expectedRevision: UInt64
    fileprivate let entry: JournalEntry
    fileprivate let invoice: InvoiceRecord?
    fileprivate let newInvoice: Bool
    fileprivate let debitBalance: Int64
    fileprivate let creditBalance: Int64
}

/// One owner, bounded history, exact minor units, balanced two-sided postings.
/// Ordinary apply is atomic for expected failures; durable storage is not implemented here.
public struct FinanceStore: ~Copyable, Sendable {
    public static var maximumCapacity: Int { 1_000_000 }
    public static var maximumPageSize: Int { 256 }
    private let stamp: LedgerStamp
    public let currency: CurrencySpec
    private let revisionBase: UInt64
    private let timeBase: UInt64
    private var revision: UInt64
    private var lastTime: UInt64
    private var balances: [Int64]
    private var invoices: [InvoiceRecord?]
    private var journal: [JournalEntry?]
    private var origins: [InvoiceOrigin: InvoiceHandle]
    public private(set) var invoiceCount: Int
    public private(set) var journalCount: Int
    public var invoiceCapacity: Int { invoices.count }
    public var journalCapacity: Int { journal.count }
    public var lastPostedTime: UInt64 { lastTime }
    public var token: FinanceToken { FinanceToken(stamp: stamp, revision: revision) }

    public init(limits: FinanceLimits, currency: CurrencySpec = .sar) throws {
        try self.init(testingLimits: limits, currency: currency)
    }
    package init(testingLimits: FinanceLimits, currency: CurrencySpec = .sar,
                 initialRevision: UInt64 = 0, initialTime: UInt64 = 0) throws {
        guard (0...Self.maximumCapacity).contains(testingLimits.invoices),
              (0...Self.maximumCapacity).contains(testingLimits.journalEntries) else {
            throw FinanceFailure.invalidCapacity
        }
        stamp = LedgerStamp()
        self.currency = currency
        revisionBase = initialRevision; revision = initialRevision
        timeBase = initialTime; lastTime = initialTime
        balances = Array(repeating: 0, count: LedgerAccount.allCases.count)
        invoices = Array(repeating: nil, count: testingLimits.invoices)
        journal = Array(repeating: nil, count: testingLimits.journalEntries)
        origins = [:]; origins.reserveCapacity(testingLimits.invoices)
        invoiceCount = 0; journalCount = 0
    }

    public func balance(_ account: LedgerAccount) -> Int64 { balances[Int(account.rawValue)] }
    public var summary: FinanceSummary {
        FinanceSummary(currency: currency, cashMinor: balance(.cash), receivablesMinor: balance(.receivables),
            revenueMinor: -balance(.revenue), contributedCapitalMinor: -balance(.capital),
            payrollExpenseMinor: balance(.payrollExpense), maintenanceExpenseMinor: balance(.maintenanceExpense),
            operatingExpenseMinor: balance(.operatingExpense), invoiceCount: invoiceCount,
            journalCount: journalCount, token: token)
    }
    public func readInvoice(_ handle: InvoiceHandle) throws -> InvoiceView { view(try record(handle)) }
    public func invoice(for origin: InvoiceOrigin) -> InvoiceHandle? { origins[origin] }

    public func invoicePage(offset: Int, limit: Int) throws -> [InvoiceView] {
        try validatePage(offset: offset, limit: limit, count: invoiceCount)
        let end = min(invoiceCount, offset + limit)
        var result: [InvoiceView] = []
        result.reserveCapacity(end - offset)
        for index in offset..<end {
            guard let row = invoices[index] else { fatalError("NEXORA_FINANCE_INVARIANT: invoice hole") }
            result.append(view(row))
        }
        return result
    }
    public func journalPage(offset: Int, limit: Int) throws -> [JournalEntry] {
        try validatePage(offset: offset, limit: limit, count: journalCount)
        let end = min(journalCount, offset + limit)
        return (offset..<end).map { index in
            guard let entry = journal[index] else { fatalError("NEXORA_FINANCE_INVARIANT: journal hole") }
            return entry
        }
    }
    private func validatePage(offset: Int, limit: Int, count: Int) throws {
        guard (0...count).contains(offset), (1...Self.maximumPageSize).contains(limit) else {
            throw FinanceFailure.invalidPage
        }
    }
    private func record(_ handle: InvoiceHandle) throws -> InvoiceRecord {
        guard handle.stamp === stamp else { throw FinanceFailure.foreignInvoice }
        guard handle.number > 0, handle.number <= UInt64(invoiceCount) else { throw FinanceFailure.unknownInvoice }
        guard let row = invoices[Int(handle.number - 1)], row.handle == handle else {
            fatalError("NEXORA_FINANCE_INVARIANT: missing or mismatched invoice")
        }
        return row
    }
    private func view(_ row: InvoiceRecord) -> InvoiceView {
        InvoiceView(handle: row.handle, origin: row.origin, issuedAt: row.issuedAt,
                    amountMinor: row.amount, paidMinor: row.paid, currency: currency)
    }

    public mutating func apply(_ command: FinanceCommand, expected: FinanceToken) throws -> FinanceReceipt {
        let plan = try prepare(command, expected: expected)
        return commit(consume plan)
    }

    /// All recoverable checks happen before any write. This method has no side effects.
    package func prepare(_ command: FinanceCommand, expected: FinanceToken) throws -> PreparedFinance {
        guard expected.stamp === stamp else { throw FinanceFailure.foreignToken }
        guard expected.revision == revision else { throw FinanceFailure.revisionConflict }
        guard revision < UInt64.max else { throw FinanceFailure.revisionExhausted }
        let amount: Int64, at: UInt64
        switch command {
        case .contributeCapital(let value, let time), .issueInvoice(_, let value, let time),
             .collectInvoice(_, let value, let time), .payExpense(_, let value, let time):
            amount = value; at = time
        }
        guard amount > 0 else { throw FinanceFailure.invalidAmount }
        guard at >= lastTime else { throw FinanceFailure.nonMonotonicTime }
        guard journalCount < journal.count else { throw FinanceFailure.journalCapacityExhausted }
        let debit: LedgerAccount, credit: LedgerAccount, kind: JournalKind
        let replacement: InvoiceRecord?, isNew: Bool
        switch command {
        case .contributeCapital:
            debit = .cash; credit = .capital; kind = .capitalContribution
            replacement = nil; isNew = false
        case .issueInvoice(let origin, _, _):
            guard origin.operationID > 0 else { throw FinanceFailure.invalidOrigin }
            guard origins[origin] == nil else { throw FinanceFailure.duplicateOrigin }
            guard invoiceCount < invoices.count else { throw FinanceFailure.invoiceCapacityExhausted }
            let handle = InvoiceHandle(stamp: stamp, number: UInt64(invoiceCount) + 1)
            replacement = InvoiceRecord(handle: handle, origin: origin, issuedAt: at, amount: amount, paid: 0)
            isNew = true; debit = .receivables; credit = .revenue; kind = .invoiceIssued
        case .collectInvoice(let handle, _, _):
            let old = try record(handle)
            guard amount <= old.amount - old.paid else { throw FinanceFailure.overpayment }
            let paid = old.paid.addingReportingOverflow(amount)
            guard !paid.overflow else { throw FinanceFailure.balanceOverflow }
            replacement = InvoiceRecord(handle: handle, origin: old.origin, issuedAt: old.issuedAt,
                                        amount: old.amount, paid: paid.partialValue)
            isNew = false; debit = .cash; credit = .receivables; kind = .invoiceCollected
        case .payExpense(let expense, _, _):
            guard balance(.cash) >= amount else { throw FinanceFailure.insufficientCash }
            replacement = nil; isNew = false; debit = expense.account; credit = .cash; kind = .cashExpense(expense)
        }
        let debitResult = balance(debit).addingReportingOverflow(amount)
        let creditResult = balance(credit).subtractingReportingOverflow(amount)
        guard !debitResult.overflow, !creditResult.overflow,
              debitResult.partialValue >= 0, creditResult.partialValue != Int64.min else {
            throw FinanceFailure.balanceOverflow
        }
        if credit == .cash || credit == .receivables {
            guard creditResult.partialValue >= 0 else {
                fatalError("NEXORA_FINANCE_INVARIANT: validated asset credit became negative")
            }
        }
        let entry = JournalEntry(number: revision + 1, at: at, kind: kind, debit: debit, credit: credit,
                                 amountMinor: amount, invoice: replacement?.handle)
        return PreparedFinance(stamp: stamp, expectedRevision: revision, entry: entry, invoice: replacement,
                               newInvoice: isNew, debitBalance: debitResult.partialValue,
                               creditBalance: creditResult.partialValue)
    }

    /// The enclosing owner guarantees no intervening writer. No expected failure after its first write.
    package mutating func commit(_ plan: consuming PreparedFinance) -> FinanceReceipt {
        guard plan.stamp === stamp, plan.expectedRevision == revision, revision < UInt64.max,
              plan.entry.number == revision + 1, journalCount < journal.count,
              journal[journalCount] == nil else {
            fatalError("NEXORA_FINANCE_INVARIANT: stale/foreign or invalid prepared posting")
        }
        if let row = plan.invoice {
            guard row.handle.stamp === stamp, row.handle.number > 0,
                  row.handle.number <= UInt64(invoices.count) else {
                fatalError("NEXORA_FINANCE_INVARIANT: invalid prepared invoice")
            }
            if plan.newInvoice {
                guard Int(row.handle.number - 1) == invoiceCount, invoices[invoiceCount] == nil,
                      origins[row.origin] == nil else { fatalError("NEXORA_FINANCE_INVARIANT: invoice preparation conflict") }
            } else {
                guard Int(row.handle.number - 1) < invoiceCount,
                      invoices[Int(row.handle.number - 1)]?.handle == row.handle else {
                    fatalError("NEXORA_FINANCE_INVARIANT: missing prepared collection invoice")
                }
            }
        }
        balances[Int(plan.entry.debit.rawValue)] = plan.debitBalance
        balances[Int(plan.entry.credit.rawValue)] = plan.creditBalance
        if let row = plan.invoice {
            invoices[Int(row.handle.number - 1)] = row
            if plan.newInvoice { origins[row.origin] = row.handle; invoiceCount += 1 }
        }
        journal[journalCount] = plan.entry
        journalCount += 1; revision = plan.entry.number; lastTime = plan.entry.at
        let invoiceView: InvoiceView?
        if let row = plan.invoice { invoiceView = view(row) } else { invoiceView = nil }
        return FinanceReceipt(entry: plan.entry, invoice: invoiceView, token: token)
    }

    /// Allocating O(capacity + history) recomputation; never part of apply/prepare/commit.
    public func checkInvariants() -> Bool {
        guard balances.count == LedgerAccount.allCases.count,
              (0...invoices.count).contains(invoiceCount), (0...journal.count).contains(journalCount),
              origins.count == invoiceCount, revision >= revisionBase,
              revision - revisionBase == UInt64(journalCount) else { return false }
        var recomputed = Array(repeating: Int64(0), count: balances.count)
        var billed = Array(repeating: Int64(0), count: invoiceCount)
        var paid = Array(repeating: Int64(0), count: invoiceCount)
        var previousTime = timeBase
        for index in journal.indices {
            if index >= journalCount { if journal[index] != nil { return false }; continue }
            guard let entry = journal[index], entry.number == revisionBase + UInt64(index) + 1,
                  entry.at >= previousTime, entry.amountMinor > 0, entry.debit != entry.credit else { return false }
            previousTime = entry.at
            switch entry.kind {
            case .capitalContribution:
                guard entry.debit == .cash, entry.credit == .capital, entry.invoice == nil else { return false }
            case .cashExpense(let expense):
                guard entry.debit == expense.account, entry.credit == .cash, entry.invoice == nil else { return false }
            case .invoiceIssued, .invoiceCollected:
                guard let handle = entry.invoice, handle.stamp === stamp, handle.number > 0,
                      handle.number <= UInt64(invoiceCount), let row = invoices[Int(handle.number - 1)],
                      row.handle == handle else { return false }
                let slot = Int(handle.number - 1)
                if entry.kind == .invoiceIssued {
                    guard entry.debit == .receivables, entry.credit == .revenue, billed[slot] == 0,
                          row.issuedAt == entry.at else { return false }
                    billed[slot] = entry.amountMinor
                } else {
                    guard entry.debit == .cash, entry.credit == .receivables, billed[slot] > 0,
                          entry.amountMinor <= billed[slot] - paid[slot] else { return false }
                    paid[slot] += entry.amountMinor
                }
            }
            let debit = recomputed[Int(entry.debit.rawValue)].addingReportingOverflow(entry.amountMinor)
            let credit = recomputed[Int(entry.credit.rawValue)].subtractingReportingOverflow(entry.amountMinor)
            guard !debit.overflow, !credit.overflow, debit.partialValue >= 0,
                  credit.partialValue != .min else { return false }
            if entry.credit == .cash || entry.credit == .receivables {
                guard credit.partialValue >= 0 else { return false }
            }
            recomputed[Int(entry.debit.rawValue)] = debit.partialValue
            recomputed[Int(entry.credit.rawValue)] = credit.partialValue
        }
        guard recomputed == balances, previousTime == lastTime else { return false }
        for index in invoices.indices {
            if index >= invoiceCount { if invoices[index] != nil { return false }; continue }
            guard let row = invoices[index], row.handle.stamp === stamp, row.handle.number == UInt64(index) + 1,
                  row.origin.operationID > 0, origins[row.origin] == row.handle, row.amount > 0,
                  row.paid >= 0, row.paid <= row.amount, billed[index] == row.amount, paid[index] == row.paid else {
                return false
            }
        }
        return true
    }

    // Test-only capability for otherwise unreachable unknown-number validation.
    func invoiceHandleForTesting(number: UInt64) -> InvoiceHandle {
        InvoiceHandle(stamp: stamp, number: number)
    }

    package func auditForTesting() -> FinanceAudit {
        var invoiceViews: [InvoiceView?] = []
        invoiceViews.reserveCapacity(invoices.count)
        for row in invoices {
            if let row { invoiceViews.append(view(row)) } else { invoiceViews.append(nil) }
        }
        return FinanceAudit(token: token, currency: currency, revisionBase: revisionBase, timeBase: timeBase,
                     lastTime: lastTime, balances: balances.map { $0 },
                     invoices: invoiceViews, journal: journal.map { $0 },
                     origins: Dictionary(uniqueKeysWithValues: origins.map { ($0.key, $0.value) }),
                     invoiceCount: invoiceCount, journalCount: journalCount)
    }
}

package struct FinanceAudit: Equatable {
    package let token: FinanceToken
    package let currency: CurrencySpec
    package let revisionBase: UInt64
    package let timeBase: UInt64
    package let lastTime: UInt64
    package let balances: [Int64]
    package let invoices: [InvoiceView?]
    package let journal: [JournalEntry?]
    package let origins: [InvoiceOrigin: InvoiceHandle]
    package let invoiceCount: Int
    package let journalCount: Int
}
