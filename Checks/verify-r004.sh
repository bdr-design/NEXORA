#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -warnings-as-errors
bin="$(swift build -c release --show-bin-path)"
package="$(python3 Checks/package-name.py "$bin")"
mkdir -p local-evidence/r004-compiler
swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" -c Checks/finance_client.swift -o local-evidence/r004-compiler/client.o
swiftc -swift-version 6 -warnings-as-errors -package-name "$package" -I "$bin/Modules" -c Checks/finance_plan_client.swift -o local-evidence/r004-compiler/plan-client.o
for name in finance_consume finance_concurrent finance_private finance_invoice finance_token finance_prepare finance_audit finance_fixture finance_currency finance_plan_consume finance_plan_forge; do
  log="local-evidence/r004-compiler/$name.txt"
  compiler_flags=(-swift-version 6 -warnings-as-errors)
  case "$name" in finance_plan_*) compiler_flags+=(-package-name "$package") ;; esac
  if swiftc "${compiler_flags[@]}" -I "$bin/Modules" -c "Checks/$name.swift" -o "local-evidence/r004-compiler/$name.o" > "$log" 2>&1; then
    echo "Invalid finance client compiled: $name" >&2; exit 1
  fi
  if grep -q 'no such module' "$log"; then echo "Missing module, not contract rejection" >&2; exit 1; fi
  case "$name" in
    finance_consume|finance_plan_consume) pattern='error:.*(used after consume|consumed more than once)' ;;
    finance_concurrent) pattern='error:.*(data races|concurrent|noncopyable)' ;;
    finance_currency) pattern='error:.*(cannot assign|let constant|get-only)' ;;
    *) pattern='error:.*(inaccessible|protection level|extra argument|incorrect argument)' ;;
  esac
  grep -E "$pattern" "$log" >/dev/null || { cat "$log"; exit 1; }
  echo "PASS required rejection: $name"
done
