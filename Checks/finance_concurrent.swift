import NexoraFinance
func invalid() async throws {
    var ledger = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 2))
    let token = ledger.token
    async let a = ledger.apply(.contributeCapital(amountMinor: 1, at: 0), expected: token)
    async let b = ledger.apply(.contributeCapital(amountMinor: 1, at: 0), expected: token)
    _ = try await (a,b)
}
