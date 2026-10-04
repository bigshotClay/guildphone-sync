#!/usr/bin/env python3
"""Fail if guildphone-sync.py imports anything that is not standard library.

The README and the portal both say "Python 3 and nothing else - no packages
to install". A single `pip install` away from that being false is a player
who downloads the script, runs it, and gets a traceback.

Names come from the parse tree and are matched whole. The first version of
this check was a grep against a list of allowed substrings, and it passed
`import requests` on the strength of "re".
"""
import ast, sys

target = sys.argv[1] if len(sys.argv) > 1 else "guildphone-sync.py"
tree = ast.parse(open(target, encoding="utf-8").read())

names = set()
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        names |= {a.name.split(".")[0] for a in n.names}
    elif isinstance(n, ast.ImportFrom) and n.level == 0 and n.module:
        names.add(n.module.split(".")[0])

if not names:
    sys.exit(f"FAIL: no imports found in {target} at all - this check scanned nothing")

outside = sorted(names - set(sys.stdlib_module_names))
print(f"{target}: {len(names)} modules imported, all stdlib" if not outside
      else f"FAIL: not in the standard library: {', '.join(outside)}")
sys.exit(1 if outside else 0)
