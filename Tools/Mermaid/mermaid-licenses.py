#!/usr/bin/env python3
"""Lists the licence of every package inside a Mermaid release, for the app's acknowledgements.

`mermaid.min.js` is one file, but it is compiled from Mermaid and every package it depends on —
117 of them at 12.0.0 — and their licences travel with it. This walks an `npm install` of the
release and writes each package's name, version, licence and licence text.

Usage: mermaid-licenses.py <node_modules> <mermaid version> <output.json>
       mermaid-licenses.py --pin-embedded <list.json> <mermaid.min.js>

The second form corrects the list to the versions the bundle itself declares (2026-10-12). npm
resolves a dependency's range to its newest release, while the bundle carries the one Mermaid was
built with: the list said DOMPurify 3.4.16 for a bundle holding 3.4.12, and an advisory scan read
the wrong version from it.

Exit 3 when a package's licence is not one already reviewed below. The caller then keeps the
bundled Mermaid it has: a licence nobody has read does not ship.
"""
import json
import os
import re
import sys

# Licences reviewed for this bundle. A new one stops the update until someone reads it and adds it.
REVIEWED = {"MIT", "ISC", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "0BSD", "Unlicense",
            "EPL-2.0", "MPL-2.0 OR Apache-2.0", "EPL-2.0 OR GPL-3.0-or-later"}
# Where a package offers a choice, the licence taken.
ELECTED = {"EPL-2.0 OR GPL-3.0-or-later": "EPL-2.0", "MPL-2.0 OR Apache-2.0": "Apache-2.0"}
LICENCE_FILE = re.compile(r"^(licen[cs]e|copying|notice)([.-].*)?$", re.IGNORECASE)


def licence_of(meta, texts):
    value = meta.get("license") or meta.get("licenses")
    if isinstance(value, list):
        value = " OR ".join(v.get("type", "") if isinstance(v, dict) else str(v) for v in value)
    if isinstance(value, dict):
        value = value.get("type")
    if value:
        return re.sub(r"^\((.*)\)$", r"\1", value.strip())
    # Some packages publish a licence file but no metadata (khroma, at 12.0.0).
    joined = "\n".join(t["body"] for t in texts)
    if "Permission is hereby granted, free of charge" in joined:
        return "MIT"
    return "UNKNOWN"


# A bundled package's version, as the bundle states it.
EMBEDDED = {"dompurify": re.compile(r"DOMPurify (\d+\.\d+\.\d+)")}


def pin_embedded(list_path, bundle_path):
    with open(bundle_path, encoding="utf-8", errors="replace") as handle:
        bundle = handle.read()
    with open(list_path, encoding="utf-8") as handle:
        listing = json.load(handle)
    for entry in listing["packages"]:
        pattern = EMBEDDED.get(entry["name"])
        found = pattern.search(bundle) if pattern else None
        if found and found.group(1) != entry["version"]:
            print(f"mermaid-licenses: {entry['name']} {entry['version']} -> {found.group(1)}, as bundled")
            entry["version"] = found.group(1)
    with open(list_path, "w", encoding="utf-8") as handle:
        json.dump(listing, handle, indent=1, ensure_ascii=False, sort_keys=True)
        handle.write("\n")


def main():
    if sys.argv[1] == "--pin-embedded":
        pin_embedded(sys.argv[2], sys.argv[3])
        return
    root, version, output = sys.argv[1], sys.argv[2], sys.argv[3]
    packages, unreviewed = {}, []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d != ".bin"]
        # A package is `node_modules/<name>` or `node_modules/@scope/<name>`; anything deeper
        # holding a package.json is a package's own internals.
        parent = os.path.dirname(dirpath)
        is_package = os.path.basename(parent) == "node_modules" or (
            os.path.basename(parent).startswith("@")
            and os.path.basename(os.path.dirname(parent)) == "node_modules")
        if "package.json" not in filenames or not is_package:
            continue
        with open(os.path.join(dirpath, "package.json"), encoding="utf-8") as handle:
            meta = json.load(handle)
        name, pkg_version = meta.get("name"), meta.get("version")
        if not name or not pkg_version or (name, pkg_version) in packages:
            continue
        texts = []
        for filename in sorted(filenames):
            if LICENCE_FILE.match(filename):
                with open(os.path.join(dirpath, filename), encoding="utf-8", errors="replace") as handle:
                    texts.append({"title": filename, "body": handle.read().strip()})
        licence = licence_of(meta, texts)
        if licence not in REVIEWED:
            unreviewed.append(f"{name}@{pkg_version}: {licence}")
        entry = {"name": name, "version": pkg_version, "license": licence, "texts": texts}
        if licence in ELECTED:
            entry["elected"] = ELECTED[licence]
        packages[(name, pkg_version)] = entry
    result = {"mermaid": version,
              "packages": [packages[key] for key in sorted(packages)]}
    if unreviewed:
        print("mermaid-licenses: licence not yet reviewed — " + "; ".join(unreviewed), file=sys.stderr)
        sys.exit(3)
    with open(output, "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=1, ensure_ascii=False, sort_keys=True)
        handle.write("\n")
    print(f"mermaid-licenses: {len(packages)} packages in Mermaid {version}")


if __name__ == "__main__":
    main()
