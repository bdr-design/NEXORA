import NexoraFinance

switch CommandLine.arguments.dropFirst().first {
case "stale":
    var ledger = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 3))
    let prepared = try ledger.prepare(.contributeCapital(amountMinor: 1, at: 0), expected: ledger.token)
    _ = try ledger.apply(.contributeCapital(amountMinor: 2, at: 0), expected: ledger.token)
    _ = ledger.commit(consume prepared)
case "foreign":
    let original = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 3))
    var other = try FinanceStore(limits: FinanceLimits(invoices: 0, journalEntries: 3))
    let prepared = try original.prepare(.contributeCapital(amountMinor: 1, at: 0), expected: original.token)
    _ = other.commit(consume prepared)
default: fatalError("Unknown finance probe")
}
print("PROBE_FAILED: invalid prepared finance was committed")
