#!/usr/bin/env python3
"""Print one line per file from a `trivy config -f json` report (stdin)."""
import json
import sys

results = json.load(sys.stdin).get("Results", [])
for r in results:
    s = r.get("MisconfSummary", {})
    print(f"{r['Type']:<11} {r['Target']:<52} passed={s.get('Successes', 0):<3} failed={s.get('Failures', 0)}")
print(f"{len(results)} files scanned, {sum(r.get('MisconfSummary', {}).get('Failures', 0) for r in results)} HIGH/CRITICAL failures")
