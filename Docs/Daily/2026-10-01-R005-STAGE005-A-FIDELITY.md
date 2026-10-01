# R005 Stage A fidelity correction — 2026-10-01

Repository: bdr-design/NEXORA only.
Pre-correction branch HEAD: 717093a8a5ce71bb08de8f5a4fccc310e1223a90.
main remains 38ce39cf9322f47e4def5f6eddb425c5a66ea7f9.

Review against the owner-supplied proof-closure directive found a real fidelity
defect in the Stage A S benchmark. S still had the earlier thin asset columns and
omitted contract/changeEpoch/entity/policy/origin. The prior green Apple run
36834086456 is preserved but is no longer accepted for the final A design choice.

Correction:
- add five UInt32 columns to SwiftWorld so S has the required 65 asset bytes;
- initialize contract=i/16, entity=i%32 and origin from the current airport;
- use contract for group lookup and write changeEpoch on completion;
- extend the typed full checkpoint/restore by the same five fields;
- record origin on HybridWorld schedule for semantic parity;
- preserve every existing threshold and health gate unchanged.

No production source or test is changed. A must pass again before B/C acceptance.
