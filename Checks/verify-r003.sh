#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -warnings-as-errors
bin="$(swift build -c release --show-bin-path)"
mkdir -p local-evidence/r003-compiler
swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" -c Checks/trip_client.swift -o local-evidence/r003-compiler/client.o
for name in trip_consume trip_concurrent trip_private trip_token trip_fixture trip_audit trip_clock; do
  log="local-evidence/r003-compiler/$name.txt"
  if swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" -c "Checks/$name.swift" -o "local-evidence/r003-compiler/$name.o" > "$log" 2>&1; then
    echo "Invalid external trip client compiled: $name" >&2; exit 1
  fi
  if grep -q 'no such module' "$log"; then echo "Missing module, not contract rejection" >&2; exit 1; fi
  case "$name" in
    trip_consume) pattern='error:.*(used after consume|consumed more than once)' ;;
    trip_concurrent) pattern='error:.*(data races|concurrent|noncopyable)' ;;
    trip_clock) pattern='error:.*(cannot assign|inaccessible|setter)' ;;
    *) pattern='error:.*(inaccessible|protection level|extra arguments|incorrect argument)' ;;
  esac
  grep -E "$pattern" "$log" >/dev/null || { cat "$log"; exit 1; }
  echo "PASS required rejection: $name"
done
