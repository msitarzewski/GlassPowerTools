//
//  MacTmuxHostCopy.swift
//  Glass Power Tools — GlassTerminal
//
//  The host local terminals run in (D66) runs from a copy that no update replaces (D114, 2026-11-23). It ran from
//  the app itself, and an update replaced that under it: macOS's check of the running host then failed, and every
//  program in its terminals lost the app's folder permissions (Documents, Desktop and Downloads; reproduced in the
//  macOS VM, `MacTmuxHostCheck`). Telling the person at each update and offering to end every terminal was no
//  answer: the owner, shown it after an install, "Every quit CAN NOT DO THIS."
//
//  So the job runs a copy, made in Application Support and checked before it is used. It was the whole app bundle
//  (D114: 229 MB, its executable alone 179 MB, for a process that only waits on tmux), and the owner found that
//  "incredibly inefficient". Since 2026-11-24 (D115) it is the small app the host is, `Glass Power Tools Terminal
//  Host.app` in the app's `Contents/Helpers` (`MacTmuxHost`): the app's bundle ID, signed as the app is, so macOS
//  knows it as Glass Power Tools and its permissions are the app's (measured in the macOS VM: a bare program is
//  known by its path, a bundle by its ID and signature). The copy is `Glass Power Tools.app`, so a folder prompt it
//  causes names the app (`copyBundleName`). A copy's folder is named by its code's hash alone: an update that
//  leaves the helper as it was keeps its copy, and a changed helper gets a new one beside it. A running host keeps
//  its copy on disk and its terminals keep their permissions, and a server started after the update runs the new
//  one. Copies nothing runs from are removed at the app's start and when a server is started, the whole-app copies
//  earlier versions made among them. The folder ends in `.noindex` so Spotlight, and through it the list of apps,
//  leaves the copies out.
//

#if os(macOS)
import Darwin
import Foundation
import GlassTerminalHost
import os
import Security

nonisolated enum MacTmuxHostCopy {
    private static let logger = Logger(subsystem: "sh.glas", category: "local-tmux")

    /// Where the copies are kept.
    static func folder(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Glass Power Tools", isDirectory: true)
            .appendingPathComponent("Terminal Host.noindex", isDirectory: true)
    }

    /// The terminal host app's name in the app's `Contents/Helpers`, as the `GlassPowerToolsTerminalHost` target
    /// builds it.
    static let helperName = "Glass Power Tools Terminal Host.app"

    /// The terminal host app inside an app: its bundle, and its executable there.
    struct Helper: Equatable {
        let bundle: URL
        let executable: String
    }

    /// The terminal host app inside `app`; nil when it has none, as a test runner has none.
    static func helper(of app: Bundle) -> Helper? {
        guard app.bundleURL.pathExtension == "app" else { return nil }
        let bundle = app.bundleURL.appendingPathComponent("Contents/Helpers/\(helperName)", isDirectory: true)
        guard let executable = executable(inBundle: bundle) else { return nil }
        return Helper(bundle: bundle, executable: executable)
    }

    /// The executable of the bundle at `url`, from its Info.plist, when the bundle has one.
    static func executable(inBundle url: URL, fileManager: FileManager = .default) -> String? {
        guard let name = infoName("CFBundleExecutable", of: url, fileManager: fileManager) else { return nil }
        let path = url.appendingPathComponent("Contents/MacOS/\(name)").path
        return fileManager.isExecutableFile(atPath: path) ? path : nil
    }

    /// The name a copy of the bundle at `url` is given: its `CFBundleName` (the helper's is "Glass Power Tools"), or
    /// its own file name. A folder prompt names the program by its bundle's file name (measured in the macOS VM:
    /// "“Glass Power Tools Terminal Host” would like to access files in your Downloads folder", and the same signed
    /// helper renamed "Glass Power Tools.app" was asked for as Glass Power Tools), and the product can't carry the
    /// app's name in the build, beside the app itself. A bundle's file name isn't part of its signature.
    static func copyBundleName(of url: URL, fileManager: FileManager = .default) -> String {
        infoName("CFBundleName", of: url, fileManager: fileManager).map { "\($0).app" } ?? url.lastPathComponent
    }

    /// A name from the Info.plist of the bundle at `url`, when it can stand as one part of a path.
    private static func infoName(_ key: String, of url: URL, fileManager: FileManager) -> String? {
        guard let data = fileManager.contents(atPath: url.appendingPathComponent("Contents/Info.plist").path),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = info[key] as? String, !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return nil }
        return name
    }

    /// A copy's folder name: the start of its code's hash, so an unchanged helper keeps its copy through an update,
    /// and a changed one gets its own.
    static func copyName(codeHash: String) -> String {
        "host-\(codeHash.prefix(12))"
    }

    /// The hash macOS knows the code at `url` by (its CDHash), in hex; nil when it isn't signed.
    static func codeHash(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
              let unique = (information as? [String: Any])?[kSecCodeInfoUnique as String] as? Data else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the bundle at `url` is intact as signed, resources and all.
    static func isIntact(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
    }

    /// The executable of the copy of `helper` (a bundle), made in `folder` when missing and checked; nil when it can't
    /// be made or doesn't check, and the caller runs the helper where it is.
    static func executable(of helper: URL, in folder: URL, fileManager: FileManager = .default) -> String? {
        guard let hash = codeHash(of: helper), executable(inBundle: helper) != nil else { return nil }
        let name = copyName(codeHash: hash)
        let place = folder.appendingPathComponent(name, isDirectory: true)
        let bundleName = copyBundleName(of: helper, fileManager: fileManager)
        let copy = place.appendingPathComponent(bundleName, isDirectory: true)
        if !fileManager.fileExists(atPath: copy.path) {
            // Made beside its place and moved in whole, so a copy is never found half made.
            let making = folder.appendingPathComponent(".\(name).\(UUID().uuidString)", isDirectory: true)
            do {
                try fileManager.createDirectory(at: making, withIntermediateDirectories: true)
                // A clone on APFS (`copyfile`'s clone, which FileManager uses there).
                try fileManager.copyItem(at: helper, to: making.appendingPathComponent(bundleName))
                try fileManager.moveItem(at: making, to: place)
            } catch {
                try? fileManager.removeItem(at: making)
                if !fileManager.fileExists(atPath: copy.path) {
                    logger.error("The terminal host's copy could not be made: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        }
        guard codeHash(of: copy) == hash, isIntact(copy), let executable = executable(inBundle: copy) else {
            logger.error("The terminal host's copy doesn't check; it runs from the app")
            try? fileManager.removeItem(at: place)
            return nil
        }
        return executable
    }

    /// Copies run once in this process.
    private static let warmed = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    /// Runs the copy's executable once, to start and end (`MacTmuxHost.readyFlag`), unless it ran in this process.
    /// macOS scans a program the first time it runs, and for the whole app's copy (D114) that took 4.5 s in the VM:
    /// longer than a terminal waits for its server, so the server was started without the host. Run again, it started
    /// in 0.15 s.
    /// True when it ran and ended well.
    @discardableResult
    static func warm(_ executable: String,
                     run: (_ executable: String, _ arguments: [String]) -> String? = { MacLocalTmux.run($0, $1) }) -> Bool {
        if warmed.withLock({ $0.contains(executable) }) { return true }
        let started = ContinuousClock.now
        guard run(executable, [MacTmuxHost.readyFlag]) != nil else {
            logger.error("The terminal host's copy didn't start")
            return false
        }
        warmed.withLock { _ = $0.insert(executable) }
        logger.notice("The terminal host's copy ran once, in \(ContinuousClock.now - started, privacy: .public)")
        return true
    }

    /// Removes every copy in `folder` but `keeping` (folder names).
    static func removeCopies(in folder: URL, keeping: Set<String>, fileManager: FileManager = .default) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where !keeping.contains(name) {
            try? fileManager.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// Removes every copy in `folder` but `keeping` and those a running program runs from: a host started before
    /// an update runs from an earlier build's copy (a whole app's, before D115), and keeps it for as long as it runs. Nothing is removed when the
    /// running programs can't be listed: a running host's copy taken away fails macOS's check as an update did.
    static func removeUnusedCopies(in folder: URL, keeping: Set<String>,
                                   running: () -> [String]? = runningExecutables) {
        guard let inUse = copiesInUse(in: folder, running: running) else {
            logger.error("The running programs couldn't be listed; the terminal host's earlier copies stay")
            return
        }
        removeCopies(in: folder, keeping: keeping.union(inUse))
    }

    /// The copies in `folder` (folder names) that a running program runs from; nil when they can't be listed.
    static func copiesInUse(in folder: URL, running: () -> [String]? = runningExecutables) -> Set<String>? {
        running().map { Set($0.compactMap { copyName(of: $0, in: folder) }) }
    }

    /// The executable of every program running on this Mac that macOS lets this user see; nil when they can't be
    /// listed.
    static func runningExecutables() -> [String]? {
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return nil }
        // Room for programs started since it was counted.
        var pids = [pid_t](repeating: 0, count: Int(needed) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(Int(count)).compactMap { pid in
            guard pid > 0 else { return nil }
            return path.withUnsafeMutableBufferPointer { buffer -> String? in
                guard let base = buffer.baseAddress, proc_pidpath(pid, base, UInt32(buffer.count)) > 0 else { return nil }
                return String(cString: base)
            }
        }
    }

    /// The copy's folder name within `folder` that `executable` runs from; nil when it isn't one of them. macOS
    /// names a running program by its real path, so the folder is matched as written and with its links resolved.
    static func copyName(of executable: String, in folder: URL) -> String? {
        var bases = [folder.standardizedFileURL.path]
        if let resolved = realpath(folder.path, nil) {
            bases.append(String(cString: resolved))
            free(resolved)
        }
        for base in bases where executable.hasPrefix(base + "/") {
            return executable.dropFirst(base.count + 1).split(separator: "/").first.map(String.init)
        }
        return nil
    }
}
#endif
