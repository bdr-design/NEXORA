import Testing
import NexoraFinance

struct FinanceInputBoundaryTests {
    @Test func F31_longAndMultibyteCurrencyInputsAreRejected() throws {
        // Input rejection coverage; not an allocation or thermal benchmark.
        let invalid = [String(repeating: "A", count: 1_000_000), "AAAA", "ＡＡＡ", "SA😀"]
        for code in invalid {
            do {
                _ = try CurrencySpec(code: code, minorDigits: 2)
                Issue.record("Invalid or oversized currency was accepted")
            } catch { checkFinance(error as? FinanceFailure == .invalidCurrency) }
        }
        checkFinance(try CurrencySpec(code: "AAA", minorDigits: 0).code == "AAA")
        checkFinance(try CurrencySpec(code: "ZZZ", minorDigits: 6).minorDigits == 6)
    }

}
