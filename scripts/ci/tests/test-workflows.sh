#!/usr/bin/env bash
# Loads every .github/workflows/*.yml and runs `bash -n` on each `run:` block.
# Includes a negative check proving that a broken workflow is rejected.
set -euo pipefail
cd "$(dirname "$0")/../../.."
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "SKIP: PyYAML is not installed (pip install pyyaml); workflow checks not run"
  exit 0
fi
CHECK="$(mktemp)"; TMP="$(mktemp -d)"
trap 'rm -f "$CHECK"; rm -rf "$TMP"' EXIT
cat > "$CHECK" <<'PY'
import re, subprocess, sys, yaml
bad = 0
for path in sys.argv[1:]:
    try:
        doc = yaml.safe_load(open(path))
    except Exception as e:
        print(f"FAIL {path}: yaml error: {e}"); bad += 1; continue
    jobs = doc.get("jobs") if isinstance(doc, dict) else None
    if not jobs:
        print(f"FAIL {path}: no jobs"); bad += 1; continue
    for jname, job in jobs.items():
        for i, step in enumerate(job.get("steps", [])):
            run = step.get("run")
            if run is None:
                continue
            script = re.sub(r"\$\{\{.*?\}\}", "EXPR", run, flags=re.S)
            r = subprocess.run(["bash", "-n"], input=script, text=True, capture_output=True)
            if r.returncode:
                print(f"FAIL {path} job {jname} step {step.get('name', i)}: {r.stderr.strip()}"); bad += 1
sys.exit(1 if bad else 0)
PY
python3 "$CHECK" .github/workflows/*.yml || { echo "FAIL: workflows invalid" >&2; exit 1; }
# Negative checks: a broken run block and broken yaml must both be rejected.
printf 'jobs:\n  j:\n    steps:\n      - run: |\n          if then fi (\n' > "$TMP/bad-run.yml"
printf 'jobs: [unclosed\n' > "$TMP/bad-yaml.yml"
python3 "$CHECK" "$TMP/bad-run.yml" >/dev/null && { echo "FAIL: broken run block accepted" >&2; exit 1; }
python3 "$CHECK" "$TMP/bad-yaml.yml" >/dev/null && { echo "FAIL: broken yaml accepted" >&2; exit 1; }
echo "PASS"
