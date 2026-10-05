# NEXORA — current checkpoint / نقطة الاستئناف

Updated 2026-10-05. Only bdr-design/NEXORA, branch diagnostic/r005-design-1m-20260930.
Read AGENTS.md first, then recheck live HEAD before any modification. Main remains
38ce39cf9322f47e4def5f6eddb425c5a66ea7f9. All denied branches remain forbidden.

Latest tested candidate source bbe26ef771c78a6ebd7aa5bdc198696303fa066f;
tree b5a2573c6b55438769661fc00e65079d82eb5473. Apple run 37315706838 SUCCESS,
artifact 11347843021 ZIP SHA-256
c1134d5e6c4c6eedb4b7d80c2153482d304771193b971a7f763fb99d4b3e8644.
SUCCESS is bounded diagnostics, not C acceptance. S ratio=1.8873046206229083;
advance p99=1172542 ns (732 samples). H ratio=1.9071515315977814.
S/H idle and saving allocations=0; Debug/Release transport/100k restore, known SHA,
and real truncated K3 with exact 1M recovery passed. Scratch costs S 97.3 MB capacity /
98.0 MB physical delta; H 103.3 / 104.1 MB. No device memory acceptance claimed.

Owner said «حله!» after earlier alternatives. Bounded profiling and one copy/write
candidate completed; performance remains unaccepted. A/B reuse is revalidated from
36875130222/fa9c446, not freshly measured. Original run 36875130222 stays FAILED.
Raw phase/micro JSON, artifact identities and every failure retained in
Experiments/R005Swift/review-20261005.json and failures.json.

Next: one final bounded micro enforcing background writer QoS; estimates/ownership
are in Docs/Daily/2026-10-05-R005-EXECUTION.md. If overhead remains, stop and give
2–3 alternatives with measured costs. Do not repeat full campaigns; no new full
100-save attempt has been made. C can close only with genuine 1M/100-save PASS,
K1–K10 Debug/Release/TSan and paired allocation gates, explicitly on S or H.
All thresholds and acceptance formula stay unchanged, including overhead <=1.10.
No production change, main merge, IPA or iPhone acceptance. B manifest torn-tail
resume-write source-review risk must be resolved before production.

This file is deliberately short for reliable chat handoffs. The previous complete
continuity is preserved verbatim at Docs/History/2026-10-05-R005-CONTINUITY-HISTORY.md,
SHA-256 0f4611589718941d2e4594226a4aa06d29fdbf6e7e7c465e25c48cb79ad1db56.
Daily review/execution and evidence remain the detailed sources. Chat app connection
failure cause is unverified; do not promise background work or repeat uncertain writes.
