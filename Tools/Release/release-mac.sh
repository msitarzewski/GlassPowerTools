#!/bin/bash
# Builds a signed, notarized, stapled Mac release of Glass Power Tools (D38):
#   build/release/GlassPowerTools-<version>.dmg and .zip, and a new entry in site/static/appcast.xml.
#
# Run on the maintainer's Mac, which holds the "Developer ID Application" certificate for the team
# in Config/Identity.xcconfig, and Sparkle's EdDSA private key in the login Keychain
# (made once with Sparkle's `generate_keys --account GlassPowerTools`; its public half goes in
# GPT_SPARKLE_PUBLIC_KEY in Config/Identity.xcconfig — a build without it does not update itself).
#
# Needs, in the environment:
#   APPLE_ID, APPLE_PASSWORD (an app-specific password), APPLE_TEAM_ID   — for notarytool
#
#   set -a; source <your signing environment file>; set +a
#   Tools/Release/release-mac.sh 1.0.0 100 [notes.html]
#
# Flow: archive (Release, push environment production) → export with Developer ID (app and widget,
# Sparkle's helpers, hardened runtime) → verify signatures, hardened runtime, entitlements and the
# update key → notarize the app → staple → Sparkle zip, signed with the EdDSA key → feed entry →
# disk image with an Applications link → sign → notarize → staple → checksums.
# Afterwards: publish the GitHub release v<version> with the .dmg and .zip, THEN publish the site
# (the feed points at the zip on the release).
set -euo pipefail

VERSION="${1:?usage: release-mac.sh <version> <build number> [notes.html]}"
BUILD="${2:?usage: release-mac.sh <version> <build number> [notes.html]}"
NOTES="${3:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

: "${APPLE_ID:?set APPLE_ID (see the header of this script)}"
: "${APPLE_PASSWORD:?set APPLE_PASSWORD (an app-specific password)}"
: "${APPLE_TEAM_ID:?set APPLE_TEAM_ID}"

setting() { xcodebuild -project GlassPowerTools.xcodeproj -scheme GlassPowerTools -configuration Release \
  -destination 'generic/platform=macOS' -skipPackagePluginValidation -showBuildSettings 2>/dev/null | awk -v k="$1" '$1 == k { $1=""; $2=""; sub(/^  /, ""); print; exit }'; }
TEAM="$(setting DEVELOPMENT_TEAM)"
[ "$TEAM" = "$APPLE_TEAM_ID" ] || { echo "Config/Identity.xcconfig team ($TEAM) doesn't match APPLE_TEAM_ID"; exit 1; }
[ -n "$(setting GPT_SPARKLE_PUBLIC_KEY)" ] || { echo "GPT_SPARKLE_PUBLIC_KEY is empty: this build would not update itself"; exit 1; }
IDENTITY="$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM)" | head -1 | awk '{print $2}')"
[ -n "$IDENTITY" ] || { echo "No Developer ID Application certificate for team $TEAM in the Keychain"; exit 1; }

OUT="$ROOT/build/release"
PACKAGES="$ROOT/build/SourcePackages"
SPARKLE_BIN="$PACKAGES/artifacts/sparkle/Sparkle/bin"
ARCHIVE="$OUT/GlassPowerTools.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/Glass Power Tools.app"
ZIP="$OUT/GlassPowerTools-$VERSION.zip"
DMG="$OUT/GlassPowerTools-$VERSION.dmg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT" && mkdir -p "$OUT"

notarize() {
  xcrun notarytool submit "$1" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID" \
    --wait --output-format json | tee "$WORK/notary.json" | grep -q '"status" *: *"Accepted"' || {
      echo "Notarization failed:"; cat "$WORK/notary.json"
      id="$(sed -nE 's/.*"id" *: *"([^"]+)".*/\1/p' "$WORK/notary.json" | head -1)"
      [ -n "$id" ] && xcrun notarytool log "$id" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$APPLE_TEAM_ID"
      exit 1
    }
}

echo "==> Glass Power Tools $VERSION ($BUILD), team $TEAM"
echo "==> archive (Release; push environment production for released copies, D38)"
xcodebuild -project GlassPowerTools.xcodeproj -scheme GlassPowerTools -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$ARCHIVE" -clonedSourcePackagesDirPath "$PACKAGES" \
  -packageAuthorizationProvider netrc -skipPackagePluginValidation -allowProvisioningUpdates -quiet \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" GPT_APS_ENVIRONMENT=production archive

echo "==> export with Developer ID"
cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates -quiet

echo "==> verify"
codesign --verify --deep --strict --verbose=2 "$APP"
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
for helper in "$SPARKLE_FW" "$SPARKLE_FW/Versions/B/Autoupdate" "$SPARKLE_FW/Versions/B/Updater.app" \
  "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc" "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"; do
  # Captured first: with pipefail, `grep -q` closing the pipe early would read as a failure.
  info="$(codesign -dvv "$helper" 2>&1)"
  grep -q "Authority=Developer ID Application" <<<"$info" || { echo "$helper: not Developer ID signed"; exit 1; }
done
info="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$info" || { echo "app: not Developer ID signed"; exit 1; }
grep -q "flags=.*runtime" <<<"$info" || { echo "app: hardened runtime missing"; exit 1; }
entitlements="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
grep -q "production" <<<"$entitlements" || { echo "app: push environment is not production"; exit 1; }
# Not sandboxed on purpose (SECURITY.md): a terminal must start the user's shell.
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION" ] \
  || { echo "version mismatch"; exit 1; }
[ -n "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist" 2>/dev/null)" ] \
  || { echo "SUPublicEDKey missing from the build"; exit 1; }

echo "==> notarize the app (waits for Apple)"
ditto -c -k --keepParent "$APP" "$WORK/GlassPowerTools.zip"
notarize "$WORK/GlassPowerTools.zip"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "==> Sparkle update: zip, EdDSA signature, feed entry"
[ -x "$SPARKLE_BIN/sign_update" ] || { echo "Sparkle tools missing at $SPARKLE_BIN"; exit 1; }
ditto -c -k --keepParent "$APP" "$ZIP"
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account GlassPowerTools -p "$ZIP")"
[ -n "$SIGNATURE" ] || { echo "sign_update produced no signature"; exit 1; }
python3 "$ROOT/Tools/Release/appcast.py" "$VERSION" "$BUILD" "$ZIP" "$SIGNATURE" ${NOTES:+"$NOTES"}

echo "==> disk image"
mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/Glass Power Tools.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -volname "Glass Power Tools $VERSION" -srcfolder "$WORK/dmg" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "==> notarize the disk image (waits for Apple)"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > "GlassPowerTools-$VERSION.sha256")
echo
echo "==> done: $DMG and $ZIP; site/static/appcast.xml updated"
cat "$OUT/GlassPowerTools-$VERSION.sha256"
echo "Next: publish the GitHub release v$VERSION with both files, then rebuild and publish the site (the feed)."
