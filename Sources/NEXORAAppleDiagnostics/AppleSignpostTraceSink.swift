import NEXORADiagnostics

#if canImport(os)
import os

public final class AppleSignpostTraceSink: TraceSink, Sendable {
    private let signposter: OSSignposter

    public init(subsystem: String = "com.bdrdesign.nexora", category: String = "CoreTrace") {
        self.signposter = OSSignposter(subsystem: subsystem, category: category)
    }

    public func record(_ record: TraceRecord) {
        let id = signposter.makeSignpostID()
        signposter.emitEvent(
            "NEXORA.Trace",
            id: id,
            "domain=\(record.domain.rawValue) op=\(record.operation.rawValue) duration_ns=\(record.durationNanoseconds) work=\(record.workCount) revision=\(record.revision) result=\(record.result.rawValue)"
        )
    }
}
#else
public final class AppleSignpostTraceSink: TraceSink, Sendable {
    public init(subsystem: String = "com.bdrdesign.nexora", category: String = "CoreTrace") {}
    public func record(_ record: TraceRecord) {}
}
#endif
