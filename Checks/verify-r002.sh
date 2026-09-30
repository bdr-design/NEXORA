#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -warnings-as-errors
bin="$(swift build -c release --show-bin-path)"
mkdir -p local-evidence/r002-compiler
swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" -c Checks/aircraft_client.swift -o local-evidence/r002-compiler/client.o
for name in aircraft_consume aircraft_concurrent aircraft_private aircraft_token aircraft_fixture aircraft_audit identity_package aircraft_readonly; do
  log="local-evidence/r002-compiler/$name.txt"
  if swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" -c "Checks/$name.swift" -o "local-evidence/r002-compiler/$name.o" > "$log" 2>&1; then
    echo "Invalid external client compiled: $name" >&2; exit 1
  fi
  if grep -q 'no such module' "$log"; then echo "Module loading failure, not contract rejection" >&2; exit 1; fi
  case "$name" in
    aircraft_consume) pattern='error:.*(used after consume|consumed more than once)' ;;
    aircraft_concurrent) pattern='error:.*(data races|concurrent|noncopyable)' ;;
    aircraft_readonly) pattern='error:.*(cannot assign|let constant|get-only)' ;;
    *) pattern='error:.*(inaccessible|protection level|extra arguments|incorrect argument)' ;;
  esac
  grep -E "$pattern" "$log" >/dev/null || { cat "$log"; exit 1; }
  echo "PASS required rejection: $name"
done
