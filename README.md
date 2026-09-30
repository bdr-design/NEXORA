# NEXORA

## NXR-R003 — verified bounded timed-trip core

Development 0.0.3. No app build, IPA or playable iOS game yet.
Read AGENTS.md's source exclusion and current execution authorization first.

Implemented: uniquely owned aircraft records and identity; timed trips between
numeric fixture airports; deterministic bounded arrival heap; explicit prefix
progress, failed-event retention and independent manual-input sequence. Input
errors preserve compound state, and corrupt internal invariants fail-stop.

Apple CI run36655778966 passed on code50a9fb82db7ea13f636b5c4b3e4f104d8bb7b113:
86 named tests each Debug/Release/TSan, 18 compiler misuse rejections, 8 isolated
corruption processes, 4 iOS library compiles, independent models and narrow scale
fixtures. The evidence archive and complete 67-file source export were downloaded
and their digests and exact full Git source tree independently checked.
Read Docs/VALIDATION-R003.md for exact identities, measurements and limitations.

Not implemented: real route catalog/planning, finance, payroll/maintenance/delivery,
transactional save/load, document storage, iOS UI/map or device diagnostics.
20k full-feature acceptance and 100k architectural scale remain unproven goals.
This is a verified core milestone, not proof of complete gameplay or no defects.

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

The earlier incomplete local sanitizer invocation is recorded, not represented as
passed by the later Apple success. Deep audits/exports allocate outside normal
simulation work. Benchmark budget256 and API maximum1024 are event-count bounds,
not FPS/heat/energy guarantees. PROJECT_CONTINUITY.md is the current handoff point.
