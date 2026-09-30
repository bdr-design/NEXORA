#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ulimit -c 0 || true
for config in debug release; do
  swift build -c "$config" -Xswiftc -enable-testing -Xswiftc -warnings-as-errors
  bin="$(swift build -c "$config" --show-bin-path)"
  package="$(python3 Checks/package-name.py "$bin")"
  destination="local-evidence/finance-failstop-$config"
  mkdir -p "$destination"
  objects=()
  while IFS= read -r file; do objects+=("$file"); done < <(find "$bin/NexoraFinance.build" "$bin/NexoraIdentity.build" -name '*.o' -type f | sort)
  swiftc -swift-version 6 -package-name "$package" -I "$bin/Modules" "${objects[@]}" Checks/finance_failure_probe.swift -o "$destination/probe"
  python3 - "$destination" <<'PY'
import pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1])
for case in ('stale','foreign'):
    result=subprocess.run([str(root/'probe'),case],capture_output=True,text=True)
    log=result.stdout+result.stderr
    (root/(case+'.txt')).write_text(log)
    if result.returncode==0 or 'NEXORA_FINANCE_INVARIANT:' not in log or 'PROBE_FAILED:' in log:
        raise SystemExit(f'FAIL finance corruption contract {case}: {result.returncode}\n{log}')
    print(f'PASS finance fail-stop {root.name}/{case}: exit={result.returncode}, invariant marker present')
PY
done
