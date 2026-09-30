import NexoraFinance
func invalid() throws {
    let ledger = try FinanceStore(limits: .disabled)
    _ = try ledger.prepare(.contributeCapital(amountMinor: 1, at: 0), expected: ledger.token)
}
