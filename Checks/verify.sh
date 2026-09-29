#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release -Xswiftc -warnings-as-errors
bin="$(swift build -c release --show-bin-path)"
mkdir -p local-evidence/compiler
# First prove that an ordinary public API client compiles with these flags.
swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" -c Checks/client.swift -o local-evidence/compiler/client.o
for test in copy_owner forge_handle concurrent_mutation; do
    if swiftc -swift-version 6 -warnings-as-errors -I "$bin/Modules" -c "Checks/$test.swift" -o "local-evidence/compiler/$test.o" > "local-evidence/compiler/$test.txt" 2>&1; then
        echo "ERROR: invalid client compiled: $test" >&2
        exit 1
    fi
    if grep -q 'no such module' "local-evidence/compiler/$test.txt"; then
        echo "ERROR: $test failed due to missing module, not its intended contract" >&2
        exit 1
    fi
    case "$test" in
        copy_owner) grep -Eq 'used after consume|consumed more than once|noncopyable' "local-evidence/compiler/$test.txt" ;;
        forge_handle) grep -Eq 'inaccessible|protection level' "local-evidence/compiler/$test.txt" ;;
        concurrent_mutation) grep -Eq 'data races|concurrently|concurrent|noncopyable' "local-evidence/compiler/$test.txt" ;;
    esac
    echo "PASS (compiler rejected): $test"
done
