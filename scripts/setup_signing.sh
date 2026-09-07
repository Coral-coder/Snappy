#!/usr/bin/env bash
#
# One-shot signing setup for Snappy's ad hoc builds.
#
# Turns the Apple certificate dance into: run this, click three links, done.
# It generates the private key and CSR, builds the .p12 for you, and uploads all
# three GitHub secrets so you never touch the repository settings UI.
#
#   scripts/setup_signing.sh
#
# If you already have a .p12 and an Ad Hoc .mobileprovision, point it at them and
# it skips straight to the upload:
#
#   scripts/setup_signing.sh ~/Downloads/Certificates.p12 ~/Downloads/Snappy.mobileprovision
#
# Needs: openssl (everywhere), and gh (https://cli.github.com) to upload secrets.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$REPO_ROOT/.signing"
mkdir -p "$WORK"
chmod 700 "$WORK"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[33m%s\033[0m\n' "$1"; }

P12="${1:-}"
PROFILE="${2:-}"

# ---------------------------------------------------------------- discovery --
if [[ -z "$P12" ]]; then
  P12=$(ls -t "$HOME"/Downloads/*.p12 "$REPO_ROOT"/*.p12 2>/dev/null | head -1 || true)
fi
if [[ -z "$PROFILE" ]]; then
  PROFILE=$(ls -t "$HOME"/Downloads/*.mobileprovision "$REPO_ROOT"/*.mobileprovision 2>/dev/null | head -1 || true)
fi

# ------------------------------------------------------------ make the cert --
if [[ -z "$P12" || ! -f "$P12" ]]; then
  step "No .p12 found — let's make one"
  echo "Apple signs your app with a certificate only your account can create."
  echo "This makes the private key locally; the key never leaves this machine."
  echo

  read -r -p "Email on your Apple Developer account: " EMAIL
  read -r -p "Your name (as on the account): " FULLNAME

  KEY="$WORK/distribution.key"
  CSR="$WORK/CertificateSigningRequest.certSigningRequest"
  if [[ ! -f "$KEY" ]]; then
    openssl genrsa -out "$KEY" 2048 2>/dev/null
    chmod 600 "$KEY"
  fi
  openssl req -new -key "$KEY" -out "$CSR" \
    -subj "/emailAddress=${EMAIL}/CN=${FULLNAME}/C=US" 2>/dev/null

  step "Three clicks in the browser"
  bold "1. Certificate"
  echo "   https://developer.apple.com/account/resources/certificates/add"
  echo "   Pick 'Apple Distribution', upload:"
  echo "     $CSR"
  echo "   Download the .cer it gives you."
  echo
  bold "2. Device"
  echo "   https://developer.apple.com/account/resources/devices/add"
  echo "   Add the iPhone's UDID. On a Mac: Finder → the device → click under its"
  echo "   name until the identifier shows. On Windows: Apple Devices app."
  echo
  bold "3. Profile"
  echo "   https://developer.apple.com/account/resources/profiles/add"
  echo "   Type 'Ad Hoc' → your App ID → the certificate from step 1 → the device"
  echo "   from step 2. Download the .mobileprovision."
  echo
  echo "Drop both downloads anywhere in ~/Downloads, then press Return."
  read -r _

  CER=$(ls -t "$HOME"/Downloads/*.cer "$REPO_ROOT"/*.cer 2>/dev/null | head -1 || true)
  [[ -n "$CER" && -f "$CER" ]] || { warn "No .cer found in ~/Downloads. Re-run once it is downloaded."; exit 1; }
  PROFILE=$(ls -t "$HOME"/Downloads/*.mobileprovision "$REPO_ROOT"/*.mobileprovision 2>/dev/null | head -1 || true)
  [[ -n "$PROFILE" && -f "$PROFILE" ]] || { warn "No .mobileprovision found in ~/Downloads. Re-run once it is downloaded."; exit 1; }

  step "Building the .p12"
  P12="$WORK/Certificates.p12"
  P12_PASSWORD="$(openssl rand -hex 16)"
  openssl x509 -inform DER -in "$CER" -out "$WORK/distribution.pem" 2>/dev/null
  openssl pkcs12 -export -legacy \
    -inkey "$WORK/distribution.key" \
    -in "$WORK/distribution.pem" \
    -out "$P12" \
    -passout "pass:${P12_PASSWORD}" 2>/dev/null \
  || openssl pkcs12 -export \
    -inkey "$WORK/distribution.key" \
    -in "$WORK/distribution.pem" \
    -out "$P12" \
    -passout "pass:${P12_PASSWORD}"
  chmod 600 "$P12"
  echo "Built $P12 (password generated, uploaded as a secret — you never need it)."
else
  bold "Using certificate: $P12"
  read -r -s -p "Password for that .p12: " P12_PASSWORD
  echo
fi

[[ -n "${PROFILE:-}" && -f "$PROFILE" ]] || { warn "No .mobileprovision found. Pass it as the second argument."; exit 1; }
bold "Using profile: $PROFILE"

# ------------------------------------------------------------------ report --
if command -v security > /dev/null 2>&1; then
  security cms -D -i "$PROFILE" > "$WORK/profile.plist" 2>/dev/null || true
  if [[ -s "$WORK/profile.plist" ]]; then
    DEVICES=$(/usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$WORK/profile.plist" 2>/dev/null | grep -c '^ ' || true)
    echo "Profile covers ${DEVICES:-0} registered device(s)."
  fi
fi

# ------------------------------------------------------------------ upload --
step "Uploading the secrets"
CERT_B64=$(base64 < "$P12" | tr -d '\n')
PROFILE_B64=$(base64 < "$PROFILE" | tr -d '\n')

if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
  gh secret set BUILD_CERTIFICATE_BASE64 --body "$CERT_B64"
  gh secret set P12_PASSWORD --body "$P12_PASSWORD"
  gh secret set PROVISIONING_PROFILE_BASE64 --body "$PROFILE_B64"
  echo "All three secrets are set."

  step "Kicking off a build"
  echo "Bump VERSION and push, and the .ipa plus its install page are built for you:"
  echo
  echo "  echo 0.1.1 > VERSION && git commit -am 0.1.1 && git push"
  echo
  echo "Then open the install link from the run summary in Safari on the iPhone."
else
  OUT="$WORK/secrets.txt"
  {
    echo "BUILD_CERTIFICATE_BASE64=$CERT_B64"
    echo "P12_PASSWORD=$P12_PASSWORD"
    echo "PROVISIONING_PROFILE_BASE64=$PROFILE_B64"
  } > "$OUT"
  chmod 600 "$OUT"
  warn "gh is not installed or not logged in, so nothing was uploaded."
  echo "Values written to $OUT — paste them into"
  echo "  Settings → Secrets and variables → Actions"
  echo "then delete that file."
fi

echo
warn "$WORK holds your private key. It is gitignored; keep it or delete it, but never commit it."
