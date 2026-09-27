#!/usr/bin/env python3
"""Copies Package.resolved's pins into the Xcode project's Package.resolved.

`swift package update` moves the package's pins; Xcode keeps its own copy and does not follow. They
drifted once (swift-crypto 3 in the app, 4 in the tests), and `PackagePinAgreementTests` now fails
when they differ. Run this after any `swift package update`, then
`xcodebuild -resolvePackageDependencies -project GlassPowerTools.xcodeproj -scheme GlassPowerTools`
to let Xcode check out what the pins name.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
XCODE = os.path.join(ROOT, "GlassPowerTools.xcodeproj", "project.xcworkspace", "xcshareddata",
                     "swiftpm", "Package.resolved")

with open(os.path.join(ROOT, "Package.resolved"), encoding="utf-8") as handle:
    package = json.load(handle)
with open(XCODE, encoding="utf-8") as handle:
    xcode = json.load(handle)
if xcode["pins"] == package["pins"]:
    print("sync-xcode-pins: already the same")
else:
    xcode["pins"] = package["pins"]
    with open(XCODE, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(xcode, indent=2, separators=(",", " : ")) + "\n")
    print("sync-xcode-pins: Xcode's pins now match Package.resolved")
