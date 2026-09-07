#!/usr/bin/env bash
#
# Writes the itms-services manifest that lets iOS install an .ipa straight from
# a web page — the "ad hoc, no TestFlight" install path.
#
# Usage:
#   scripts/make_ota_manifest.sh <bundle-id> <version> <title> <ipa-url> <output.plist>
#
# The IPA URL and the URL this file is served from must both be HTTPS.
set -euo pipefail

BUNDLE_ID="${1:?bundle id}"
VERSION="${2:?version}"
TITLE="${3:?title}"
IPA_URL="${4:?https url to the ipa}"
OUTPUT="${5:?output path}"

cat > "$OUTPUT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>
          <string>software-package</string>
          <key>url</key>
          <string>${IPA_URL}</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key>
        <string>${BUNDLE_ID}</string>
        <key>bundle-version</key>
        <string>${VERSION}</string>
        <key>kind</key>
        <string>software</string>
        <key>title</key>
        <string>${TITLE}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "wrote $OUTPUT -> $IPA_URL"
