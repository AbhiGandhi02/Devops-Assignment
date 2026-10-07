#!/usr/bin/env python3
"""Security gate: reads every scanner report and decides pass/fail.

Policy (fail the pipeline if any is violated):
  SAST    - Bandit: no HIGH severity findings;  Semgrep: no ERROR findings
  SCA     - pip-audit: no known vulnerable dependency
  Secrets - Gitleaks: zero leaks
  Image   - Trivy: no fixable CRITICAL or HIGH vulnerability
"""
import json
import sys
from pathlib import Path

reports = Path(sys.argv[1] if len(sys.argv) > 1 else "reports")


def load(name, default):
    p = reports / name
    if not p.exists():
        print(f"  ! {name} missing - treating as failure")
        return None
    text = p.read_text().strip()
    return json.loads(text) if text else default


results = []


def check(label, ok, detail):
    results.append(ok)
    print(f"  [{'PASS' if ok else 'FAIL'}] {label:<34} {detail}")


print("Security gate policy check")
bandit = load("bandit.json", {"results": []})
if bandit is not None:
    sev = [r["issue_severity"] for r in bandit["results"]]
    check("SAST   bandit HIGH findings", "HIGH" not in sev,
          f"{len(sev)} total, {sev.count('HIGH')} high, {sev.count('MEDIUM')} medium")
else:
    check("SAST   bandit", False, "report missing")

semgrep = load("semgrep.json", {"results": []})
if semgrep is not None:
    errs = [r for r in semgrep["results"] if r["extra"]["severity"] == "ERROR"]
    check("SAST   semgrep ERROR findings", not errs, f"{len(semgrep['results'])} total, {len(errs)} error")
else:
    check("SAST   semgrep", False, "report missing")

audit = load("pip-audit.json", {"dependencies": []})
if audit is not None:
    vulns = [(d["name"], v["id"]) for d in audit["dependencies"] for v in d.get("vulns", [])]
    check("SCA    vulnerable dependencies", not vulns, f"{len(audit['dependencies'])} deps scanned, {len(vulns)} vulnerable")
else:
    check("SCA    pip-audit", False, "report missing")

leaks = load("gitleaks.json", [])
if leaks is not None:
    check("SECRET leaked credentials", not leaks, f"{len(leaks)} leaks")
else:
    check("SECRET gitleaks", False, "report missing")

trivy = load("trivy-image.json", {"Results": []})
if trivy is not None:
    vulns = [v for r in trivy.get("Results", []) for v in (r.get("Vulnerabilities") or [])
             if v["Severity"] in ("HIGH", "CRITICAL") and v.get("FixedVersion")]
    check("IMAGE  fixable HIGH/CRITICAL CVEs", not vulns,
          f"{len(vulns)} found" + (": " + ", ".join(sorted({v['VulnerabilityID'] for v in vulns})[:5]) if vulns else ""))
else:
    check("IMAGE  trivy", False, "report missing")

if all(results):
    print("\nGATE PASSED - image may be pushed and deployed")
    sys.exit(0)
print("\nGATE FAILED - fix the findings above before this build can ship")
sys.exit(1)
