#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0 || true
for config in debug release; do
  # A preceding ordinary release build can replace the testable module.
  # Rebuild explicitly for this internal-fixture harness in each configuration.
  swift build -c "$config" -Xswiftc -enable-testing -Xswiftc -warnings-as-errors
  bin="$(swift build -c "$config" --show-bin-path)"
  destination="local-evidence/failstop-$config"
  mkdir -p "$destination"
  objects=()
  while IFS= read -r file; do objects+=("$file"); done < <(find "$bin/NexoraAviation.build" "$bin/NexoraIdentity.build" -name '*.o' -type f | sort)
  swiftc -swift-version 6 -I "$bin/Modules" "${objects[@]}" Checks/aircraft_failure_probe.swift -o "$destination/probe"
  python3 - "$destination" <<'PY'
import pathlib, subprocess, sys
root=pathlib.Path(sys.argv[1])
for case in ('missing-row','occupied-slot'):
    result=subprocess.run([str(root/'probe'),case],capture_output=True,text=True)
    log=result.stdout+result.stderr
    (root/(case+'.txt')).write_text(log)
    if result.returncode==0 or 'NEXORA_AIRCRAFT_INVARIANT:' not in log or 'PROBE_FAILED:' in log:
        raise SystemExit(f'FAIL crash contract {case}: status={result.returncode}\n{log}')
    print(f'PASS fail-stop {root.name}/{case}: exit={result.returncode}, invariant marker present')
PY
done
