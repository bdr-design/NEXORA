import NexoraFinance
func invalid() throws { _ = try FinanceStore(testingLimits: .disabled, initialRevision: 1) }
