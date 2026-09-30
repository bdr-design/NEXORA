# R004 audit — final verified checkpoint

Date: 2026-09-30 / Asia/Riyadh. Repository bdr-design/NEXORA only.
Branch: review/r004-comprehensive-audit-20260930.
Reviewed base: 96db1cebc38798a81f0315ec16e20136de7ce8da.
Final tested review code: 0706447fceaca594d7dd897d98fe406dd926e352.
Final tested tree: 27a428eb9b2df227706ff9165f8c72cba748aa62, 110 files.
This evidence-only publication does not modify source, tests, checks or workflows.
Read AGENTS permanent exclusion; no excluded implementation or destructive action.

Apple run 36697715699 / job 109829567389 completed SUCCESS at 09:46:33Z.
Artifact 11089180650, SHA256:
4fe2a49c41c14331e8706d706888129c512ec1837dec5077c6e194aeecb7723d.
Debug/Release/TSan each 142 named tests / 11 suites PASS. Python 43 tests PASS.
29 compiler rejections, five valid clients, 12 invariant fail-stops PASS.
Rebuilt all source bytes/modes; source tree matches the tested commit exactly.
Strict reanalysis of the original 372600 measured batches is byte-identical to the
pinned original report. This is reanalysis, not new performance measurements.

Supersedes pending Apple wording in AUDIT and AUDIT-ERRNO daily entries. Earlier
41-test commit/run stays historical; final suite includes zero-errno failure tests.
Seven invalid/duplicate evidence cases are fixed. No newly established economic
or atomicity defect, no Swift changes, no R005, no main merge, no device acceptance.
Two local verifier log-parsing assertions were corrected and preserved as verifier
failures, not recast as Swift test failures. See Docs/VALIDATION-R004-AUDIT.md.
