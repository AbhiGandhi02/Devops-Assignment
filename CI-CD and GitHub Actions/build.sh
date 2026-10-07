#!/usr/bin/env bash
# Packages the app into build/ and writes build metadata - uploaded as a CI artifact.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build && mkdir -p build
cp -r app requirements.txt build/
find build -name '__pycache__' -prune -exec rm -rf {} +
cat > build/build-info.txt <<INFO
application : orbit-tasks
commit      : ${GITHUB_SHA:-local}
run number  : ${GITHUB_RUN_NUMBER:-local}
built by    : ${GITHUB_ACTOR:-$(whoami)}
built at    : $(date -u +%Y-%m-%dT%H:%M:%SZ)
INFO
tar -czf build/orbit-tasks.tar.gz -C build app requirements.txt build-info.txt
echo "Build complete:"
ls -l build
