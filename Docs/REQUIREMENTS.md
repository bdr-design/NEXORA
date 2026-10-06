# Product requirements retained for the fresh implementation

Name: **NEXORA**, without a subtitle. Repository: `bdr-design/NEXORA` only.

Priority: sustained smoothness and low unnecessary power/thermal load, then deep
realistic business simulation and long-term extension. Initial real-device target
is the owner's iPhone 17 Pro Max; CI/Mac measurements are not device certification.

Permanent owner rules, reaffirmed 2026-10-07 (Asia/Riyadh): smoothness is an
acceptance requirement for every addition, not a later polish task. Every
player-facing department, option, button and company must have a complete,
realistic functional lifecycle before it is added. No decorative companies or
inert controls. The supplied GlobalHoldings repository contributes product ideas
only; its code and implementation methods are forbidden, including rewritten
copies. See `PRODUCT-RULES.md` and `../AGENTS.md` for the binding contract.

The player operates holdings, subsidiaries, business units and facilities across
multiple industries. Product scope includes aviation, sea and road transport,
banking, energy, retail, manufacturing and logistics. Future car sales and
manufacturing, dairy products, phone retail and phone manufacturing must fit
without hard-coding a closed company-type list into the core.

Reusable business responsibilities may include sales, procurement, inventory,
production/BOM/recipes, finance, treasury, HR/payroll, maintenance, facilities,
quality, contracts, compliance, research, warranty and distribution. These are
requirements, NOT instructions to build twenty speculative modules immediately.

Finance must support incoming/outgoing transfers, cheques, cheque images,
transfer proofs, receipts, invoices, searchable history and linked business
documents. Full-size media belongs outside hot simulation state, with lazy
retrieval and integrity references. No financial implementation is inherited.

Rendering and economic simulation are separate. Map motion, filtering and large
lists must not trigger full-world mutation/scanning on the UI path. A future
thermal governor may reduce presentation work, not silently change economic
outcomes or discard scheduled business events. An overloaded accelerated clock
must honestly report actual progress rather than corrupt simulation.

The current scale decision supersedes the earlier 20,000 acceptance / 100,000
architecture figures: design for 1M assets with capacity headroom to 2M. After
explicit layout-specific C closure and the owner's production merge approval,
physical iPhone 17 Pro Max acceptance proceeds through 100k, 250k and 1M.
Acceptance still requires full-feature assets: operations, invoices, revenue,
payroll, maintenance, delivery, persistence and active UI/map use. R005 fixtures
and Apple CI probes do not prove this gameplay or device acceptance. Native Swift
and a Metal map remain the selected platform direction, subject to measurement.

Diagnostics starts with the foundation and grows into bounded causal tracing:
operation/owner/cause, work counts, stage latency, queue state, failures, saves,
UI/frame context, memory and thermal observations. No automatic root-cause
certainty may be claimed from correlation alone.

The first end-to-end gameplay milestone should be a THIN aviation slice, not an
entire generic enterprise platform. Reuse is extracted from validated needs of a
second industry. Every published build must identify its source, tests and
artifact digest. User rules on careful work and chat handoff remain in force.
