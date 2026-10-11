// NEXORA R005, disposable state-machine micro ONLY. Not a production world, WAL,
// scheduler, save format, or claim of durable storage. No foreign project code.

public enum MicroFailure: Error, Equatable {
    case invalidRequest
    case operationOverflow
    case timeOverflow
    case staleOrActiveAsset
    case transactionBusy
    case readDuringTransaction
    case injectedFailure
    case journalUnavailable
    case uncertainCommit
    case requestConflict
    case recoveryRequired
    case cannotRecover
}

public struct RescheduleRequest: Equatable, Sendable {
    public let id: String
    public let time: UInt64
    public let firstOperation: UInt64
    public let count: Int

    public init(id: String, time: UInt64, firstOperation: UInt64, count: Int) {
        self.id = id
        self.time = time
        self.firstOperation = firstOperation
        self.count = count
    }
}

public struct DurableReceipt: Equatable, Sendable {
    public let id: String
    public let sequence: UInt64
}

// In-memory substitute for the future real durable manifest/WAL. Intentionally
// cannot prove fsync, dirsync, crash durability, throughput, or disk footprint.
public final class JournalMock {
    public enum FailurePoint { case none, beforeDurable, afterDurable }
    private var record: RescheduleRequest?
    private var receipt: DurableReceipt?
    private var receiptFingerprint: UInt64?
    public var nextFailure: FailurePoint = .none

    public init() {}

    public func status(for id: String) -> (RescheduleRequest, DurableReceipt)? {
        guard let record, let receipt, record.id == id else { return nil }
        return (record, receipt)
    }

    // This 64-bit marker is *not* cryptographic or a production durable state
    // commitment. It guards mistaken cross-world receipt reuse in this mock.
    fileprivate func fingerprint(for id: String) -> UInt64? {
        guard record?.id == id, receipt != nil else { return nil }
        return receiptFingerprint
    }

    fileprivate func append(_ request: RescheduleRequest,
                            stateFingerprint: UInt64) throws -> DurableReceipt {
        if let record, let receipt {
            guard record == request, receiptFingerprint == stateFingerprint else {
                throw MicroFailure.requestConflict
            }
            return receipt
        }
        if nextFailure == .beforeDurable { nextFailure = .none; throw MicroFailure.journalUnavailable }
        let receipt = DurableReceipt(id: request.id, sequence: 1)
        self.record = request
        self.receipt = receipt
        self.receiptFingerprint = stateFingerprint
        if nextFailure == .afterDurable { nextFailure = .none; throw MicroFailure.uncertainCommit }
        return receipt
    }

    public func committedRecord() -> RescheduleRequest? { record }
}

public enum TransactionPhase: Equatable {
    case idle
    case validating
    case staging
    case awaitingJournal
    case recoveryRequired
}

public struct Tick: Equatable {
    public let phase: TransactionPhase
    public let workItems: Int
    public let receipt: DurableReceipt?
}

public struct VisibleWorld: Equatable {
    public let count: Int
    public let publishedEvents: Int
    public let activeCount: Int
    public let fingerprint: UInt64
}

fileprivate struct Row {
    var active: Bool = false
    var lastOperation: UInt64 = 0
    var scheduledTime: UInt64 = 0
}

fileprivate struct Event {
    let asset: Int
    let operation: UInt64
    let due: UInt64
}

// Serial-owner research model: all public reads and mutations are blocked for
// the entire transaction. Stage writes reuse an initially empty fixed-capacity
// wheel and cannot throw after preflight except injected fatal errors. A real
// scheduler's invariants and fail-stop recovery still need independent proof.
public final class ChunkedTransactionWorld {
    private var rows: [Row]
    private var wheel: [Event?]
    private var phase: TransactionPhase = .idle
    private var cursor = 0
    private var pendingRequest: RescheduleRequest?
    private var visiblePending = 0
    private var injectStageFailureAt: Int?
    private let checksumSeed: UInt64 = 14695981039346656037
    private var stagedFingerprint: UInt64 = 14695981039346656037
    private var publishedFingerprint: UInt64?

    // The same finite row hash is used by staged checks and diagnostic reads.
    // It is a mock state marker, not a collision-resistant durability root.
    private func appendRowHash(_ index: Int, to digest: inout UInt64) {
        let row = rows[index]
        let event = wheel[index]
        func add(_ field: UInt64) {
            digest = (digest ^ field) &* 1099511628211
        }
        add(UInt64(index))
        add(row.active ? 1 : 0)
        add(row.lastOperation)
        add(row.scheduledTime)
        add(event?.operation ?? 0)
        add(event?.due ?? 0)
        add(event == nil ? 0 : UInt64(event!.asset) + 1)
    }

    private func currentView() -> VisibleWorld {
        var checksum = checksumSeed
        var activeCount = 0
        for i in rows.indices {
            if rows[i].active { activeCount += 1 }
            appendRowHash(i, to: &checksum)
        }
        return VisibleWorld(count: rows.count, publishedEvents: visiblePending,
                            activeCount: activeCount, fingerprint: checksum)
    }

    public init(count: Int) throws {
        guard count > 0 && count <= Int(UInt32.max) else { throw MicroFailure.invalidRequest }
        rows = [Row](repeating: Row(), count: count)
        wheel = [Event?](repeating: nil, count: count)
    }

    public var phaseForDiagnostics: TransactionPhase { phase }
    public var fixedEventSlots: Int { wheel.count }

    public func prepareTestPriorOperation(asset: Int, lastOperation: UInt64) throws {
        guard phase == .idle && (0..<rows.count).contains(asset), visiblePending == 0 else {
            throw MicroFailure.transactionBusy
        }
        rows[asset].lastOperation = lastOperation
    }

    public func injectStageFailure(at asset: Int?) throws {
        guard phase == .idle else { throw MicroFailure.transactionBusy }
        if let asset, !(0..<rows.count).contains(asset) { throw MicroFailure.invalidRequest }
        injectStageFailureAt = asset
    }

    @discardableResult
    public func begin(_ request: RescheduleRequest, journal: JournalMock) throws -> DurableReceipt? {
        guard phase == .idle else { throw MicroFailure.transactionBusy }
        if let (record, receipt) = journal.status(for: request.id) {
            guard record == request, visiblePending == request.count,
                  let recorded = journal.fingerprint(for: request.id),
                  publishedFingerprint == recorded else {
                throw MicroFailure.requestConflict
            }
            return receipt
        }
        guard journal.committedRecord() == nil, visiblePending == 0,
              request.count == rows.count, !request.id.isEmpty else { throw MicroFailure.invalidRequest }
        guard request.firstOperation > 0,
              UInt64(request.count - 1) <= UInt64.max - request.firstOperation else {
            throw MicroFailure.operationOverflow
        }
        guard request.time <= UInt64.max - 600 else { throw MicroFailure.timeOverflow }
        pendingRequest = request
        cursor = 0
        stagedFingerprint = checksumSeed
        phase = .validating
        return nil
    }

    // Makes at most `budget` model work units; no time/FPS claim is possible
    // without timing the real loop and memory allocation on an Apple device.
    public func tick(budget: Int, journal: JournalMock) throws -> Tick {
        guard budget > 0 else { throw MicroFailure.invalidRequest }
        guard phase != .recoveryRequired else { throw MicroFailure.recoveryRequired }
        guard phase != .idle, let request = pendingRequest else { throw MicroFailure.invalidRequest }
        if phase == .validating {
            var visited = 0
            while visited < budget && cursor < rows.count {
                let row = rows[cursor]
                let op = request.firstOperation + UInt64(cursor) // global preflight guarantees no overflow
                guard !row.active && op > row.lastOperation && wheel[cursor] == nil else {
                    phase = .idle
                    pendingRequest = nil
                    cursor = 0
                    throw MicroFailure.staleOrActiveAsset
                }
                visited += 1
                cursor += 1
            }
            if cursor == rows.count { cursor = 0; phase = .staging }
            return Tick(phase: phase, workItems: visited, receipt: nil)
        }
        if phase == .staging {
            var written = 0
            while written < budget && cursor < rows.count {
                if injectStageFailureAt == cursor {
                    phase = .recoveryRequired
                    throw MicroFailure.injectedFailure
                }
                let op = request.firstOperation + UInt64(cursor)
                let due = request.time + UInt64(cursor % 600 + 1)
                wheel[cursor] = Event(asset: cursor, operation: op, due: due)
                rows[cursor].active = true
                rows[cursor].lastOperation = op
                rows[cursor].scheduledTime = due
                appendRowHash(cursor, to: &stagedFingerprint)
                cursor += 1
                written += 1
            }
            if cursor == rows.count { phase = .awaitingJournal }
            return Tick(phase: phase, workItems: written, receipt: nil)
        }
        // Real durability, commit authority and instant publication are NOT
        // implemented here. Any ambiguous append result poisons the live owner.
        do {
            let receipt = try journal.append(request, stateFingerprint: stagedFingerprint)
            visiblePending = rows.count
            publishedFingerprint = stagedFingerprint
            pendingRequest = nil
            cursor = 0
            phase = .idle
            return Tick(phase: phase, workItems: 0, receipt: receipt)
        } catch {
            phase = .recoveryRequired
            throw error
        }
    }

    public func inspect() throws -> VisibleWorld {
        guard phase == .idle else { throw MicroFailure.readDuringTransaction }
        return currentView()
    }

    // A baseline identity is REQUIRED. Without a durable pre-transaction base,
    // synthesizing an empty world may silently erase business-owned state.
    // This mock only supports an *empty initial base*, verified by a caller-
    // supplied pre-transaction view. Real recovery requires a durable base.
    public static func recover(count: Int, from journal: JournalMock,
                               expectedBase: VisibleWorld) throws -> ChunkedTransactionWorld {
        let world = try ChunkedTransactionWorld(count: count)
        guard try world.inspect() == expectedBase else { throw MicroFailure.cannotRecover }
        guard let record = journal.committedRecord() else { return world }
        try world.begin(record, journal: JournalMock())
        let scratch = JournalMock()
        while world.phaseForDiagnostics != .idle {
            _ = try world.tick(budget: 1024, journal: scratch)
        }
        guard scratch.committedRecord() == record,
              journal.fingerprint(for: record.id) == scratch.fingerprint(for: record.id) else {
            throw MicroFailure.cannotRecover
        }
        return world
    }

}
