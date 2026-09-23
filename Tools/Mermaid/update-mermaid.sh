#!/bin/bash
# Keeps the bundled Mermaid current. Runs as the GlassPowerTools scheme's build pre-action, so
# every build — Xcode or xcodebuild — asks the npm registry for the latest version first.
#
# The user's rule (2026-09-23): "make updating it a part of the build process. Check the version
# number and if it moves, download and build the new version in. We never want stale."
#
# - Moved: download the registry's tarball, verify its sha512 against the registry's own
#   integrity field, and replace mermaid.min.js, its LICENSE and VERSION. A tarball that does not
#   verify is discarded and the build keeps the copy it has.
# - Unchanged: nothing is written, so the build is not dirtied.
# - Offline or the registry fails: the build continues with the bundled copy and says so. A
#   build that could not check is not a build that failed.
set -u
ROOT="${SRCROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
DEST="$ROOT/Sources/GlassEditor/Resources/Mermaid"
mkdir -p "$DEST"
say() { echo "update-mermaid: $*"; }

meta=$(curl -sS --fail --max-time 8 https://registry.npmjs.org/mermaid/latest) || { say "registry unreachable; keeping $(cat "$DEST/VERSION" 2>/dev/null || echo none)"; exit 0; }
read -r latest tarball integrity < <(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["version"], d["dist"]["tarball"], d["dist"]["integrity"])' <<<"$meta") || { say "unreadable registry answer; keeping current"; exit 0; }
current=$(cat "$DEST/VERSION" 2>/dev/null || echo "")
if [ "$latest" = "$current" ] && [ -s "$DEST/mermaid.min.js" ]; then say "$current is current"; exit 0; fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
curl -sS --fail --max-time 60 -o "$work/m.tgz" "$tarball" || { say "download failed; keeping ${current:-none}"; exit 0; }
actual="sha512-$(openssl dgst -sha512 -binary "$work/m.tgz" | base64 | tr -d '\n')"
if [ "$actual" != "$integrity" ]; then say "integrity mismatch for $latest; keeping ${current:-none}"; exit 0; fi
tar -xzf "$work/m.tgz" -C "$work" package/dist/mermaid.min.js package/LICENSE 2>/dev/null \
  || tar -xzf "$work/m.tgz" -C "$work" package/dist/mermaid.min.js || { say "tarball lacks dist/mermaid.min.js; keeping ${current:-none}"; exit 0; }
cp "$work/package/dist/mermaid.min.js" "$DEST/mermaid.min.js"
[ -f "$work/package/LICENSE" ] && cp "$work/package/LICENSE" "$DEST/LICENSE"
echo "$latest" > "$DEST/VERSION"
say "updated ${current:-none} -> $latest"
