#!/usr/bin/env bash
#
# Imports the signing certificate and the ad hoc provisioning profile into a
# throwaway keychain, then reports what it found so the build steps can use it.
#
# Expects (base64, from GitHub secrets):
#   BUILD_CERTIFICATE_BASE64   Apple Distribution .p12
#   P12_PASSWORD               password for that .p12
#   PROVISIONING_PROFILE_BASE64  the ad hoc .mobileprovision
#
# Writes PROFILE_UUID, PROFILE_NAME and PROFILE_BUNDLE_ID to $GITHUB_ENV when
# running under Actions, and prints them either way.
set -euo pipefail

: "${BUILD_CERTIFICATE_BASE64:?missing BUILD_CERTIFICATE_BASE64}"
: "${P12_PASSWORD:?missing P12_PASSWORD}"
: "${PROVISIONING_PROFILE_BASE64:?missing PROVISIONING_PROFILE_BASE64}"

WORK_DIR="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN_PATH="$WORK_DIR/snappy-signing.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
CERT_PATH="$WORK_DIR/certificate.p12"
PROFILE_PATH="$WORK_DIR/profile.mobileprovision"

echo "$BUILD_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH"
echo "$PROVISIONING_PROFILE_BASE64" | base64 --decode > "$PROFILE_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERT_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" > /dev/null
security list-keychain -d user -s "$KEYCHAIN_PATH" login.keychain-db

PROFILES_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILES_DIR"

PLIST="$WORK_DIR/profile.plist"
security cms -D -i "$PROFILE_PATH" > "$PLIST"

PROFILE_UUID=$(/usr/libexec/PlistBuddy -c "Print :UUID" "$PLIST")
PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "$PLIST")
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:application-identifier" "$PLIST")
TEAM_PREFIX=$(/usr/libexec/PlistBuddy -c "Print :ApplicationIdentifierPrefix:0" "$PLIST")
PROFILE_BUNDLE_ID="${APP_ID#"$TEAM_PREFIX".}"
DEVICE_COUNT=$(/usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$PLIST" 2>/dev/null | grep -c '^ ' || true)

cp "$PROFILE_PATH" "$PROFILES_DIR/$PROFILE_UUID.mobileprovision"

echo "Installed profile '$PROFILE_NAME' ($PROFILE_UUID)"
echo "  bundle id : $PROFILE_BUNDLE_ID"
echo "  team      : $TEAM_PREFIX"
echo "  devices   : ${DEVICE_COUNT:-0} registered UDIDs"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "PROFILE_UUID=$PROFILE_UUID"
    echo "PROFILE_NAME=$PROFILE_NAME"
    echo "PROFILE_BUNDLE_ID=$PROFILE_BUNDLE_ID"
    echo "PROFILE_TEAM_ID=$TEAM_PREFIX"
  } >> "$GITHUB_ENV"
fi
