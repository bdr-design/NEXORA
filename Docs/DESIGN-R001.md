# R001: small ownership-first foundation

## Current path and ownership

`test/CLI owner -> EntitySpace.create/contains/destroy -> private identity columns`

EntitySpace is a noncopyable value (`~Copyable`). Mutable access is exclusive;
there is no public reference-sharing manager, global actor, or lock. It can be
moved to another owner but not used after that transfer. No reference to its
mutable columns escapes. Lifetime, validation and recycling exist in ONE module.
There is no domain storage to drift out of sync with it in this first milestone.
A future component store MUST receive a separately reviewed lifetime contract.

Each handle has a slot, generation and an immutable space stamp. The stamp is
one small reference object per space, not one object per asset. It prevents a
handle from another world with coincidentally equal slot/generation from being
accepted. The handle keeps the stamp alive even when its space is gone, preventing
address-reuse confusion. Only the owner can mint handles through a non-public
constructor. Hashable supports ephemeral Set membership, not replay order.

A free list is preallocated. A deleted slot increments its generation. At the
maximum generation it retires rather than wrapping. Capacity is bounded from
zero to one million slots and exhaustion throws without mutation. The upper
bound is a resource safety limit, not a scale/performance claim.

Create/contains/destroy touch a bounded number of entries. `checkInvariants()`
walks the free chain, checks every slot and counts live/retired entries; it is an
explicit allocating O(capacity) TEST/diagnostic operation, never a per-frame gate.

## What this deliberately does not solve

Handles are process-local, not stable persistence identities. Persistence/replay
needs a new logical-identity contract before a save format is implemented. There
is no business state, cross-domain transaction, simulation ordering, asynchronous
command runner, frame loop or selected-row compute pipeline. There is no claim
that concurrency is solved for systems not yet built.

## Diagnostic path

`CLI measured phase -> explicit TraceEvent -> uniquely owned Timeline -> export`

The ring is bounded, validates monotonic sequence and parent-before-child order,
and reports overwritten records. It has no static clock/counter, I/O, callback
or lock. Exports copy selected records into a separate array outside the timed
phase. A parent may be evicted; the ring does not claim a full replay history.

The timeline is only the initial measurement envelope. Apple signposts, frame
capture, persistence evidence and causal diagnosis are not implemented yet.

## Measured-first choices

Do not add parallel shared scratch buffers before a serial reference and a real
workload exist. The CLI measures creation/validation/destruction of identity
handles with 30 repetitions. These samples are not p99 certification, whole-game
performance, RAM usage, allocation counts or temperature measurements.

## Failure-path findings during construction

Local tests found that declaring a default reference-valued stamp before a
throwing/delegating noncopyable initializer produced a crash/failure in the tested
Debug/TSan configurations. Stamp initialization was moved into the validated
initializer after the capacity guard. Debug, Release and TSan were rerun. No
compiler-fault attribution or general workaround claim is made.

Swift Testing receiver-capture macro forms did not accept noncopyable store
receivers. Assertions now evaluate a Bool before passing it to the macro, keeping
noncopyable ownership intact. Negative compile tests independently verify that
forging handles, using a consumed owner and concurrent mutation are rejected.
