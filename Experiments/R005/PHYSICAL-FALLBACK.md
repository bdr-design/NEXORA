# One physical Apple Silicon fallback — NOT executed in this delivery

Use an operator-confirmed physical Apple Silicon Mac with Xcode16.4/Swift6.1.2
where possible. Record model,OS,kernel,Xcode,CPU,thermal conditions and whether
other workloads were present. Architecture arm64 alone does not prove physical.
No token is required for this public repository. Do not inspect excluded branches.

From a clean checkout of permitted source357dcd4e0658d84b821b3fcd9360b7fc29255225:

```sh
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
source_sha="$(git rev-parse HEAD)"
test "$source_sha" = 357dcd4e0658d84b821b3fcd9360b7fc29255225
git diff --exit-code
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
out="$(mktemp -d "${TMPDIR:-/tmp}/nexora-physical.XXXXXX")"
uname -a > "$out/environment.txt"
sw_vers >> "$out/environment.txt"
sysctl hw.model hw.memsize hw.ncpu >> "$out/environment.txt"
xcodebuild -version >> "$out/environment.txt"
python3 -B Experiments/R005/prepare.py "$out/source" > "$out/generated-hash.txt"
export NXR_GENERATED_SHA256="$(cat "$out/generated-hash.txt")"
swift build --package-path "$out/source" -c release --product nexora-financial-check -Xswiftc -g -Xswiftc -warnings-as-errors
bin="$(swift build --package-path "$out/source" -c release --show-bin-path)/nexora-financial-check"
"$bin" --extra-selftest > "$out/transcript.txt"
for run in 1 2 3; do
  "$bin" --v4-study "$out/v4-$run.ndjson" "$run" 30 "$source_sha"
done
"$bin" --event-study "$out/events.ndjson" "$source_sha"
python3 -B Experiments/R005/analyze.py --output "$out/verdict.json" "$out"/v4-{1,2,3}.ndjson
python3 -B Experiments/R005/analyze_events.py "$out/events.ndjson" "$out/event-summary.json"
python3 -B Experiments/R005/run_layout.py "$out/layout"
printf 'Physical execution output: %s\n' "$out"
```

This is one campaign comprising3 sequential processes,not unbounded retries.
Preserve failures and full source/generated identities. Attach operator confirmation
of physical hardware separately; software labels alone are not independent proof.
If positive counters are available,compare same-position peers but do not turn
instruction equality into proof of an external pause. Instruction growth>=1.5x
requires symbolized attribution; new data never reconstructs old missing counters.
Do not run this script against a dirty tree and label it as the pinned commit.
