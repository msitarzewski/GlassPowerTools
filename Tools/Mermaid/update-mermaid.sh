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
# - Licences: mermaid.min.js is compiled from Mermaid and every package it depends on. A new
#   version is taken only with a list of those packages' licences, from an npm install of that
#   version (mermaid-licenses.py), and only when every licence is one already reviewed. A new kind
#   stops the update and the build keeps the copy it has. The acknowledgements are then rebuilt.
set -u
# Xcode runs pre-actions with a minimal PATH; npm usually lives in Homebrew.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
ROOT="${SRCROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
DEST="$ROOT/Sources/GlassEditor/Resources/Mermaid"
LIST="$ROOT/Documentation/ThirdPartyLicenses/mermaid/bundled-packages.json"
mkdir -p "$DEST" "$(dirname "$LIST")"
say() { echo "update-mermaid: $*"; }

meta=$(curl -sS --fail --max-time 8 https://registry.npmjs.org/mermaid/latest) || { say "registry unreachable; keeping $(cat "$DEST/VERSION" 2>/dev/null || echo none)"; exit 0; }
read -r latest tarball integrity < <(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["version"], d["dist"]["tarball"], d["dist"]["integrity"])' <<<"$meta") || { say "unreadable registry answer; keeping current"; exit 0; }
current=$(cat "$DEST/VERSION" 2>/dev/null || echo "")
listed=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mermaid"])' "$LIST" 2>/dev/null || echo "")
if [ "$latest" = "$current" ] && [ -s "$DEST/mermaid.min.js" ] && [ "$listed" = "$current" ]; then say "$current is current"; exit 0; fi

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# The licence list first: without one, nothing changes.
command -v npm >/dev/null || { say "npm not found, so $latest's licences cannot be listed; keeping ${current:-none}"; exit 0; }
npm install --prefix "$work/deps" --ignore-scripts --omit=dev --omit=peer --omit=optional \
  --no-audit --no-fund --no-package-lock --loglevel=error "mermaid@$latest" >/dev/null 2>&1 \
  || { say "npm install of $latest failed; keeping ${current:-none}"; exit 0; }
python3 "$ROOT/Tools/Mermaid/mermaid-licenses.py" "$work/deps/node_modules" "$latest" "$work/licenses.json" \
  || { say "WARNING: $latest brings a licence nobody has reviewed (above); keeping ${current:-none}. Review it, add it to mermaid-licenses.py, rebuild."; exit 0; }
curl -sS --fail --max-time 60 -o "$work/m.tgz" "$tarball" || { say "download failed; keeping ${current:-none}"; exit 0; }
actual="sha512-$(openssl dgst -sha512 -binary "$work/m.tgz" | base64 | tr -d '\n')"
if [ "$actual" != "$integrity" ]; then say "integrity mismatch for $latest; keeping ${current:-none}"; exit 0; fi
tar -xzf "$work/m.tgz" -C "$work" package/dist/mermaid.min.js package/LICENSE 2>/dev/null \
  || tar -xzf "$work/m.tgz" -C "$work" package/dist/mermaid.min.js || { say "tarball lacks dist/mermaid.min.js; keeping ${current:-none}"; exit 0; }
cp "$work/package/dist/mermaid.min.js" "$DEST/mermaid.min.js"
[ -f "$work/package/LICENSE" ] && cp "$work/package/LICENSE" "$DEST/LICENSE"
echo "$latest" > "$DEST/VERSION"
cp "$work/licenses.json" "$LIST"
python3 "$ROOT/Tools/Licenses/generate-acknowledgements.py" || say "WARNING: acknowledgements not rebuilt; run Tools/Licenses/generate-acknowledgements.py"
say "updated ${current:-none} -> $latest"
