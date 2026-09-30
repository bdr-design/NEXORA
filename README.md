# NEXORA

## NXR-R002 — Executable aircraft lifecycle

Development version 0.0.2. This is a tested core candidate, not a playable game.
Read AGENTS.md's permanent source exclusion and current authorization first.

Implemented: R001 identity ownership and bounded timeline, plus AircraftStore
with owned identity/rows, create/start/complete/retire, revision and operation
contracts, independent serial-model tests, compiler misuse gates and isolated
invariant fail-stop checks. Five raw scale fixtures extend to 100,000 records.

Not implemented here: real routes/trips, scheduler, financial engines, save/load,
document storage, iOS app or map. No IPA. 20,000 fully functional assets is future
acceptance; 100,000 is an architectural goal, not certified gameplay capacity.

Current implementation branch: feature/r002-aircraft-lifecycle-20260930.
Exact current state and remaining stages: PROJECT_CONTINUITY.md.
Implementation evidence and limitations: Docs/Updates/NXR-R002.md.
Product requirements: Docs/REQUIREMENTS.md.

```sh
swift test -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -warnings-as-errors
bash Checks/verify.sh
bash Checks/verify-r002.sh
bash Checks/verify-failstop.sh
swift test --sanitize=thread -Xswiftc -warnings-as-errors
python3 Checks/review-r002.py
swift run -c release nexora-aircraft-check --json local-evidence/aircraft-samples.json
```

The crash gate intentionally launches four invalid test-fixture processes and
requires a failure plus the specific invariant marker. It is not a gameplay crash
report. Deep audits/exports and fixture controls are not the per-command hot path.
Local and Apple CI evidence are separate. Check the exact remote run before
assuming Apple success; local Linux timings do not certify iPhone performance.
