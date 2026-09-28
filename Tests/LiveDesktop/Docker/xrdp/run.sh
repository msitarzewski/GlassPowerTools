#!/bin/bash
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
# The probes live in the Tests/LiveDesktop package, two levels up.
package_dir=$(cd "$script_dir/../.." && pwd)
# --disable-keychain: SwiftPM otherwise can wait on a Keychain prompt for package credentials.
swift_flags=(--disable-keychain --package-path "$package_dir")
if [[ -n "${GLASS_SWIFT_SCRATCH:-}" ]]; then swift_flags+=(--scratch-path "$GLASS_SWIFT_SCRATCH"); fi
DOCKER_BIN=${DOCKER_BIN:-$(command -v docker)}
export DOCKER_BIN
artifact_dir=${1:-$(mktemp -d "${TMPDIR:-/tmp}/glass-rdp-evidence.XXXXXX")}
mkdir -p "$artifact_dir"
artifact_dir=$(cd "$artifact_dir" && pwd)
credential_dir=$(mktemp -d "${TMPDIR:-/tmp}/glass-rdp-credential.XXXXXX")
container_name="glass-rdp-fixture-$(uuidgen | tr '[:upper:]' '[:lower:]')"
container_id=""
cleanup() {
  if [[ -n "$container_id" ]]; then "$DOCKER_BIN" rm --force "$container_id" >/dev/null 2>&1 || true; fi
  rm -f "$credential_dir/password"
  if [[ -d "$credential_dir" ]]; then rmdir "$credential_dir"; fi
}
trap cleanup EXIT INT TERM
swift build "${swift_flags[@]}" --product GlassRDPFunctionalProbe > "$artifact_dir/swift-build.log" 2>&1
umask 077
openssl rand -hex 24 | tr -d '\n' > "$credential_dir/password"
"$DOCKER_BIN" build --tag glass-xrdp-fixture:local "$script_dir" > "$artifact_dir/docker-build.log" 2>&1
container_id=$("$DOCKER_BIN" run --detach --name "$container_name" --cpus 2 --memory 2g --memory-swap 2g --pids-limit 256 \
  --publish 127.0.0.1::3389 \
  --mount "type=bind,source=$credential_dir/password,target=/run/glass-test-password,readonly" \
  glass-xrdp-fixture:local)
port=$("$DOCKER_BIN" port "$container_name" 3389/tcp | sed 's/^127\.0\.0\.1://')
for attempt in {1..30}; do
  if nc -z 127.0.0.1 "$port"; then break; fi
  sleep 1
done
"$DOCKER_BIN" exec "$container_name" dpkg-query -W xrdp xorgxrdp > "$artifact_dir/server-versions.txt"
swift run "${swift_flags[@]}" --skip-build GlassRDPFunctionalProbe \
  "$port" "$credential_dir/password" "$container_name" "$artifact_dir" 2> "$artifact_dir/probe-stderr.log" | tee "$artifact_dir/results.jsonl"
printf 'Evidence: %s\n' "$artifact_dir"
