# NEXORA Project Structure

- `Apps/iOS/` — iOS application shell/composition root.
- `Core/StateKernel/` — authoritative state ownership/commit contracts.
- `Core/SimulationClock/` — simulation time.
- `Core/Scheduler/` — due-event scheduling.
- `Core/JobSystem/` — bounded background computation.
- `Platform/Persistence/` — incremental persistence/recovery.
- `Platform/Diagnostics/` — black-box/root-cause tracing.
- `Platform/Performance/` — performance/thermal governance.
- `Platform/Rendering/` — Metal map/rendering, LOD, clustering.
- `Enterprise/` — reusable business capabilities.
- `Industries/` — industry-specific extensions only.
- `World/` — geography, currencies, markets and world economy.
- `UI/` — read models/screens/query boundaries.
- `Tests/` — correctness, persistence, scale, performance, thermal, determinism.
- `Docs/` — architecture, ADRs, Daily, Updates and Releases.
