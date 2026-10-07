#!/usr/bin/env python3
"""Security gate: reads every scanner report produced by the pipeline and decides pass/fail.

Policy - the build is blocked if any rule is violated:
  SAST     bandit  : no HIGH severity finding        semgrep : no ERROR finding
  SCA      pip-audit: no vulnerable Python package   npm audit: no HIGH/CRITICAL JS package
  SECRETS  gitleaks: zero leaks
  IMAGES   trivy   : no fixable HIGH/CRITICAL CVE in the backend or frontend image
  IaC      trivy   : no HIGH/CRITICAL misconfiguration in Dockerfiles, Helm, K8s, Terraform
"""
import json
import sys
from pathlib import Path

reports = Path(sys.argv[1] if len(sys.argv) > 1 else "reports")
results = []


def load(name):
    path = reports / name
    if not path.exists():
        return None
    text = path.read_text().strip()
    return json.loads(text) if text else {}


def check(label, ok, detail):
    results.append(ok)
    print(f"  [{'PASS' if ok else 'FAIL'}] {label:<40} {detail}")


def missing(label):
    check(label, False, "report missing")


print(f"Security gate - reports from {reports}/")

bandit = load("bandit.json")
if bandit is None:
    missing("SAST    bandit")
else:
    sev = [r["issue_severity"] for r in bandit.get("results", [])]
    check("SAST    bandit HIGH findings", "HIGH" not in sev,
          f"{len(sev)} total ({sev.count('HIGH')} high, {sev.count('MEDIUM')} medium, {sev.count('LOW')} low)")

semgrep = load("semgrep.json")
if semgrep is None:
    missing("SAST    semgrep")
else:
    res = semgrep.get("results", [])
    errors = [r for r in res if r["extra"]["severity"] == "ERROR"]
    check("SAST    semgrep ERROR findings", not errors, f"{len(res)} total, {len(errors)} error")

audit = load("pip-audit.json")
if audit is None:
    missing("SCA     pip-audit")
else:
    deps = audit.get("dependencies", [])
    vulns = [(d["name"], v["id"]) for d in deps for v in d.get("vulns", [])]
    check("SCA     vulnerable Python packages", not vulns,
          f"{len(deps)} packages, {len(vulns)} vulnerable" + (f": {vulns[:3]}" if vulns else ""))

npm = load("npm-audit.json")
if npm is None:
    missing("SCA     npm audit")
else:
    counts = npm.get("metadata", {}).get("vulnerabilities", {})
    bad = counts.get("high", 0) + counts.get("critical", 0)
    check("SCA     npm HIGH/CRITICAL packages", bad == 0,
          f"total={counts.get('total', 0)} high={counts.get('high', 0)} critical={counts.get('critical', 0)}")

leaks = load("gitleaks.json")
if leaks is None:
    missing("SECRETS gitleaks")
else:
    leaks = leaks or []
    check("SECRETS leaked credentials", not leaks,
          f"{len(leaks)} leaks" + (": " + ", ".join(sorted({f"{x['RuleID']}@{x['File']}" for x in leaks})) if leaks else ""))

for image in ("backend", "frontend"):
    trivy = load(f"trivy-{image}.json")
    if trivy is None:
        missing(f"IMAGE   trivy {image}")
        continue
    vulns = [v for r in trivy.get("Results", []) for v in (r.get("Vulnerabilities") or [])
             if v["Severity"] in ("HIGH", "CRITICAL") and v.get("FixedVersion")]
    ids = sorted({v["VulnerabilityID"] for v in vulns})
    check(f"IMAGE   {image} fixable HIGH/CRITICAL CVEs", not vulns,
          f"{len(vulns)} found" + (": " + ", ".join(ids[:5]) if ids else ""))

iac = load("trivy-config.json")
if iac is None:
    missing("IaC     trivy config")
else:
    mis = [(r["Target"], m["ID"]) for r in iac.get("Results", []) for m in (r.get("Misconfigurations") or [])
           if m.get("Status") == "FAIL" and m["Severity"] in ("HIGH", "CRITICAL")]
    check("IaC     HIGH/CRITICAL misconfigurations", not mis,
          f"{len(mis)} found" + (": " + ", ".join(f"{i}@{t}" for t, i in mis[:4]) if mis else ""))

if all(results):
    print(f"\nGATE PASSED ({len(results)}/{len(results)} checks) - images may be pushed and deployed")
    sys.exit(0)
print(f"\nGATE FAILED ({results.count(False)} of {len(results)} checks failed) - fix the findings before shipping")
sys.exit(1)
