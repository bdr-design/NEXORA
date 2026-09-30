import NexoraFinance
func invalidWithinPackage() throws {
    var ledger = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 2))
    let prepared = try ledger.prepare(.contributeCapital(amountMinor: 1, at: 0), expected: ledger.token)
    _ = ledger.commit(consume prepared)
    _ = ledger.commit(consume prepared)
}
