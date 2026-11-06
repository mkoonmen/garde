#!/bin/zsh
# Garde: build, archive and upload to TestFlight using the Apple account signed in to Xcode.
# Full compiler output: build/xcodebuild-full.log   Summary: build-log.txt
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
LOG="$PWD/build-log.txt"
mkdir -p build
{
  echo "== $(date)"
  DEVELOPMENT_TEAM=T3893TN44X xcodegen generate || exit 1
  # One-time: Apple's Metal compiler, needed for the on-device AI engine (MLX).
  xcrun metal -v >/dev/null 2>&1 || xcodebuild -downloadComponent MetalToolchain
  BUILD=$(date +%Y%m%d%H%M)
  rm -rf build/Garde.xcarchive
  xcodebuild archive -jobs 2 -project Garde.xcodeproj -scheme Garde -destination "generic/platform=iOS" \
    -archivePath build/Garde.xcarchive -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=T3893TN44X CURRENT_PROJECT_VERSION=$BUILD > build/xcodebuild-full.log 2>&1
  archive_result=$?
  grep -E "error:|\*\* ARCHIVE|requires a provisioning|No profiles|entitlement|capabilit" build/xcodebuild-full.log | sort -u | head -150
  (( archive_result == 0 )) || { echo "ARCHIVE FAILED"; tail -40 build/xcodebuild-full.log; exit 1; }
  cat > build/ExportOptions.plist <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>teamID</key><string>T3893TN44X</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
P
  xcodebuild -exportArchive -archivePath build/Garde.xcarchive -exportPath build/export \
    -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates > build/export-full.log 2>&1
  export_result=$?
  grep -vE "Progress [0-9]+%" build/export-full.log | tail -30
  (( export_result == 0 )) || exit "$export_result"
  echo "DONE"
} > "$LOG" 2>&1
echo "Finished. You can close this window."
