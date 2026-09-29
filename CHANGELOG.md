# NEXORA changelog — fresh restart line

## NXR-R001 — 2026-09-30 — Fresh ownership foundation

The owner authorized replacement of the complete active tree. Retired
NXR-0001/2/3 and unfinished repair code are not carried forward.

Added newly written identity ownership, bounded trace timeline, lifecycle CLI,
Swift 6 tests, compiler misuse checks, and restart-specific requirements and
handoff records. Local initializer and assertion compatibility failures were
found and corrected before remote submission.

This update is non-production scaffolding. There is no game runtime, save format,
financial engine, scheduler, renderer, IPA or claimed full-game scale result.
Historical Git records remain separately recoverable; see Docs/RESET-RECORD.md.

### Verified initial scaffold
Apple CI run `36646039605` passed Debug/Release/TSan (19 named tests each),
3 compiler misuse rejections, both iOS library compile gates, and five identity
smoke scales. Verified code: `c45d24e0445219fc0db4df5efd0e920b5e129c16`.
No old-source benchmark or acceptance result was reused.
