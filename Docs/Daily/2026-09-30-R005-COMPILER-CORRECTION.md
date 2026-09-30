# R005 prototype compiler boundary correction

Date:2026-09-30/Asia-Riyadh. Active branch diagnostic/r005-design-1m-20260930.
First candidate b097ae64ab539c60fc82f08ec4c60a79cb65c124, run36754290347,
layout job110020462644 failed at compilation before any layout case ran on Apple.
The Python wrapper captured compiler stderr but failed to emit/preserve it. That
observability omission is fixed here; all accepted-build commands/stdout/stderr
are now retained. No result from the failed Apple layout job is accepted.

The same platform C file built in the generated Swift check executable, whose
Debug/Release transcript gates passed. Unlike that build, the layout wrapper
requested a strict POSIX feature namespace while calling Darwin-only interfaces.
This correction selects the platform's appropriate feature namespace: Linux keeps
_POSIX_C_SOURCE=200809L; Darwin does not request POSIX-only declarations.
The exact original Darwin compile is repeated as a labeled compatibility preflight
and its full outcome preserved before the corrected build. Its stderr must be
inspected before claiming a particular missing symbol caused the first failure.
-Wall,-Wextra,-Werror,ASan/UBSan and every case/budget gate remain enabled.
The storage layout and event kernel, V4 capture and production sources are unchanged.
No second bounded performance campaign is requested by this correction commit.
The first campaign, if complete, belongs to its original source/runner, not this
new commit. Subsequent layout/contract checks are separately identified.
