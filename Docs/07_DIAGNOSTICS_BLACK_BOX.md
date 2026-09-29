# Diagnostics / Black Box

Diagnostics is a foundation engine, not a late debug feature.

## Trace model
Each critical operation may carry:
- TraceID / ParentTraceID / CauseID
- domain/engine
- operation
- simulation time
- entity/company IDs where safe
- start/end/duration
- executor/thread/queue
- work/item count
- reads/writes summary
- transaction/commit/retry/conflict info
- allocation/memory counters where measured
- I/O bytes/time
- frame context
- thermal state
- result/error.

## Root-cause chain
The system must distinguish symptom from cause. Example: a map hitch caused by route-buffer rebuild caused by route-planner churn must identify the earliest causal stage, not simply blame rendering.

## Bounded overhead
Use ring buffers, counters, signposts, sampling and event capture. Persist detailed windows only around hitches, hangs, crashes, thermal transitions, save failures or explicit capture.

## Gate
A core engine without enough diagnostics to explain its latency/failure is incomplete.
