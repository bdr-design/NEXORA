# D002 — bounded timed-trip coordinator

Date 2026-09-30. Implementation starts from verified R002, not excluded history.
Scope: one timed aircraft trip between numeric fixture airport identifiers. It is
not route planning, a geographic database, finance, persistence, or a UI loop.

## Owners and paths
TripSimulation is the sole noncopyable owner of AircraftStore, per-slot journey
rows and a fixed-capacity arrival heap. No mutable component escapes. Public input:
register-at-airport, depart-to-airport-with-duration, retire-ready-aircraft.
Read is one validated handle plus one row. No external caller can run the inner
AircraftStore independently. All entry points are synchronous, no callbacks/await.

InputToken is owner-stamped and increases only after accepted INPUT commands.
Automatic arrivals do not invalidate an already issued input token. Inner store
revisions are read at the exact serial call, never cached for background retries.
This prevents automatic tick progress from causing input revision conflicts, not
all possible UI/transport duplicate requests. Reusing a successful old input token
is rejected. A new token and same payload is a new input, not a durable replay.

## Time, ordering and boundedness
Time is UInt64 simulation seconds, not wall clock. Positive duration and checked
addition are required. Arrivals order by due time, then unique start-operation ID.
Heap is fixed storage: O(log pending) per push/pop, no growth or whole-world scan.
One pending event per active aircraft. Event limit is explicit; full queue fails
before starting the aircraft. At most 1,024 arrivals can commit in one advance.
This is a work-count bound, NOT a hard wall-time/frame guarantee.

advance(target,budget) returns reached time, committed completion prefix, next due
and stop reason (target reached, budget limited, blocked). Invalid target/budget
throws before mutation. The batch is intentionally prefix-committing, not atomic.
A rejected event remains at the heap head with its aircraft unchanged. Successful
earlier events stay committed and are explicitly returned, not thrown away.
Time only advances to committed event time; if due work remains it never jumps to
the requested target. When no due work remains it can reach target. The caller can
continue from the returned state. Repeating advance at the same target does not
repeat a completed arrival.

## Transaction boundaries
Input preflight checks all validation, time overflow and heap capacity before the
inner store mutation. That store call is the last expected failure. Fixed-row/heap
writes afterward cannot return expected failure. No destroy-to-undo workaround.
An arrival validates the paired row/event and inner active operation, then calls
inner complete, then updates airport/clears active plan, pops heap, moves clock and
appends the completion result. No I/O/log callback or await occurs in this commit.
Unexpected internal invariant corruption must stop; memory exhaustion/process
crash are not recovered by this in-memory contract. Persistence needs a new gate.

## Required invariants and review checks
1. Every live aircraft has exactly one matching journey row and vice versa.
2. Every active aircraft has one matching heap event; no ready aircraft has one.
3. Slot alone never authenticates a handle; inner store validates owner+generation.
4. Heap order and tie breaker are deterministic; operation IDs do not repeat.
5. clock never decreases, never overtakes unprocessed due work, and never wraps.
6. INPUT rejection preserves complete state; automatic prefix behavior is explicit.
7. Input sequence is independent of automatic arrivals; neither sequence wraps.
8. No queue growth, per-aircraft task/actor/lock, hot full scan, file I/O or JSON.
9. Completion result arrays are capped by requested budget, separate from hot rows.
10. All current identity and command tokens are process-local, not save identities.

## Tests before acceptance
Initial boundary and airport validation; foreign/stale token/handle; full event
queue leaves ready aircraft unchanged; duration and target overflow; deterministic
same-time tie ordering; budget1 and1024; invalid budget/target unchanged; exact
injected input failure; arrival failure before any or after some commits; failed
head retention and correct retry; inner revision exhaustion as an actual block;
input sequence exhaustion does not stop pending arrivals; read snapshots detached;
retiring/reusing slots; deep cross-store/heap invariants; independent sorted-list
model under varying budgets and commands; 1k/5k/20k/50k/100k narrow trip fixtures;
Debug/Release, external compiler boundaries, isolated corruption stops and TSan.

Package-only read-only AircraftStore evidence and new-space fixture construction
may be exposed to the coordinator's tests. Ordinary external clients still cannot
access them, and no normal command invokes test mutation fixtures. This access
change must be separately recorded and baseline misuse tests rerun.

Primary language facts: Swift package access is package-scoped; UInt64
addingReportingOverflow distinguishes rejected overflow from a valid sum.
https://docs.swift.org/swift-book/documentation/the-swift-programming-language/accesscontrol/
https://developer.apple.com/documentation/swift/uint64/addingreportingoverflow(_:)
