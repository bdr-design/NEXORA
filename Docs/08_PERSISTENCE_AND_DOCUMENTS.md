# Persistence & Documents

## Persistence direction
Structured incremental storage; SQLite/WAL is the initial evidence-backed candidate subject to NEXORA benchmarks.

Requirements:
- bounded transactions;
- no giant full-world JSON save;
- no synchronous save/checkpoint on main/render path;
- explicit checkpoint scheduling;
- recovery journal;
- schema/version migrations;
- crash/interruption tests;
- deterministic integrity checks.

World/catalog static data is separated from mutable save state.

## Documents
Functional requirements include incoming/outgoing transfers, cheque records/images, transfer proof images, receipts, contracts and future LC/guarantee documents.

Large media bytes are stored separately from hot simulation state. Transaction/document metadata stores immutable IDs, content hash, type, date, company/account/party links, audit state and Trace/Transaction links. UI uses thumbnails/lazy loading.

Loss/corruption of a media file must not corrupt authoritative financial balances; integrity status is surfaced and diagnosable.
