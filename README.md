# NEXORA

## NXR-R004 — verified in-memory finance core

NEXORA is a native Swift enterprise-simulation project under staged development.
Version 0.0.4 is a core package, not a playable iOS application. No IPA exists.

Implemented: uniquely owned identity/lifecycle stores, bounded diagnostic timeline,
deterministic timed arrivals, priced-arrival invoicing, partial/full collection,
capital and cash expenses, checked numeric limits and bounded history/pages.
Arrival finance is prepared before state commit; failures retain the current event
and return any completed prefix explicitly. This does not implement durable saves.

Final code 674c94e145f24dc6c4c9addaa5aa07d1c9d4a168 passed Apple run 36679204017:
142 named tests in each Debug/Release/TSan, 29 compiler misuse rejections, 12 isolated
fail-stop probes and 5 iOS library compiles. Artifacts/source hashes and scope are
in [the validation ledger](Docs/VALIDATION-R004.md). Parameter cases are not extra
named tests; compilation is not iPhone execution.

A 20k narrow financial fixture had a 20.050916 ms arrival-batch spike. No hard frame,
latency, RAM, zero-allocation, energy or thermal acceptance is claimed. 20k complete
assets and 100k architecture remain product targets, not achieved gameplay results.
No persistent identity/save/load, document/media storage, scheduled HR/maintenance/
delivery, treasury workflows, real route catalog, iOS UI or Metal map is complete.

Read [AGENTS.md](AGENTS.md), [continuity](PROJECT_CONTINUITY.md),
[requirements](Docs/REQUIREMENTS.md), and [the implemented financial boundary](Docs/Design/ATOMIC-FINANCE-R004.md)
before changing source. The permanent exclusion of retired sources remains binding.

### Local commands

```sh
swift test -Xswiftc -warnings-as-errors
swift test -c release -Xswiftc -warnings-as-errors
swift test --sanitize=thread -Xswiftc -warnings-as-errors
bash Checks/verify-r004.sh
bash Checks/verify-finance-failstop.sh
```

The CI workflow also runs earlier contracts, all library builds and raw fixtures.
Keep reports tied to their exact code commit; documentation-only publication may
advance the branch tip without changing the tested implementation.
