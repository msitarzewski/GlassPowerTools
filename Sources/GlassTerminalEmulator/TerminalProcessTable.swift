//
//  TerminalProcessTable.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  What this Mac's process table says about a terminal's foreground program (2026-10-14): its
//  process group, from the terminal's shell, and that group leader's command line — how a local
//  terminal tells which AI agent it runs (`TerminalAgent`, in GlassTerminal). Read-only, and only
//  for processes this user may already inspect.
//

#if os(macOS)
import Darwin
import Foundation

public enum TerminalProcessTable {
    /// The foreground process group of the terminal `shell` runs on: its controlling terminal's.
    public static func foregroundGroup(ofShell shell: pid_t) -> pid_t? {
        guard shell > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(shell, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        let group = pid_t(bitPattern: info.e_tpgid)
        return group > 0 ? group : nil
    }

    /// A process's command line, its arguments joined by spaces; nil where it cannot be read.
    public static func commandLine(of process: pid_t) -> String? {
        guard process > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, process]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        // argc, then the executable's path, padding NULs, then argc NUL-terminated arguments.
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        guard argc > 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }          // the executable path
        while index < size, buffer[index] == 0 { index += 1 }          // its padding
        var arguments: [String] = []
        while index < size, arguments.count < Int(argc) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments.isEmpty ? nil : arguments.joined(separator: " ")
    }
}
#endif
