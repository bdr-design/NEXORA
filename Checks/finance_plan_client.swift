import NexoraFinance
func allowedWithinPackage() throws {
    var ledger = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 1))
    let prepared = try ledger.prepare(.contributeCapital(amountMinor: 1, at: 0), expected: ledger.token)
    let result = ledger.commit(consume prepared)
    print(result.entry.number)
}
