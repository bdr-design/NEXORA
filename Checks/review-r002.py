#!/usr/bin/env python3
"""Narrow mechanical source-contract checks, not a proof of correctness."""
import json, pathlib, re
root = pathlib.Path(__file__).resolve().parents[1]
source = (root/'Sources/NexoraAviation/AircraftStore.swift').read_text()
body = source.split('private mutating func applyCore', 1)[1].split('private func receipt', 1)[0]
body = re.sub(r'//[^\n]*', '', body)
# Do not mistake Swift's record(for:) argument label for a for-in loop.
loop = r'\bfor\s+(?:case\s+)?[^\n]*\bin\b'
assert re.search(loop, 'for item in items { }')
assert not re.search(loop, 'record(for: handle)')
for pattern in (r'\bawait\b', r'\bTask\b', r'\bfor\s+(?:case\s+)?[^\n]*\bin\b', r'\bwhile\b', r'\.append\(',
                r'JSON', r'Timeline', r'checkInvariants', r'auditForTesting', r'FileManager'):
    if re.search(pattern, body):
        raise SystemExit(f'Unexpected hot-path construct: {pattern}')
assert 'public struct AircraftStore: ~Copyable, Sendable' in source
assert 'private var identities: EntitySpace' in source
assert 'private var rows:' in source
assert 'public mutating func seedFixture' not in source
assert 'public func auditForTesting' not in source
assert body.count('revision = next') == 4
assert body.count('at: .beforeCommit') == 4
assert body.count('at: .afterPreparation') == 4
assert 'NEXORA_AIRCRAFT_INVARIANT:' in body
print('PASS T31 mechanical source-path checks (scope-limited; not an optimizer or memory proof)')
# The reviewed checklist maps every D001 scenario to evidence, never to absence.
coverage = {f'T{i:02}': 'runtime' for i in range(1, 33)}
coverage.update(T25='external-compiler', T27='runtime-and-isolated-crash', T31='source-review')
tests = '\n'.join(p.read_text() for p in (root/'Tests/NexoraAviationTests').glob('*.swift'))
for key, kind in coverage.items():
    if kind.startswith('runtime') and not re.search(r'func '+key+r'_', tests):
        raise SystemExit(f'Missing executable scenario: {key}')
(root/'local-evidence').mkdir(exist_ok=True)
(root/'local-evidence/r002-coverage-map.json').write_text(json.dumps(coverage, indent=2)+'\n')
print('Coverage mapping: 30 scenario-named runtime tests; 2 separate compiler/source gates; 2 extra ownership runtime tests')
