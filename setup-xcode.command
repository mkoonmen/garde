#!/bin/zsh
# Garde: makes the Xcode project from project.yml and opens it in Xcode.
cd "$(dirname "$0")"
export PATH="/opt/homebrew/bin:$PATH"
LOG="$PWD/setup-log.txt"
{
  echo "== $(date)"
  command -v xcodegen >/dev/null || brew install xcodegen
  DEVELOPMENT_TEAM=T3893TN44X xcodegen generate
  echo "EXIT $?"
} > "$LOG" 2>&1
open Garde.xcodeproj
echo "Done. You can close this window."
