# Retained preparation failures

1. First disposable-source generator rejected a non-unique advance anchor (baseline and measured fixture). The shell continued to build the partially generated copy; that build is NOT accepted as instrumentation evidence. Both directory and log retained. Generator now selects only the measured-fixture region; subsequent commands use set -euo pipefail. No production file was changed.

2. Initial portable C probe build was rejected by -Werror for misleading indentation. Braces/line structure corrected; the warning gate stays enabled. No measurement was produced by that failed build.

3. Combined local Swift command exceeded its tool timeout during Debug tests; incomplete log retained as core-debug.txt. Standalone reruns are separate evidence, not a reclassification.

4. First Release compile exceeded the45s tool cap; its log is retained. Streaming exec is unavailable; no test success inferred. Standalone Release rerun follows.

5. A combined Release/Python command exceeded the tool timeout in the pre-existing Python suite. Release itself finished successfully (142/11, 6.025s), but the partial Python log is not a passing run. Its gate is retained for CI.
