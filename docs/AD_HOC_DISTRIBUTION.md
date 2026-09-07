# Installing Snappy without TestFlight

Snappy ships as an **ad hoc** build: a signed `.ipa` served from a web page, which
iOS installs over the air. No TestFlight, no App Review, no 24-hour wait for a
build to process.

The trade-off is that Apple only allows this for devices you have registered:
every device that will run the build must have its UDID in the ad hoc
provisioning profile (up to 100 iPhones per membership year).

```
echo 0.1.1 > VERSION && git commit -am "0.1.1" && git push
        │
        ▼
GitHub Actions (.github/workflows/adhoc-release.yml)
  ├─ imports your certificate + profile into a throwaway keychain
  ├─ xcodebuild archive → xcodebuild -exportArchive (method: release-testing)
  ├─ writes manifest.plist (itms-services) + an install page
  ├─ publishes both, plus the .ipa, to GitHub Pages
  └─ attaches the .ipa to a GitHub Release
        │
        ▼
Open the Pages URL in Safari on the iPhone → Install
```

## One-time setup, the short way

```bash
scripts/setup_signing.sh
```

That generates the private key and CSR locally, points you at the three Apple
pages that need a human (certificate, device, profile), builds the `.p12`, and
uploads `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD` and
`PROVISIONING_PROFILE_BASE64` with `gh` so you never open the settings UI. If you
already have a `.p12` and an Ad Hoc `.mobileprovision`, hand them over and it
skips to the upload:

```bash
scripts/setup_signing.sh ~/Downloads/Certificates.p12 ~/Downloads/Snappy.mobileprovision
```

The rest of this section is the same thing done by hand.

## One-time setup, by hand

### 1. Register the devices

In the Apple Developer portal, **Devices → +**, add each iPhone's UDID. Get a UDID
by connecting the phone to a Mac and opening Xcode → Window → Devices and
Simulators (the "Identifier" field), or Finder's device page.

### 2. Create the App ID and the profile

1. **Identifiers → +** → App IDs → App. Use a bundle id you own, e.g.
   `com.yourname.snappy`. No special capabilities are needed — Snappy uses only
   camera, microphone and photo-library-add, which are Info.plist keys rather
   than entitlements.
2. **Profiles → + → Ad Hoc**, pick that App ID, your Apple Distribution
   certificate, and select the devices. Download the `.mobileprovision`.

### 3. Export the signing certificate

In Keychain Access, find your **Apple Distribution** certificate, expand it so the
private key is included, right-click → Export → `.p12`, and set a password.

### 4. Add the repository secrets

Base64-encode both files:

```bash
base64 -i Certificates.p12 | pbcopy        # → BUILD_CERTIFICATE_BASE64
base64 -i Snappy_AdHoc.mobileprovision | pbcopy  # → PROVISIONING_PROFILE_BASE64
```

In **Settings → Secrets and variables → Actions**, add:

| Secret | What it is |
| --- | --- |
| `BUILD_CERTIFICATE_BASE64` | base64 of the `.p12` |
| `P12_PASSWORD` | the password you set when exporting it |
| `PROVISIONING_PROFILE_BASE64` | base64 of the `.mobileprovision` |

The bundle id and team id are read out of the profile at build time, so they are
not secrets you have to keep in sync.

### 5. Let the workflow publish Pages

The workflow asks GitHub to enable Pages on the first run
(`actions/configure-pages` with `enablement: true`). If your account cannot
enable it automatically, turn it on manually: **Settings → Pages → Source:
GitHub Actions**.

> Pages sites are publicly readable, including for private repositories on plans
> where Pages is available. Anyone with the URL can download the `.ipa` — they
> just cannot install it unless their device is in the profile. If that is not
> acceptable, see "Keeping the build private" below.

## Making a build

- **Bump the version:** edit `VERSION`, commit, push to `main`. That file is the
  release trigger; the workflow tags `v<VERSION>` and cuts the Release itself.
- **Or run it by hand:** Actions → *Ad hoc build* → Run workflow, with optional
  release notes. Re-running for a version that already shipped refreshes that
  release in place instead of failing on the tag.

When it finishes, the run summary and the Release both link to the install page.
Open that page **in Safari on the iPhone** (not on a Mac, and not in an in-app
browser), tap Install, and the app appears on the home screen.

## When the install fails

| What you see | Cause |
| --- | --- |
| "Unable to Install" straight away | The device UDID is not in the profile. Add it, regenerate the profile, update the secret, rebuild. |
| "Cannot connect to \<host\>" | The manifest or the `.ipa` is not being served over HTTPS, or the URL 404s. |
| Nothing happens on tap | The page was not opened in Safari, or `itms-services` was stripped by an in-app browser. |
| App installs, then "Untrusted Developer" | Settings → General → VPN & Device Management → trust the certificate. |
| App stops launching after a year | Ad hoc profiles expire after 12 months. Rebuild with a fresh profile. |

## Keeping the build private

The Pages route trades privacy for convenience. Alternatives, in rough order of
effort:

- **Release assets only.** Drop the Pages steps and attach the `.ipa` to a
  private Release. Installing then means Apple Configurator or Xcode's Devices
  window over USB — no OTA link.
- **Your own HTTPS host.** Any static host works; the requirement is only that
  the manifest and the `.ipa` are both HTTPS, and the manifest is reachable from
  the device. `scripts/make_ota_manifest.sh` takes the URL as an argument.
- **Apple Developer Enterprise Program.** $299/year, needs a real organisation
  and a legitimate internal-distribution case, but removes the 100-device limit
  and the UDID registration. Apple audits this.
- **Sideloading tools** (AltStore/SideStore) re-sign with a free personal team.
  That works without any of the above, but the app expires every 7 days.

## Doing it locally

You do not need CI for a one-off build:

```bash
make project
xcodebuild archive -project Snappy.xcodeproj -scheme Snappy \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/Snappy.xcarchive
scripts/make_export_options.sh <TEAM_ID> <BUNDLE_ID> <PROFILE_NAME> build/ExportOptions.plist
xcodebuild -exportArchive -archivePath build/Snappy.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export
```

Then host `build/export/Snappy.ipa` and a manifest from
`scripts/make_ota_manifest.sh` anywhere over HTTPS.
