// Glass Project's (scripts/macvm/vmtool.swift), as Glass Power Tools uses it.
// Helper run INSIDE the macOS test VM, in the logged-in user's GUI (Aqua) session. Never run it on the host:
// `wallpaper set` changes the desktop picture of whatever Mac it runs on.
//
// Tools/Screenshots/macvm/macvm.sh compiles it in the VM (`swiftc`, Command Line Tools are in the Cirrus base image) and runs
// it through `macvm.sh gui …`, which puts it in the GUI session.
//
//   vmtool windows [owner]            on-screen windows (id, owner, pid, layer, bounds, title), for screencapture -l
//   vmtool wallpaper get              each screen's desktop picture (NSWorkspace.desktopImageURL(for:))
//   vmtool wallpaper set <file>       set it on every screen (setDesktopImageURL), then read it back
//   vmtool press <bundle-id|name|pid> <title>  press the first button, menu item, radio button or checkbox
//                                     with that title or description: in the windows, then the menu bar
//   vmtool place <app> x y w h [title]  move and size the app's front window, or its window with that title (points)
//   vmtool display [set WIDTHxHEIGHT]  list the main display's modes, or pick one by size in points (HiDPI if any)
//   vmtool ax <bundle-id|name|pid> [depth]
//                                     accessibility tree of the app's windows (role, title, description = the
//                                     VoiceOver label, identifier, value) and controls with no label at all
//
// Exit codes: 0 ok, 2 usage, 3 not trusted for Accessibility, 4 app not running, 5 wallpaper failed.
import AppKit
import ApplicationServices

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

// MARK: windows

func listWindows(owner: String?) {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    for window in info {
        let name = window[kCGWindowOwnerName as String] as? String ?? "?"
        if let owner, name != owner { continue }
        let id = window[kCGWindowNumber as String] as? Int ?? 0
        let pid = window[kCGWindowOwnerPID as String] as? Int ?? 0
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let title = window[kCGWindowName as String] as? String ?? ""
        let b = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        let bounds = "\(Int(b["X"] ?? 0)),\(Int(b["Y"] ?? 0)) \(Int(b["Width"] ?? 0))x\(Int(b["Height"] ?? 0))"
        print("\(id)\t\(name)\tpid=\(pid)\tlayer=\(layer)\t\(bounds)\t\(title)")
    }
}

// MARK: wallpaper

func screenName(_ screen: NSScreen, _ index: Int) -> String {
    "screen \(index) \(screen.localizedName) \(Int(screen.frame.width))x\(Int(screen.frame.height))@\(screen.backingScaleFactor)x"
}

func wallpaperGet() {
    for (index, screen) in NSScreen.screens.enumerated() {
        let url = NSWorkspace.shared.desktopImageURL(for: screen)?.path ?? "(none)"
        print("\(screenName(screen, index))\t\(url)")
    }
}

func wallpaperSet(_ path: String) {
    let file = URL(fileURLWithPath: path).standardizedFileURL
    guard FileManager.default.fileExists(atPath: file.path) else { fail("no such file: \(file.path)", 5) }
    var failed = false
    for (index, screen) in NSScreen.screens.enumerated() {
        do {
            // The options a wallpaper app would use.
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: true,
            ])
        } catch {
            print("\(screenName(screen, index))\tset failed: \(error.localizedDescription)")
            failed = true
            continue
        }
        // macOS 26 applies the change asynchronously (WallpaperAgent): desktopImageURL(for:) can report the old
        // picture for a second or two after setDesktopImageURL returns. Poll up to 10 s.
        var now = NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL
        let started = Date()
        while now != file, Date().timeIntervalSince(started) < 10 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            now = NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL
        }
        let ok = now == file
        let waited = String(format: "%.1f s", Date().timeIntervalSince(started))
        print("\(screenName(screen, index))\t\(now?.path ?? "(none)")\t\(ok ? "OK" : "MISMATCH") after \(waited)")
        if !ok { failed = true }
    }
    if failed { exit(5) }
}

// MARK: accessibility

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func text(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name) else { return nil }
    let string = (value as? String) ?? String(describing: value)
    let trimmed = string.replacingOccurrences(of: "\n", with: " ")
    return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
}

/// Roles a person operates; each needs a name VoiceOver can speak (title, description or a labelling element).
let controlRoles: Set<String> = [
    "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXTextField", "AXTextArea",
    "AXSlider", "AXComboBox", "AXLink", "AXImage", "AXSegmentedControl", "AXDisclosureTriangle", "AXIncrementor",
]

/// Window chrome VoiceOver names from the subrole ("close button"), so no label is expected.
let namedBySubrole: Set<String> = ["AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton"]

var unlabelled: [String] = []
var visited = 0

func walk(_ element: AXUIElement, depth: Int, maxDepth: Int, path: String) {
    visited += 1
    let role = text(element, kAXRoleAttribute) ?? "?"
    let subrole = text(element, kAXSubroleAttribute)
    let title = text(element, kAXTitleAttribute)
    let description = text(element, kAXDescriptionAttribute)
    let identifier = text(element, kAXIdentifierAttribute)
    let value = text(element, kAXValueAttribute)
    let labelledBy = attribute(element, "AXTitleUIElement") != nil || text(element, kAXPlaceholderValueAttribute) != nil
        || subrole.map(namedBySubrole.contains) == true
    var line = String(repeating: "  ", count: depth) + role
    if let subrole { line += "/\(subrole)" }
    if let title { line += " title=\"\(title)\"" }
    if let description { line += " desc=\"\(description)\"" }
    if let identifier { line += " id=\(identifier)" }
    if let value { line += " value=\"\(value)\"" }
    print(line)
    let here = "\(path)/\(role)"
    if controlRoles.contains(role), title == nil, description == nil, !labelledBy {
        unlabelled.append("\(here)\(identifier.map { " id=\($0)" } ?? "")")
    }
    guard depth < maxDepth, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
    for child in children { walk(child, depth: depth + 1, maxDepth: maxDepth, path: here) }
}

func findApp(_ query: String) -> NSRunningApplication? {
    if let pid = pid_t(query) { return NSRunningApplication(processIdentifier: pid) }
    if let app = NSRunningApplication.runningApplications(withBundleIdentifier: query).first { return app }
    return NSWorkspace.shared.runningApplications.first { $0.localizedName == query }
}

func audit(_ query: String, maxDepth: Int) {
    // Trust belongs to the "responsible" process: over SSH that's sshd-keygen-wrapper, which the Cirrus base image
    // grants Accessibility in the system TCC database (memory-bank/techContext.md, "The macOS screenshot VM").
    let trusted = AXIsProcessTrusted()
    print("AXIsProcessTrusted: \(trusted)")
    guard trusted else { fail("not trusted for Accessibility", 3) }
    guard let app = findApp(query) else { fail("not running: \(query)", 4) }
    print("app: \(app.localizedName ?? "?") \(app.bundleIdentifier ?? "?") pid=\(app.processIdentifier)")
    let element = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 3)
    let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    print("windows: \(windows.count)")
    for window in windows { walk(window, depth: 0, maxDepth: maxDepth, path: "") }
    print("elements: \(visited), controls without a label: \(unlabelled.count)")
    for item in unlabelled { print("  UNLABELLED \(item)") }
}

/// Depth-first search of the app's windows for a button whose title or description is `name`; presses it.
func press(_ query: String, _ name: String) {
    guard AXIsProcessTrusted() else { fail("not trusted for Accessibility", 3) }
    guard let app = findApp(query) else { fail("not running: \(query)", 4) }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 3)
    func search(_ element: AXUIElement, _ depth: Int) -> AXUIElement? {
        let role = text(element, kAXRoleAttribute) ?? ""
        let description = text(element, kAXDescriptionAttribute)
        // SwiftUI labels choices "Label, explanation"; the part before the comma is enough.
        if ["AXButton", "AXMenuItem", "AXRadioButton", "AXCheckBox"].contains(role),
           text(element, kAXTitleAttribute) == name || description == name
            || description?.hasPrefix(name + ",") == true {
            return element
        }
        guard depth < 12, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children { if let hit = search(child, depth + 1) { return hit } }
        return nil
    }
    // The app's windows first, then its menu bar (menu items, submenus included, press without opening).
    var places = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
    if let menuBar = attribute(root, kAXMenuBarAttribute) { places.append(menuBar as! AXUIElement) }
    guard let button = places.lazy.compactMap({ search($0, 0) }).first else { fail("no button \"\(name)\"", 4) }
    let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
    print(result == .success ? "pressed \"\(name)\"" : "press failed: \(result.rawValue)")
    if result != .success { exit(4) }
}

// MARK: window placement

// `place <app> x y width height` moves and sizes the app's front window (points, top-left origin), so screenshots
// are framed the same way every time.
func place(_ query: String, _ frame: [Double], title: String? = nil) {
    guard AXIsProcessTrusted() else { fail("not trusted for Accessibility", 3) }
    guard let app = findApp(query) else { fail("\(query) isn't running", 4) }
    let element = AXUIElementCreateApplication(app.processIdentifier)
    let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    // The front window, or the one titled so: raising a window by title doesn't always make it the front one. A
    // window's accessibility title can carry its subtitle after the one the window list shows ("alpha – ann@…").
    func titled(_ window: AXUIElement, _ title: String) -> Bool {
        guard let text = attribute(window, kAXTitleAttribute) as? String else { return false }
        return text == title || text.hasPrefix(title + " ")
    }
    guard let window = title.map({ title in windows.first { titled($0, title) } }) ?? windows.first else {
        fail("\(query) has no window\(title.map { " titled \($0)" } ?? "")", 4)
    }
    var origin = CGPoint(x: frame[0], y: frame[1]), size = CGSize(width: frame[2], height: frame[3])
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    print("placed \(query)'s window at \(Int(frame[0])),\(Int(frame[1])) \(Int(frame[2]))x\(Int(frame[3]))")
}

// MARK: display

// The guest picks its own screen mode whatever tart's --display says (it's a hint), so screenshots can come out
// at 1024×768. `display` lists the main display's modes; `display set 1920x1200` picks that size in points,
// HiDPI when there is such a mode, and keeps it.
func displayModes(set target: String?) {
    let id = CGMainDisplayID()
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
    let current = CGDisplayCopyDisplayMode(id)?.ioDisplayModeID
    guard let target else {
        for m in modes {
            print("\(m.width)x\(m.height) pt\t\(m.pixelWidth)x\(m.pixelHeight) px\(m.ioDisplayModeID == current ? "\tcurrent" : "")")
        }
        return
    }
    let size = target.split(separator: "x").compactMap { Int($0) }
    guard size.count == 2 else { fail("usage: vmtool display set WIDTHxHEIGHT (points)", 2) }
    guard let mode = modes.filter({ $0.width == size[0] && $0.height == size[1] })
        .max(by: { $0.pixelWidth < $1.pixelWidth }) else { fail("no \(target) mode; see vmtool display", 6) }
    var config: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&config)
    CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
    let error = CGCompleteDisplayConfiguration(config, .permanently)
    guard error == .success else { fail("display configuration failed: \(error.rawValue)", 6) }
    print("display: \(mode.width)x\(mode.height) pt, \(mode.pixelWidth)x\(mode.pixelHeight) px")
}

// MARK: main

let args = Array(CommandLine.arguments.dropFirst())
switch (args.first, args.dropFirst().first) {
case ("windows", let owner): listWindows(owner: owner)
case ("wallpaper", "get"): wallpaperGet()
case ("wallpaper", "set") where args.count == 3: wallpaperSet(args[2])
case ("ax", let query?): audit(query, maxDepth: args.count > 2 ? Int(args[2]) ?? 6 : 6)
case ("press", let query?) where args.count == 3: press(query, args[2])
case ("place", let query?) where args.count == 6: place(query, args.dropFirst(2).compactMap(Double.init))
case ("place", let query?) where args.count == 7: place(query, args[2...5].compactMap(Double.init), title: args[6])
case ("display", nil): displayModes(set: nil)
case ("display", "set") where args.count == 3: displayModes(set: args[2])
default:
    fail("usage: vmtool windows [owner] | wallpaper get | wallpaper set <file> | ax <bundle-id|name|pid> [depth] | "
        + "press <bundle-id|name|pid> <button title> | place <app> x y w h [title] | display [set WIDTHxHEIGHT]", 2)
}
