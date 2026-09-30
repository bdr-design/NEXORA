import NexoraFinance
func invalid() throws {
    let ledger = try FinanceStore(limits: .disabled)
    print(ledger.balances)
}
