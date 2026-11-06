#!/bin/zsh
# Garde: run the automated tests on the newest iPhone simulator. Summary: test-log.txt
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
  trap 'xcrun simctl shutdown "$SIM" >/dev/null 2>&1 || true' EXIT
  xcodebuild test -parallel-testing-enabled NO -collect-test-diagnostics never -jobs 2 -project Garde.xcodeproj -scheme Garde -destination "id=$SIM" CODE_SIGNING_ALLOWED=NO > build/test-full.log 2>&1
  test_result=$?
  grep -E "error:|✘|failed|passed after|\*\* TEST" build/test-full.log | grep -v "^.*✔" | sort -u | head -80
  (( test_result == 0 )) || exit "$test_result"
  echo "DONE"
} > test-log.txt 2>&1
