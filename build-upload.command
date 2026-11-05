#!/bin/zsh
# Garde: build, archive and upload to TestFlight using the Apple account signed in to Xcode.
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
LOG="$PWD/build-log.txt"
{
  echo "== $(date)"
  DEVELOPMENT_TEAM=T3893TN44X xcodegen generate || exit 1
  BUILD=$(date +%Y%m%d%H%M)
  xcodebuild archive -project Garde.xcodeproj -scheme Garde -destination "generic/platform=iOS" \
    -archivePath build/Garde.xcarchive -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=T3893TN44X CURRENT_PROJECT_VERSION=$BUILD 2>&1 | grep -E "error:|warning: .*deprecated|\*\* ARCHIVE|Signing|provision" | head -200
  [ -d build/Garde.xcarchive ] || { echo "ARCHIVE FAILED"; exit 1; }
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
    -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates 2>&1 | tail -30
  echo "DONE"
} > "$LOG" 2>&1
echo "Finished. You can close this window."
