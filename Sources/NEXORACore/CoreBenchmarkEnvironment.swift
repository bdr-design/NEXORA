import NEXORADiagnostics

/// Test/benchmark composition helper only. This is not a gameplay environment.
public final class CoreBenchmarkEnvironment: Sendable {
    public let gate: TransactionGate
    public let coordinator: TransactionCoordinator
    public let registry: EntityRegistry
    public let assets: AssetDomain

    public init(capacity: Int, traceSink: any TraceSink = NullTraceSink()) {
        let ids = TraceIDSource()
        let gate = TransactionGate()
        self.gate = gate
        self.coordinator = TransactionCoordinator(gate: gate)
        self.registry = EntityRegistry(capacity: capacity, traceSink: traceSink, traceIDs: ids)
        self.assets = AssetDomain(capacity: capacity, gate: gate, traceSink: traceSink, traceIDs: ids)
    }

    public func seedAssets(count: Int) -> [EntityID] {
        precondition(count >= 0)
        var ids: [EntityID] = []
        ids.reserveCapacity(count)
        for _ in 0..<count {
            let id = registry.create()
            let result = assets.attach(id: id, initial: AssetInitialState(value: 100.0))
            guard case .attached = result else {
                preconditionFailure("Failed to attach newly created entity \(id): \(result)")
            }
            ids.append(id)
        }
        return ids
    }
}
