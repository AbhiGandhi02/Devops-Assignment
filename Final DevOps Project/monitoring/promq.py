#!/usr/bin/env python3
"""Tiny PromQL client: promq.py <prometheus-url> '<query>'  -> one line per series."""
import json
import sys
import urllib.parse
import urllib.request

url, query = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(f"{url}/api/v1/query?" + urllib.parse.urlencode({"query": query}), timeout=10) as r:
    result = json.load(r)["data"]["result"]
for s in result:
    labels = ",".join(f"{k}={v}" for k, v in s["metric"].items()) or "{}"
    print(f"{labels:<45} {float(s['value'][1]):.3f}")
if not result:
    print("(no data)")
