#!/usr/bin/env bash
#
# Builds the tiny static site that hosts the OTA install link.
#
# Usage:
#   scripts/make_install_page.sh <output-dir> <version> <build> <manifest-url> <ipa-url> [notes]
set -euo pipefail

OUT_DIR="${1:?output dir}"
VERSION="${2:?version}"
BUILD="${3:?build number}"
MANIFEST_URL="${4:?manifest url}"
IPA_URL="${5:?ipa url}"
NOTES="${6:-}"
BUILT_AT="$(date -u '+%Y-%m-%d %H:%M UTC')"

mkdir -p "$OUT_DIR"

cat > "$OUT_DIR/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Install Snappy</title>
<style>
  :root { color-scheme: light dark; }
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center;
    font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: linear-gradient(160deg, #ffd634, #ec3d94); color: #111;
  }
  .card {
    background: rgba(255,255,255,.92); border-radius: 22px; padding: 32px 28px;
    width: min(420px, calc(100vw - 40px)); box-shadow: 0 20px 60px rgba(0,0,0,.25);
  }
  h1 { margin: 0 0 4px; font-size: 26px; }
  .version { color: #666; font-size: 14px; margin-bottom: 22px; }
  a.install {
    display: block; text-align: center; text-decoration: none; font-weight: 600;
    background: #111; color: #fff; padding: 15px; border-radius: 14px; margin-bottom: 18px;
  }
  a.direct { font-size: 13px; color: #555; }
  ol { padding-left: 20px; font-size: 14px; color: #333; }
  li { margin-bottom: 6px; }
  .notes { font-size: 14px; white-space: pre-wrap; background: #f4f4f4; padding: 12px; border-radius: 10px; }
</style>
</head>
<body>
  <div class="card">
    <h1>Snappy</h1>
    <div class="version">Version ${VERSION} (build ${BUILD}) &middot; ${BUILT_AT}</div>

    <a class="install" href="itms-services://?action=download-manifest&amp;url=${MANIFEST_URL}">Install on this iPhone</a>

    <ol>
      <li>Open this page in Safari on the iPhone itself.</li>
      <li>Tap Install, then confirm.</li>
      <li>If it does not appear, the device UDID is not in the provisioning profile yet.</li>
    </ol>

    $( [[ -n "$NOTES" ]] && printf '<div class="notes">%s</div>' "$NOTES" )

    <p><a class="direct" href="${IPA_URL}">Download the .ipa directly</a></p>
  </div>
</body>
</html>
HTML

echo "wrote $OUT_DIR/index.html"
