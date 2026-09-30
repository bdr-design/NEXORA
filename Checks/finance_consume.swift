import NexoraFinance
func invalid() throws {
    let original = try FinanceStore(limits: .disabled)
    let moved = consume original
    print(moved.invoiceCount)
    print(original.invoiceCount)
}
