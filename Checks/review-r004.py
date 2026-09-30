#!/usr/bin/env python3
"""Narrow textual transaction guards; executable tests provide separate evidence."""
import pathlib,re
root=pathlib.Path(__file__).resolve().parents[1]
ledger=(root/'Sources/NexoraFinance/FinanceStore.swift').read_text()
world=(root/'Sources/NexoraSimulation/TripSimulation.swift').read_text()
prepare=ledger.split('package func prepare(',1)[1].split('/// The enclosing owner',1)[0]
commit=ledger.split('package mutating func commit(',1)[1].split('/// Allocating O(',1)[0]
advance=world.split('private mutating func advanceCore(',1)[1].split('private func progress',1)[0]
manual=world.split('private mutating func applyFinanceCore(',1)[1].split('private func nextInput',1)[0]
for text in (prepare,commit,advance,manual):
    text=re.sub(r'//[^\n]*','',text)
    for pattern in (r'\bawait\b',r'\bTask\b',r'FileManager',r'JSON',r'Timeline',r'checkInvariants',r'auditForTesting'):
        assert not re.search(pattern,text),pattern
for text in (prepare,commit,manual):
    assert not re.search(r'\bfor\s+[^\n]*\bin\b|\bwhile\b',re.sub(r'//[^\n]*','',text))
assert 'PreparedFinance: ~Copyable' in ledger
assert 'FinanceStore: ~Copyable' in ledger
assert 'private var finance: FinanceStore' in world
assert 'origins.reserveCapacity(testingLimits.invoices)' in ledger
assert 'origins[origin] == nil' in prepare
assert 'creditResult.partialValue != Int64.min' in prepare
assert 'ledger.apply' not in advance
p=advance.index('preparedFinance = try finance.prepare')
a=advance.index('result = try aircraft.apply(.complete')
f=advance.index('invoice = finance.commit(consume plan).invoice')
j=advance.index('journeys[Int(trip.handle.slot)] =')
assert p < a < f < j
assert '.blocked(.finance(error))' in advance
assert '.blocked(.aircraft(error))' in advance
assert 'try ' not in re.sub(r'//[^\n]*','',advance[f:])
assert manual.index('finance.prepare') < manual.index('finance.commit') < manual.index('inputSequence = next')
assert 'try ' not in manual[manual.index('finance.commit'):]
assert '.append(' not in prepare and '.append(' not in commit
print('PASS R004 transaction source guards; not formal atomicity/durability or allocation proof')
