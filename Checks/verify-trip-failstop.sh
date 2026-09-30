#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0 || true
for config in debug release; do
  swift build -c "$config" -Xswiftc -enable-testing -Xswiftc -warnings-as-errors
  bin="$(swift build -c "$config" --show-bin-path)"
  destination="local-evidence/trip-failstop-$config"
  mkdir -p "$destination"
  objects=()
  while IFS= read -r file; do objects+=("$file"); done < <(find "$bin/NexoraSimulation.build" "$bin/NexoraAviation.build" "$bin/NexoraIdentity.build" "$bin/NexoraFinance.build" -name '*.o' -type f | sort)
  swiftc -swift-version 6 -I "$bin/Modules" "${objects[@]}" Checks/trip_failure_probe.swift -o "$destination/probe"
  python3 - "$destination" <<'PY'
import pathlib, subprocess, sys
root=pathlib.Path(sys.argv[1])
for case in ('read','advance'):
    result=subprocess.run([str(root/'probe'),case],capture_output=True,text=True)
    log=result.stdout+result.stderr
    (root/(case+'.txt')).write_text(log)
    if result.returncode==0 or 'NEXORA_TRIP_INVARIANT:' not in log or 'PROBE_FAILED:' in log:
        raise SystemExit(f'FAIL trip crash contract {case}: status={result.returncode}\n{log}')
    print(f'PASS trip fail-stop {root.name}/{case}: exit={result.returncode}, invariant marker present')
PY
done
