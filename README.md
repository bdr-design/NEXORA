# NEXORA

## NXR-R003 — bounded timed-trip core

Development 0.0.3. No app build, IPA or playable iOS game yet.
Read AGENTS.md's source exclusion and authorization before work.

Implemented: uniquely owned aircraft records and identity; timed trips between
numeric fixture airports; deterministic bounded arrival heap; explicit prefix
progress, failed-event retention and independent manual-input sequence. Input
errors preserve compound state, and corrupt internal invariants fail-stop.

Local Debug/Release: 86 named tests. 18 compiler misuse rejections, 8 isolated
corruption processes, two independent reference models and narrow scale fixtures.
See Docs/Updates/NXR-R003.md for actual results and the incomplete local TSan
invocation. Apple gates must be checked on the exact submitted source; never
infer success from this README or prior R002 tests.

Not implemented: real route catalog/planning, finance, payroll/maintenance/delivery,
transactional save/load, document storage, iOS UI/map or device diagnostics.
20k full-feature acceptance and 100k architectural scale remain unproven goals.

```sh
swift test -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -warnings-as-errors
bash Checks/verify.sh
bash Checks/verify-r002.sh
bash Checks/verify-r003.sh
bash Checks/verify-failstop.sh
bash Checks/verify-trip-failstop.sh
python3 Checks/review-r002.py
python3 Checks/review-r003.py
swift test --sanitize=thread -Xswiftc -warnings-as-errors
swift run -c release nexora-trip-check --json local-evidence/trip-samples.json
```

Deep audits and CLI exports allocate outside normal simulation work. The 256-event
benchmark budget and 1,024 API maximum are event-count limits, not FPS guarantees.
PROJECT_CONTINUITY.md records the exact current stage and remaining work.
