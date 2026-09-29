# NEXORA

## Restart: NXR-R001 — 30 September 2026

The previous NXR-0001/0002/0003 implementation and unfinished repair work are
retired. This tree is newly written, not a patch, port, overlay, or continuation
of those implementations. Historical Git objects are retained only as a recovery
record. See `Docs/RESET-RECORD.md`.

**What exists:** a small Swift 6 package with a uniquely owned identity store,
a bounded diagnostic timeline, a lifecycle smoke executable, and tests.

**What does not exist:** a playable game, domain engines, scheduler, transaction
coordinator, persistence, iOS app, renderer, or completed diagnosis center.

The 20,000 fully functional asset acceptance target and 100,000 design target
remain requirements. Tests of 100,000 identity handles DO NOT satisfy them.

### Working entry points

- `AGENTS.md` — operational safeguards.
- `PROJECT_CONTINUITY.md` — current work and next bounded milestone.
- `Docs/REQUIREMENTS.md` — product requirements retained, not old technology.
- `Docs/DESIGN-R001.md` — ownership model, costs, limits and paths.
- `Docs/VALIDATION-R001.md` — exactly what has and has not been tested.
- `CHANGELOG.md` and `VERSION.json` — restart-scoped update identity.

### Commands

```sh
swift test -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -warnings-as-errors
bash Checks/verify.sh
swift test --sanitize=thread -Xswiftc -warnings-as-errors
swift run -c release nexora-check --json local-evidence/identity-smoke.json
```

`Checks/verify.sh` creates `local-evidence/`. Raw timing reports measure identity
creation, validation and destruction only. They are not frame-time benchmarks.
