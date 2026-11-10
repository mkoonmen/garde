#!/bin/zsh
# Garde: build and test on the newest iPhone simulator. Summary: test-log.txt
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
mkdir -p build
{
  echo "== $(date)"
  xcodegen generate >/dev/null || exit 1
  SIM=$(xcrun simctl list devices available -j | python3 -c "
import json,sys,re
d=json.load(sys.stdin)['devices']
ios=[(tuple(map(int,re.findall(r'\d+',k.split('iOS-')[1]))),v) for k,v in d.items() if 'iOS-' in k]
ios.sort(reverse=True)
print(next(x['udid'] for _,v in ios for x in v if 'iPhone' in x['name']))")
  echo "Simulator $SIM"
  [[ -n "$SIM" ]] || { echo "No available iPhone simulator"; exit 1; }
  USED_SIM=0
  cleanup() { if (( USED_SIM )); then xcrun simctl shutdown "$SIM" >/dev/null 2>&1 || true; fi }
  trap cleanup EXIT
  xcodebuild build-for-testing -clonedSourcePackagesDirPath build/SourcePackages -jobs 1 -project Garde.xcodeproj -scheme Garde -destination "id=$SIM" \
    CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES COMPILER_INDEX_STORE_ENABLE=NO SWIFT_ENABLE_BATCH_MODE=NO > build/test-full.log 2>&1
  test_result=$?
  if (( test_result == 0 )); then
    # A second Codex chat may be testing another app. Let that run finish before using its simulator.
    while python3 - "$SIM" <<'PY'
import subprocess, sys
lines = subprocess.check_output(['ps', '-axo', 'args='], text=True).splitlines()
sim = sys.argv[1]
busy = any('xcodebuild' in line and sim in line and (' test ' in line or ' test-without-building ' in line) and 'Garde.xcodeproj' not in line for line in lines)
sys.exit(0 if busy else 1)
PY
    do
      echo "Waiting for another app's simulator test to finish."
      sleep 15
    done
    USED_SIM=1
    xcodebuild test-without-building -clonedSourcePackagesDirPath build/SourcePackages -parallel-testing-enabled NO -collect-test-diagnostics never -jobs 1 \
      -project Garde.xcodeproj -scheme Garde -destination "id=$SIM" CODE_SIGNING_ALLOWED=NO >> build/test-full.log 2>&1
    test_result=$?
  fi
  grep -E "error:|✘|failed|Test run with|\*\* TEST" build/test-full.log | sort -u | head -80
  (( test_result == 0 )) || exit "$test_result"
  echo "DONE"
} > test-log.txt 2>&1
