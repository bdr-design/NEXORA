import NexoraFinance
import NexoraIdentity
func allowedFinanceClient() throws {
    var ids = try EntitySpace(capacity: 1)
    let source = InvoiceOrigin(aircraft: try ids.create(), operationID: 1)
    var books = try FinanceStore(limits: FinanceLimits(invoices: 1, journalEntries: 4))
    _ = try books.apply(.contributeCapital(amountMinor: 1, at: 0), expected: books.token)
    let result = try books.apply(.issueInvoice(origin: source, amountMinor: 2, at: 1), expected: books.token)
    if let invoice = result.invoice {
        _ = try books.apply(.collectInvoice(invoice.handle, amountMinor: 2, at: 2), expected: books.token)
    }
    _ = try books.apply(.payExpense(.payroll, amountMinor: 1, at: 3), expected: books.token)
    print(books.summary.cashMinor)
}
