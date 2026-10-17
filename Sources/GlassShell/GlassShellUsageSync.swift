//
//  GlassShellUsageSync.swift
//  Glass Power Tools — GlassShell
//
//  How every device has been used, for the library's overview (D81; the owner, 2026-10-17: "I'd
//  also like to display the cross device use in the All Connections (no connection selected) pane.
//  Right now it's per device. So maybe totals, then a way to choose which device?"). D41 kept the
//  history on each device; what travels now is each device's name and its connections counted per
//  day, per machine and per kind of service, for the overview's 30 days — no times of day, nothing
//  else. Each device writes only its own entry, through the shell's iCloud key-value sync, as
//  favourites do; the history itself stays where it was made.
//

import Foundation
import GlassConnectionKit
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import SystemConfiguration
#endif

/// Every device's connections, counted per day, keyed by the device's writer id.
public struct GlassUsagePayload: Codable, Equatable, Sendable {
    /// One device: its name, when it last counted, and its counts.
    public struct Device: Codable, Equatable, Sendable {
        public var name: String
        public var updatedAt: Date
        /// The machines its counts name, each once; a count says which by its place here.
        public var hosts: [String]
        /// Counts by day, the day as the device's own calendar has it ("2026-10-17").
        public var days: [String: [Count]]

        public init(name: String, updatedAt: Date, hosts: [String] = [], days: [String: [Count]] = [:]) {
            self.name = name
            self.updatedAt = updatedAt
            self.hosts = hosts
            self.days = days
        }
    }

    /// Connections to one machine through one kind of service on one day. The kind is its raw
    /// value, so a kind a newer build adds is skipped here rather than failing the whole payload.
    public struct Count: Codable, Equatable, Sendable {
        public var host: Int
        public var kind: String
        public var count: Int

        public init(host: Int, kind: String, count: Int) {
            self.host = host
            self.kind = kind
            self.count = count
        }
    }

    /// The overview's window: what a device counts and sends.
    public static let days = 30
    public static let maximumDevices = 64
    public static let maximumHostsPerDevice = 2_000
    public static let maximumNameLength = 128

    public var devices: [String: Device]

    public init(devices: [String: Device] = [:]) { self.devices = devices }

    /// The day key for `date` in `calendar`.
    public static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The start of the day a key names, in `calendar`; nil for a key that names none.
    public static func day(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

extension GlassUsagePayload.Device {
    /// This device's entry, counted from its own history: the last `GlassUsagePayload.days` days.
    public init(name: String, history: [GlassShellPreferences.ConnectionEvent], now: Date = Date(),
                calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(GlassUsagePayload.days - 1), to: today) ?? today
        var hosts: [String] = []
        var index: [HostID: Int] = [:]
        var counts: [String: [String: Int]] = [:]   // day → "host|kind" → count
        for event in history where event.date >= start && event.date <= now {
            let slot: Int
            if let known = index[event.hostID] {
                slot = known
            } else {
                hosts.append(event.hostID.rawValue.uuidString)
                slot = hosts.count - 1
                index[event.hostID] = slot
            }
            counts[GlassUsagePayload.dayKey(event.date, calendar: calendar), default: [:]]["\(slot)|\(event.kind.rawValue)", default: 0] += 1
        }
        var days: [String: [GlassUsagePayload.Count]] = [:]
        for (day, byKey) in counts {
            days[day] = byKey.keys.sorted().compactMap { key in
                let parts = key.split(separator: "|", maxSplits: 1)
                guard parts.count == 2, let host = Int(parts[0]), let count = byKey[key] else { return nil }
                return GlassUsagePayload.Count(host: host, kind: String(parts[1]), count: count)
            }
        }
        self.init(name: name, updatedAt: now, hosts: hosts, days: days)
    }

    /// Its counts as the overview reads them: each day in `calendar`, each machine by its id. A
    /// count naming no machine, a day naming no date, or a kind this build has no name for is skipped.
    public func counts(calendar: Calendar = .current) -> [GlassUsageCount] {
        days.flatMap { key, counts -> [GlassUsageCount] in
            guard let date = GlassUsagePayload.day(key, calendar: calendar) else { return [] }
            return counts.compactMap { count in
                guard hosts.indices.contains(count.host), let uuid = UUID(uuidString: hosts[count.host]),
                      let kind = HostServiceKind(rawValue: count.kind), count.count > 0 else { return nil }
                return GlassUsageCount(date: date, hostID: HostID(rawValue: uuid), kind: kind, count: count.count)
            }
        }
    }
}

extension GlassUsagePayload: GlassSettingsSyncPayload {
    public func validate() throws {
        guard devices.count <= Self.maximumDevices else {
            throw GlassSettingsSyncError.invalidPayload("too many devices")
        }
        for (key, device) in devices {
            guard UUID(uuidString: key) != nil else {
                throw GlassSettingsSyncError.invalidPayload("a device has no id")
            }
            guard device.name.count <= Self.maximumNameLength,
                  device.hosts.count <= Self.maximumHostsPerDevice,
                  device.days.count <= Self.days * 2 else {
                throw GlassSettingsSyncError.invalidPayload("a device's counts are too large")
            }
            for counts in device.days.values {
                guard counts.allSatisfy({ device.hosts.indices.contains($0.host) && $0.count >= 0 }) else {
                    throw GlassSettingsSyncError.invalidPayload("a count names no machine")
                }
            }
        }
    }

    /// Each device's newest entry; on a tie, the one that sorts first by name, so every device
    /// reaches the same answer in either order.
    public func converged(with other: GlassUsagePayload) -> GlassUsagePayload {
        var merged = devices
        for (key, device) in other.devices {
            guard let mine = merged[key] else { merged[key] = device; continue }
            if device.updatedAt > mine.updatedAt
                || (device.updatedAt == mine.updatedAt && device.name < mine.name) {
                merged[key] = device
            }
        }
        return GlassUsagePayload(devices: merged)
    }
}

/// One count as the overview reads it.
public struct GlassUsageCount: Equatable, Sendable {
    public var date: Date
    public var hostID: HostID
    public var kind: HostServiceKind
    public var count: Int

    public init(date: Date, hostID: HostID, kind: HostServiceKind, count: Int) {
        self.date = date
        self.hostID = hostID
        self.kind = kind
        self.count = count
    }
}

/// A device's connections, for the overview's device choice: this device first, then the others.
public struct GlassDeviceUsage: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isThisDevice: Bool
    public var counts: [GlassUsageCount]

    public init(id: String, name: String, isThisDevice: Bool, counts: [GlassUsageCount]) {
        self.id = id
        self.name = name
        self.isThisDevice = isThisDevice
        self.counts = counts
    }
}

/// What the system calls this device, before anyone names it here. On a Mac, its computer name
/// ("Sharing" in System Settings). On iPhone, iPad and Vision Pro, the name the person gave it only
/// with Apple's user-assigned-device-name entitlement; without it the system answers with the model
/// ("iPhone"), which Settings ▸ General ▸ This Device can replace.
public enum GlassDeviceName {
    @MainActor
    public static var system: String {
        #if os(macOS)
        if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty { return name }
        return "Mac"
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #else
        return "This device"
        #endif
    }
}

extension GlassSettingsSyncService where Payload == GlassUsagePayload {
    static var usageStoreKey: String { "shell-usage-envelope-v1" }

    public convenience init(usageStore store: any GlassSettingsKeyValueStore, writerID: UUID = UUID()) {
        self.init(store: store, writerID: writerID, storeKey: Self.usageStoreKey)
    }
}
