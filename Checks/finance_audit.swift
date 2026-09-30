import NexoraFinance
func invalid() throws {
    let ledger = try FinanceStore(limits: .disabled)
    _ = ledger.auditForTesting()
}
