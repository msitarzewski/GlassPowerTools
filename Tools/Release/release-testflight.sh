#!/bin/bash
# Uploads Glass Power Tools for iPhone, iPad and Vision Pro to App Store Connect, for TestFlight (D38).
#
# Run on the maintainer's Mac, with Xcode signed in to the team in Config/Identity.xcconfig (Xcode ▸
# Settings ▸ Accounts): Xcode makes the App Store profiles and uploads with that account. The app record
# (bundle identifier from GPT_BUNDLE_ID, platforms iOS and visionOS) must exist in App Store Connect.
#
#   Tools/Release/release-testflight.sh 0.5.0 500
#   Tools/Release/release-testflight.sh --dry-run 0.5.0 500
#
# --dry-run archives, exports for App Store Connect and runs every check below, then stops: nothing is
# uploaded. Xcode may still create App Store provisioning profiles in the team's account.
#
# Flow, for iOS (iPhone and iPad) and then visionOS: archive (Release, push environment production) →
# export for App Store Connect (or upload) → check the version, and that the app and each extension are
# signed for distribution, with production push and iCloud and a store profile. A build number may be
# uploaded once per platform: bump it for every upload. After processing, a build appears under TestFlight
# in App Store Connect, which asks about encryption until the app's Info.plist answers it.
set -euo pipefail

DRY_RUN=""
[ "${1:-}" = "--dry-run" ] && { DRY_RUN=1; shift; }
VERSION="${1:?usage: release-testflight.sh [--dry-run] <version> <build number>}"
BUILD="${2:?usage: release-testflight.sh [--dry-run] <version> <build number>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

setting() { xcodebuild -project GlassPowerTools.xcodeproj -scheme GlassPowerTools -configuration Release \
  -destination 'generic/platform=iOS' -skipPackagePluginValidation -showBuildSettings 2>/dev/null | awk -v k="$1" '$1 == k { $1=""; $2=""; sub(/^  /, ""); print; exit }'; }
TEAM="$(setting DEVELOPMENT_TEAM)"
[ -n "$TEAM" ] || { echo "No DEVELOPMENT_TEAM in Config/Identity.xcconfig"; exit 1; }
[ "$(setting GPT_ICLOUD_ENVIRONMENT)" = Production ] \
  || { echo "GPT_ICLOUD_ENVIRONMENT is not Production: TestFlight copies would not see the account's library"; exit 1; }

OUT="$ROOT/build/testflight"
PACKAGES="$ROOT/build/SourcePackages"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT" && mkdir -p "$OUT"

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([ -n "$DRY_RUN" ] && echo export || echo upload)</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

# The app and each extension: distribution-signed, production push and iCloud where claimed, and a store
# profile (one that names no devices). The export's .ipa is unpacked to read them.
check() {
  local platform="$1" export_dir="$2"
  local ipa; ipa="$(ls "$export_dir"/*.ipa 2>/dev/null | head -1)"
  [ -n "$ipa" ] || { echo "$platform: no .ipa was exported"; exit 1; }
  rm -rf "$WORK/ipa" && mkdir -p "$WORK/ipa" && ditto -x -k "$ipa" "$WORK/ipa"
  local app; app="$(ls -d "$WORK"/ipa/Payload/*.app | head -1)"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist")" = "$VERSION" ] \
    && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist")" = "$BUILD" ] \
    || { echo "$platform: version or build number mismatch"; exit 1; }
  for bundle in "$app" "$app"/PlugIns/*.appex "$app"/Extensions/*.appex; do
    [ -d "$bundle" ] || continue
    local name; name="$(basename "$bundle")"
    codesign --verify --strict "$bundle" || { echo "$platform/$name: signature invalid"; exit 1; }
    codesign -d --entitlements - --xml "$bundle" > "$WORK/ent.plist" 2>/dev/null || true
    [ "$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$WORK/ent.plist" 2>/dev/null)" = true ] \
      && { echo "$platform/$name: signed for development (get-task-allow)"; exit 1; }
    local aps; aps="$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$WORK/ent.plist" 2>/dev/null || true)"
    [ -z "$aps" ] || [ "$aps" = production ] || { echo "$platform/$name: push environment is $aps"; exit 1; }
    local cloud; cloud="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-container-environment' "$WORK/ent.plist" 2>/dev/null || true)"
    [ -z "$cloud" ] || [ "$cloud" = Production ] || { echo "$platform/$name: iCloud environment is $cloud"; exit 1; }
    [ -f "$bundle/embedded.mobileprovision" ] || { echo "$platform/$name: no provisioning profile"; exit 1; }
    security cms -D -i "$bundle/embedded.mobileprovision" > "$WORK/profile.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$WORK/profile.plist" >/dev/null 2>&1 \
      && { echo "$platform/$name: its profile lists devices, so it is not a store profile"; exit 1; }
    echo "   $platform/$name: $(/usr/libexec/PlistBuddy -c 'Print :Name' "$WORK/profile.plist"); push ${aps:-none}, iCloud ${cloud:-none}"
  done
}

for platform in iOS visionOS; do
  archive="$OUT/GlassPowerTools-$platform.xcarchive"
  echo "==> $platform: archive (Release; push environment production)"
  xcodebuild -project GlassPowerTools.xcodeproj -scheme GlassPowerTools -configuration Release \
    -destination "generic/platform=$platform" -archivePath "$archive" -clonedSourcePackagesDirPath "$PACKAGES" \
    -packageAuthorizationProvider netrc -skipPackagePluginValidation -onlyUsePackageVersionsFromResolvedFile \
    -allowProvisioningUpdates -quiet MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    GPT_APS_ENVIRONMENT=production archive
  if [ -n "$DRY_RUN" ]; then
    echo "==> $platform: export for App Store Connect (dry run: not uploaded)"
  else
    echo "==> $platform: export and upload to App Store Connect"
  fi
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$OUT/$platform" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates -quiet
  if [ -n "$DRY_RUN" ]; then
    echo "==> $platform: checks"
    check "$platform" "$OUT/$platform"
  fi
done

echo
if [ -n "$DRY_RUN" ]; then
  echo "==> dry run: exported for App Store Connect and checked; nothing uploaded ($OUT)"
else
  echo "==> uploaded $VERSION ($BUILD) for iPhone, iPad and Vision Pro."
  echo "    In App Store Connect: wait for processing, answer the encryption question if asked, and add the"
  echo "    build to an internal testing group under TestFlight."
fi
