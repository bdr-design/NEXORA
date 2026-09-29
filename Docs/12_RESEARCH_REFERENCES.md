# Research References

Primary engineering sources guide principles; NEXORA benchmarks make final decisions.

## Apple
- Metal Best Practices Guide — https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/
- Improving game graphics performance/settings — https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings
- Analyzing Metal app performance — https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app/
- MetricKit performance monitoring — https://developer.apple.com/documentation/metrickit/monitoring-app-performance-with-metrickit
- ProcessInfo thermal state — https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum
- OSSignposter — https://developer.apple.com/documentation/os/ossignposter
- Swift performance / contiguous-memory APIs — current Apple Swift performance sessions/documentation.

Engineering conclusions: use measured CPU/GPU/frame evidence, keep render workload sustainable, treat thermal/power as first-class, and avoid unnecessary allocations/work in hot paths.

## SQLite
- WAL — https://www.sqlite.org/wal.html
Conclusion: WAL is an evidence-backed candidate for incremental local persistence, but checkpoints must be explicitly controlled and benchmarked.

## Large simulation engineering
- Factorio FFF #82 — https://www.factorio.com/blog/post/fff-82
- Factorio FFF #204 — https://www.factorio.com/blog/post/fff-204
- Factorio FFF #421 — https://www.factorio.com/blog/post/fff-421
- Factorio FFF #121 — https://www.factorio.com/blog/post/fff-121

Lessons used only as public engineering inspiration: profile first, improve locality, sleep/avoid idle work, group/bucket work, cache with correct invalidation. No code or proprietary implementation is copied.

## Domain architecture
- Microsoft tactical DDD — https://learn.microsoft.com/en-us/azure/architecture/microservices/model/tactical-domain-driven-design
- Event-driven architecture — https://learn.microsoft.com/en-us/azure/architecture/guide/architecture-styles/event-driven

NEXORA applies bounded domains/events inside a modular monolith, not mobile network microservices.

## Product-depth references only
- Airline Manager 4 — https://store.steampowered.com/app/1641650
- Transport Fever 2 simulation/industries documentation — https://www.transportfever2.com/wiki/

These inform desired depth (maintenance, operational constraints, supply chains, demand) only. Their technical internals are not assumed or reused.
