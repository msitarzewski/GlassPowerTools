#!/usr/bin/env python3
"""Builds the app's acknowledgements from Tools/Licenses/components.json.

- For every SwiftPM pin: checks that a checkout exists at the pinned revision and copies its
  LICENSE / NOTICE / COPYING files into Documentation/ThirdPartyLicenses/<id>/, with a REVISION
  file. With no checkout, the copies already there are used if their REVISION matches the pin.
- Merges Mermaid's own package list (Documentation/ThirdPartyLicenses/mermaid/bundled-packages.json,
  written by Tools/Mermaid/update-mermaid.sh).
- Writes Sources/GlassShell/Resources/Acknowledgements.json, which Settings ▸ About shows.

Usage: generate-acknowledgements.py [--check]
  --check  write nothing; exit 1 if the output would change.

AcknowledgementsTests fails when a pin, a vendored package or the Mermaid version is not covered.
"""
import glob
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LICENCES = os.path.join(ROOT, "Documentation", "ThirdPartyLicenses")
OUTPUT = os.path.join(ROOT, "Sources", "GlassShell", "Resources", "Acknowledgements.json")
MERMAID_PACKAGES = os.path.join(LICENCES, "mermaid", "bundled-packages.json")
LICENCE_FILE = re.compile(r"^(licen[cs]e|copying|notice)([.-].*)?$", re.IGNORECASE)


def fail(message):
    print(f"generate-acknowledgements: {message}", file=sys.stderr)
    sys.exit(2)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def checkout_dirs(url):
    name = url.rstrip("/").removesuffix(".git").split("/")[-1]
    candidates = [os.path.join(ROOT, ".build", "checkouts", name)]
    candidates += glob.glob(os.path.expanduser(
        f"~/Library/Developer/Xcode/DerivedData/GlassPowerTools-*/SourcePackages/checkouts/{name}"))
    return candidates


def head(path):
    result = subprocess.run(["git", "-C", path, "rev-parse", "HEAD"], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def pinned_texts(component, pin, check):
    """Copies a pin's licence files from its checkout, or trusts the copies already recorded."""
    folder = os.path.join(LICENCES, component["id"])
    revision = pin["state"]["revision"]
    checkout = next((c for c in checkout_dirs(pin["location"]) if head(c) == revision), None)
    extras = component.get("extraTexts", [])
    if checkout:
        names = sorted(n for n in os.listdir(checkout)
                       if LICENCE_FILE.match(n) and os.path.isfile(os.path.join(checkout, n)))
        if not names:
            fail(f"{component['id']}: no licence file in {checkout}")
        wanted = {n: os.path.join(checkout, n) for n in names}
        wanted.update({e["file"]: os.path.join(checkout, e["checkoutPath"]) for e in extras})
        if not check:
            os.makedirs(folder, exist_ok=True)
            for existing in os.listdir(folder):
                if existing not in wanted and existing != "REVISION":
                    os.remove(os.path.join(folder, existing))
            for name, source in wanted.items():
                # Replaced, not written over: checkout files are often read-only, and so are copies.
                destination = os.path.join(folder, name)
                if os.path.exists(destination):
                    os.remove(destination)
                shutil.copyfile(source, destination)
                os.chmod(destination, 0o644)
            with open(os.path.join(folder, "REVISION"), "w") as handle:
                handle.write(revision + "\n")
        texts = [{"title": n, "body": read(p).strip()} for n, p in sorted(wanted.items())
                 if n in names]
    else:
        recorded = os.path.join(folder, "REVISION")
        if not os.path.exists(recorded) or read(recorded).strip() != revision:
            fail(f"{component['id']}: no checkout at {revision[:12]} and the recorded copy is "
                 f"for another revision. Resolve packages (swift package resolve) and rerun.")
        names = sorted(n for n in os.listdir(folder) if LICENCE_FILE.match(n))
        texts = [{"title": n, "body": read(os.path.join(folder, n)).strip()} for n in names]
    for extra in extras:
        texts.append({"title": extra["title"], "body": read(os.path.join(folder, extra["file"])).strip()
                      if not checkout else read(os.path.join(checkout, extra["checkoutPath"])).strip()})
    return texts


def path_text(text):
    body = read(os.path.join(ROOT, text["path"]))
    if "lines" in text:
        first, last = text["lines"]
        lines = body.splitlines()[first - 1:last]
        body = "\n".join(re.sub(r"^\s*/?\*+/?\s?", "", line).rstrip() for line in lines)
    body = body.strip()
    if not body:
        fail(f"empty licence text: {text['path']}")
    return {"title": text["title"], "body": body}


def main():
    check = "--check" in sys.argv
    manifest = json.loads(read(os.path.join(ROOT, "Tools", "Licenses", "components.json")))
    pins = {p["identity"]: p for p in json.loads(read(os.path.join(ROOT, "Package.resolved")))["pins"]}
    components, seen_pins = [], set()
    for entry in manifest["components"]:
        component = {k: entry[k] for k in ("id", "name", "group", "license") }
        for key in ("note", "source", "revision"):
            if key in entry:
                component[key] = entry[key]
        if "pin" in entry:
            pin = pins.get(entry["pin"])
            if pin is None:
                fail(f"{entry['id']}: pin {entry['pin']} is not in Package.resolved")
            seen_pins.add(entry["pin"])
            component["source"] = pin["location"].removesuffix(".git")
            component["revision"] = pin["state"]["revision"]
            if pin["state"].get("version"):
                component["version"] = pin["state"]["version"]
            component["texts"] = pinned_texts(entry, pin, check)
        else:
            component["texts"] = [path_text(t) for t in entry["texts"]]
        if "versionFile" in entry:
            component["version"] = read(os.path.join(ROOT, entry["versionFile"])).strip()
        components.append(component)
    missing = sorted(set(pins) - seen_pins)
    if missing:
        fail("pins with no entry in Tools/Licenses/components.json: " + ", ".join(missing))

    mermaid = json.loads(read(MERMAID_PACKAGES))
    bundled_version = read(os.path.join(ROOT, "Sources/GlassEditor/Resources/Mermaid/VERSION")).strip()
    if mermaid["mermaid"] != bundled_version:
        fail(f"Mermaid's package list is for {mermaid['mermaid']}, the bundle is {bundled_version}. "
             "Run Tools/Mermaid/update-mermaid.sh.")
    for package in mermaid["packages"]:
        if package["name"] == "mermaid":
            continue
        licence = package["license"]
        if "elected" in package:
            licence = f"{licence} — {package['elected']} taken"
        components.append({"id": f"npm:{package['name']}", "name": package["name"],
                           "group": "Inside Mermaid", "license": licence,
                           "version": package["version"], "texts": package["texts"]})

    output = json.dumps({"components": components}, indent=1, ensure_ascii=False, sort_keys=True) + "\n"
    current = read(OUTPUT) if os.path.exists(OUTPUT) else None
    if check:
        if current != output:
            print("generate-acknowledgements: out of date — run Tools/Licenses/generate-acknowledgements.py",
                  file=sys.stderr)
            sys.exit(1)
        print("generate-acknowledgements: up to date")
        return
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    if current != output:
        with open(OUTPUT, "w", encoding="utf-8") as handle:
            handle.write(output)
    print(f"generate-acknowledgements: {len(components)} components")


if __name__ == "__main__":
    main()
