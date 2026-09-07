#!/usr/bin/env bash
#
# Generates the ExportOptions.plist for an ad hoc export.
#
# Xcode 16 renamed the export methods (`ad-hoc` became `release-testing`); this
# picks the right spelling for whichever Xcode is selected.
#
# Usage: scripts/make_export_options.sh <team-id> <bundle-id> <profile-name> <output.plist>
set -euo pipefail

TEAM_ID="${1:?team id}"
BUNDLE_ID="${2:?bundle id}"
PROFILE_NAME="${3:?provisioning profile name}"
OUTPUT="${4:?output path}"

XCODE_MAJOR=$(xcodebuild -version | head -1 | sed -E 's/Xcode ([0-9]+).*/\1/')
if [[ "$XCODE_MAJOR" -ge 16 ]]; then
  METHOD="release-testing"
else
  METHOD="ad-hoc"
fi

cat > "$OUTPUT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${METHOD}</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
  <key>uploadSymbols</key>
  <false/>
  <key>destination</key>
  <string>export</string>
  <key>thinning</key>
  <string>&lt;none&gt;</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${BUNDLE_ID}</key>
    <string>${PROFILE_NAME}</string>
  </dict>
</dict>
</plist>
PLIST

echo "wrote $OUTPUT (method: $METHOD)"
