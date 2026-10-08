#!/usr/bin/env python3
"""Reports dependencies with newer releases, and tests the app against them. Changes nothing here.

Every dependency stays pinned (Package.resolved, and `exact:` or `revision:` where Package.swift
says so): the same commit always builds the same app, and a terminal that reads bytes from remote
machines takes new parser code only on purpose. Pinning's cost is drift — SwiftTerm 1.19 answered
XTVERSION for weeks before anyone noticed (2026-10-07). This closes that gap without loosening a pin.

  check-updates.py
      For every pin: the newest release, whether Package.swift already allows it, and for a newer
      one on GitHub, its release notes, the commits since our pin, and changes worth a person's
      look before taking it — a new build-tool plugin, binary target, unsafe flag or dependency in
      its manifest, or a changed licence file.

  check-updates.py --test NAME[@VERSION] [--test ...]
      In a temporary worktree (this checkout's committed state plus its uncommitted changes), moves
      NAME's pin to VERSION (default: the newest release), resolves, runs every test target, and
      builds the app for macOS, iOS and visionOS. Reports by exit status, never by grepping output.
      `--test newer` does this for every direct dependency with a newer release.

  --report PATH   also write the report there; a folder gets a dated file.
  --notify        post a macOS notification when something is newer or a test fails.
  --platforms     comma-separated, default macOS,iOS,visionOS; "none" skips the app builds.
  --keep          leave the worktree for inspection.

Raising a pin for real stays a person's decision: edit Package.swift, `swift package update NAME`,
`Tools/Packages/sync-xcode-pins.py`, `Tools/Licenses/generate-acknowledgements.py`.
Exit status: 0 when every requested test passed (or none was requested), 1 otherwise.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
VERSION_TAG = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)$")
# Swift Testing's per-target totals and its failures.
SUMMARY_LINE = re.compile(r"^(?:[✔✘━] Test run with \d+ tests|✘ Test \S)")
# Manifest lines that run or link code we have not reviewed: these want a person, not a script.
REVIEW_WORTHY = [
    (re.compile(r"\.plugin\s*\(|buildTool|\.buildCommand|prebuildCommand"), "a build-tool plugin (runs code during our build)"),
    (re.compile(r"\.binaryTarget\s*\("), "a binary target (prebuilt code)"),
    (re.compile(r"unsafeFlags"), "unsafe compiler or linker flags"),
    (re.compile(r"\.package\s*\("), "a new or changed dependency of its own"),
]


def run(command, cwd=ROOT, check=False, env=None, log=None):
    """Runs a command; returns (status, output). With `log`, output goes to that file instead."""
    if log:
        with open(log, "w", encoding="utf-8") as handle:
            status = subprocess.call(command, cwd=cwd, stdout=handle, stderr=subprocess.STDOUT, env=env)
        output = ""
    else:
        result = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                env=env, universal_newlines=True)
        status, output = result.returncode, result.stdout
    if check and status != 0:
        raise SystemExit("check-updates: %s failed (%d)\n%s" % (" ".join(command), status, output[-2000:]))
    return status, output


def version_tuple(text):
    match = VERSION_TAG.match(text or "")
    return tuple(int(part) for part in match.groups()) if match else None


def declared_requirements(root):
    """Package.swift's requirement for each URL: (kind, value), e.g. ("exact", "1.20.0")."""
    with open(os.path.join(root, "Package.swift"), encoding="utf-8") as handle:
        manifest = handle.read()
    requirements = {}
    for match in re.finditer(r'\.package\(\s*url:\s*"([^"]+)"\s*,\s*(exact|from|revision|branch)\s*:\s*"([^"]+)"',
                             manifest):
        requirements[normalized(match.group(1))] = (match.group(2), match.group(3))
    return requirements


def normalized(url):
    return url.rstrip("/").lower().removesuffix(".git") if hasattr(str, "removesuffix") \
        else re.sub(r"\.git$", "", url.rstrip("/").lower())


def pins(root):
    with open(os.path.join(root, "Package.resolved"), encoding="utf-8") as handle:
        return json.load(handle)["pins"]


def remote_versions(url):
    """Release tags on the remote, newest first, as (tuple, tag)."""
    status, output = run(["git", "ls-remote", "--tags", "--refs", url])
    if status != 0:
        return None
    tags = []
    for line in output.splitlines():
        tag = line.split("refs/tags/")[-1]
        parsed = version_tuple(tag)
        if parsed:
            tags.append((parsed, tag))
    return sorted(tags, reverse=True)


def remote_head(url):
    status, output = run(["git", "ls-remote", url, "HEAD"])
    return output.split()[0] if status == 0 and output.strip() else None


def github_repository(url):
    match = re.match(r"https://github\.com/([^/]+/[^/]+?)(?:\.git)?/?$", url)
    return match.group(1) if match else None


def gh(*arguments):
    if not shutil.which("gh"):
        return None
    status, output = run(["gh", "api"] + list(arguments))
    return output if status == 0 else None


def file_at(repository, path, ref):
    output = gh("repos/%s/contents/%s?ref=%s" % (repository, path, ref), "--jq", ".content")
    if output is None:
        return None
    import base64
    try:
        return base64.b64decode(output).decode("utf-8", "replace")
    except ValueError:
        return None


def licence_sha(repository, ref):
    for name in ("LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING"):
        output = gh("repos/%s/contents/%s?ref=%s" % (repository, name, ref), "--jq", ".sha")
        if output:
            return output.strip()
    return None


def review_points(repository, old_ref, new_ref):
    """What changed between two refs that a person should look at before taking the new one."""
    points = []
    old_manifest, new_manifest = file_at(repository, "Package.swift", old_ref), file_at(repository, "Package.swift", new_ref)
    if old_manifest is not None and new_manifest is not None:
        old_lines = set(line.strip() for line in old_manifest.splitlines())
        added = [line.strip() for line in new_manifest.splitlines() if line.strip() not in old_lines]
        for pattern, meaning in REVIEW_WORTHY:
            hits = [line for line in added if pattern.search(line)]
            if hits:
                points.append("manifest adds %s: `%s`" % (meaning, hits[0][:100]))
    old_licence, new_licence = licence_sha(repository, old_ref), licence_sha(repository, new_ref)
    if old_licence and new_licence and old_licence != new_licence:
        points.append("the licence file changed")
    return points


def commits_between(repository, old_ref, new_ref):
    output = gh("repos/%s/compare/%s...%s" % (repository, old_ref, new_ref),
                "--jq", '"\\(.total_commits)", (.commits[] | .commit.message | split("\\n")[0])')
    if output is None:
        return None, []
    lines = output.splitlines()
    return (int(lines[0]) if lines and lines[0].isdigit() else None), lines[1:]


def release_notes(repository, tag):
    output = gh("repos/%s/releases/tags/%s" % (repository, tag), "--jq", ".body")
    return (output or "").strip()


def survey(root):
    requirements = declared_requirements(root)
    entries = []
    for pin in pins(root):
        url, state = pin["location"], pin["state"]
        requirement = requirements.get(normalized(url))
        entry = {"name": pin["identity"], "url": url, "requirement": requirement,
                 "direct": requirement is not None, "version": state.get("version"),
                 "revision": state.get("revision"), "newer": [], "notes": []}
        versions = remote_versions(url)
        if versions is None:
            entry["notes"].append("could not reach the remote")
        elif entry["version"] and version_tuple(entry["version"]):
            current = version_tuple(entry["version"])
            entry["newer"] = [tag for parsed, tag in versions if parsed > current]
        else:
            # Pinned to a commit: say whether the remote has moved on, and its newest release.
            head = remote_head(url)
            if head and head != entry["revision"]:
                entry["notes"].append("default branch has moved past the pinned commit")
            if versions:
                entry["notes"].append("newest release: %s" % versions[0][1])
        if entry["newer"]:
            newest = entry["newer"][0]
            entry["newest"] = newest
            entry["allowed"] = allowed(requirement, newest, entry["version"])
            repository = github_repository(url)
            if repository:
                old_ref = next((tag for parsed, tag in versions if tag.lstrip("v") == entry["version"]), entry["revision"])
                count, messages = commits_between(repository, old_ref, newest)
                entry["commits"], entry["commit_messages"] = count, messages[:40]
                entry["review"] = review_points(repository, old_ref, newest)
                entry["release_notes"] = release_notes(repository, newest)
        entries.append(entry)
    return entries


def allowed(requirement, newest, current):
    """Whether Package.swift already allows `newest` (so `swift package update` would take it)."""
    new, old = version_tuple(newest), version_tuple(current)
    if requirement is None:
        major = "; a new major version" if new and old and new[0] != old[0] else ""
        return "set by another package's requirement" + major
    kind, value = requirement
    if kind == "from" and new and old:
        return "yes" if new[0] == version_tuple(value)[0] else "no: a new major version"
    if kind == "exact":
        return "no: Package.swift pins exactly %s" % value
    return "no: Package.swift pins a %s" % kind


def survey_markdown(entries):
    behind = [entry for entry in entries if entry["newer"]]
    lines = ["# Dependency check, %s" % datetime.date.today().isoformat(), "",
             "%d pins; %d with a newer release." % (len(entries), len(behind)), ""]
    for entry in behind:
        lines.append("## %s %s → %s%s" % (entry["name"], entry["version"], entry["newest"],
                                          "" if entry["direct"] else " (indirect)"))
        lines.append("- Allowed by Package.swift: %s" % entry["allowed"])
        if len(entry["newer"]) > 1:
            lines.append("- Releases since ours: %s" % ", ".join(entry["newer"][:12]))
        if entry.get("commits") is not None:
            lines.append("- %d commit%s since our pin" % (entry["commits"], "" if entry["commits"] == 1 else "s"))
        for point in entry.get("review", []):
            lines.append("- **Review:** %s" % point)
        if entry.get("commit_messages"):
            lines.append("")
            lines.append("<details><summary>Commits</summary>")
            lines.append("")
            lines.extend("- %s" % message for message in entry["commit_messages"])
            lines.append("</details>")
        if entry.get("release_notes"):
            lines.append("")
            lines.append("<details><summary>Release notes %s</summary>" % entry["newest"])
            lines.append("")
            lines.extend("> " + line for line in entry["release_notes"][:4000].splitlines())
            lines.append("</details>")
        lines.append("")
    others = [entry for entry in entries if entry["notes"] and not entry["newer"]]
    if others:
        lines.append("## Pinned to commits, or unreachable")
        lines.extend("- %s: %s" % (entry["name"], "; ".join(entry["notes"])) for entry in others)
        lines.append("")
    return lines


def copy_working_state(worktree):
    """The worktree starts at HEAD; add this checkout's uncommitted and untracked changes."""
    status, diff = run(["git", "diff", "--binary", "HEAD"])
    if diff.strip():
        applied = subprocess.run(["git", "apply", "--whitespace=nowarn", "-"], cwd=worktree,
                                 input=diff, universal_newlines=True)
        if applied.returncode != 0:
            raise SystemExit("check-updates: could not apply the uncommitted changes to the worktree")
    _, untracked = run(["git", "ls-files", "--others", "--exclude-standard", "-z"])
    for path in filter(None, untracked.split("\0")):
        target = os.path.join(worktree, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(os.path.join(ROOT, path), target)


def set_requirement(worktree, url, version):
    path = os.path.join(worktree, "Package.swift")
    with open(path, encoding="utf-8") as handle:
        manifest = handle.read()
    pattern = re.compile(r'(\.package\(\s*url:\s*"%s(?:\.git)?"\s*,\s*)(exact|from|revision|branch)\s*:\s*"[^"]+"'
                         % re.escape(re.sub(r"\.git$", "", url)))
    requirement = 'revision: "%s"' % version if re.fullmatch(r"[0-9a-f]{40}", version) else 'exact: "%s"' % version.lstrip("v")
    manifest, count = pattern.subn(lambda match: match.group(1) + requirement, manifest)
    if count != 1:
        raise SystemExit("check-updates: %s is not a direct dependency in Package.swift" % url)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(manifest)


def test_candidate(name, version, entries, platforms, keep, logs):
    entry = next((entry for entry in entries if entry["name"] == name.lower()), None)
    if entry is None or not entry["direct"]:
        return {"name": name, "result": "not a direct dependency", "passed": False}
    version = version or (entry["newer"][0] if entry["newer"] else None)
    if version is None:
        return {"name": name, "result": "no newer release to test", "passed": True}
    worktree = tempfile.mkdtemp(prefix="glass-dependency-%s-" % entry["name"])
    os.rmdir(worktree)
    run(["git", "worktree", "add", "--detach", worktree, "HEAD"], check=True)
    steps = []
    try:
        copy_working_state(worktree)
        set_requirement(worktree, entry["url"], version)
        log = lambda step: os.path.join(logs, "%s-%s-%s.log" % (entry["name"], version, step))
        environment = dict(os.environ)
        status, _ = run(["swift", "package", "resolve", "--disable-keychain"], cwd=worktree, env=environment, log=log("resolve"))
        steps.append(("resolve", status, log("resolve")))
        if status == 0:
            # What raising a pin for real does next, so only real differences fail the tests.
            run([sys.executable, "Tools/Packages/sync-xcode-pins.py"], cwd=worktree)
            run([sys.executable, "Tools/Licenses/generate-acknowledgements.py"], cwd=worktree)
            status, _ = run(["swift", "build", "--disable-keychain", "--build-tests"], cwd=worktree, log=log("build"))
            steps.append(("build and tests compile", status, log("build")))
        if status == 0:
            status, _ = run(["swift", "test", "--disable-keychain", "--skip-build"], cwd=worktree, log=log("test"))
            steps.append(("every test target", status, log("test")))
            with open(log("test"), encoding="utf-8", errors="replace") as handle:
                summary = [line.strip() for line in handle if SUMMARY_LINE.match(line)]
            steps.append(("summary", 0, "\n".join(summary[-40:])))
        for platform in platforms:
            if status != 0:
                break
            derived = os.path.join(worktree, ".build", "xcode-%s" % platform)
            platform_status, _ = run(["xcodebuild", "-scheme", "GlassPowerTools", "-configuration", "Debug",
                                      "-destination", "generic/platform=%s" % platform,
                                      "-derivedDataPath", derived, "-packageAuthorizationProvider", "netrc",
                                      "-skipPackagePluginValidation", "CODE_SIGNING_ALLOWED=NO", "build"],
                                     cwd=worktree, log=log("app-%s" % platform))
            steps.append(("app builds for %s" % platform, platform_status, log("app-%s" % platform)))
    finally:
        if keep:
            print("check-updates: worktree kept at %s" % worktree, file=sys.stderr)
        else:
            run(["git", "worktree", "remove", "--force", worktree])
    passed = all(status == 0 for _, status, _ in steps) and any(step == "every test target" for step, _, _ in steps)
    return {"name": entry["name"], "from": entry["version"] or entry["revision"][:12], "to": version,
            "steps": steps, "passed": passed}


def test_markdown(results):
    lines = ["# Tested against newer releases", ""]
    for result in results:
        if "steps" not in result:
            lines.append("- %s: %s" % (result["name"], result["result"]))
            continue
        lines.append("## %s %s → %s: %s" % (result["name"], result["from"], result["to"],
                                           "**passed**" if result["passed"] else "**FAILED**"))
        for step, status, detail in result["steps"]:
            if step == "summary":
                if detail:
                    lines.extend(["", "```", detail, "```"])
                continue
            lines.append("- %s: %s (log: `%s`)" % (step, "passed" if status == 0 else "failed, exit %d" % status, detail))
        lines.append("")
    return lines


def notify(title, message):
    script = 'display notification %s with title %s' % (json.dumps(message), json.dumps(title))
    subprocess.call(["osascript", "-e", script])


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--test", action="append", default=[], metavar="NAME[@VERSION]")
    parser.add_argument("--platforms", default="macOS,iOS,visionOS")
    parser.add_argument("--report")
    parser.add_argument("--notify", action="store_true")
    parser.add_argument("--keep", action="store_true")
    options = parser.parse_args()
    if options.report and (options.report.endswith("/") or os.path.isdir(options.report)):
        options.report = os.path.join(options.report, "dependency-check-%s.md" % datetime.date.today().isoformat())

    entries = survey(ROOT)
    lines = survey_markdown(entries)
    results = []
    if options.test:
        platforms = [] if options.platforms == "none" else options.platforms.split(",")
        logs = os.path.join(os.path.dirname(os.path.abspath(options.report)) if options.report else tempfile.gettempdir(),
                            "glass-dependency-logs")
        os.makedirs(logs, exist_ok=True)
        requests = []
        for request in options.test:
            if request == "newer":
                requests.extend((entry["name"], None) for entry in entries if entry["direct"] and entry["newer"])
            else:
                name, _, version = request.partition("@")
                requests.append((name, version or None))
        for name, version in requests:
            results.append(test_candidate(name, version, entries, platforms, options.keep, logs))
        lines += test_markdown(results)
    report = "\n".join(lines) + "\n"
    print(report)
    if options.report:
        os.makedirs(os.path.dirname(os.path.abspath(options.report)), exist_ok=True)
        with open(options.report, "w", encoding="utf-8") as handle:
            handle.write(report)
    behind = [entry["name"] for entry in entries if entry["newer"] and entry["direct"]]
    failed = [result["name"] for result in results if not result.get("passed")]
    if options.notify:
        if failed:
            notify("Dependency check", "Tests failed against: %s" % ", ".join(failed))
        elif behind:
            notify("Dependency check", "Newer releases: %s" % ", ".join(behind))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
