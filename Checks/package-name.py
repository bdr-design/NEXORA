#!/usr/bin/env python3
"""Read the compiler's actual package identity; do not guess from a directory name."""
import json,pathlib,sys
p=pathlib.Path(sys.argv[1])/'description.json'
description=json.loads(p.read_text())
identities=set()
for command in description.get('swiftCommands',{}).values():
    flags=command.get('otherArguments',[])
    if '-package-name' in flags:
        identities.add(flags[flags.index('-package-name')+1])
if len(identities)!=1:
    raise SystemExit(f'Expected one compiler package identity, found: {identities}')
print(identities.pop())
