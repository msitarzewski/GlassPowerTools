//
//  GlassSpotlight.swift
//  Glass Power Tools — GlassWidgetData
//
//  Machines and workgroups in the system's search — Spotlight, and what Siri knows — on every
//  platform (D72, 2026-10-13). **Off until switched on** (Settings ▸ Privacy ▸ Show Machines in
//  Search; B-F48 planned it opt-in), because it puts machine names in the system's on-device index.
//  Names and the kinds of service only: no address, user or credential. Choosing one opens it in the
//  library (`GlassOpenMachineIntent`, `GlassOpenWorkgroupIntent`).
//

import AppIntents
import CoreSpotlight
import Foundation
import os

extension GlassMachineEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        let kinds = GlassWidgetSnapshot.ServiceKind.allCases.filter { kind in services.contains { $0.kind == kind } }
        attributes.contentDescription = kinds.map(\.title).joined(separator: ", ")
        attributes.keywords = ["machine", "server"] + kinds.map { $0.title.lowercased() }
        return attributes
    }
}

extension GlassWorkgroupEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = name
        attributes.contentDescription = terminals == 1 ? "Workgroup · 1 terminal" : "Workgroup · \(terminals) terminals"
        attributes.keywords = ["workgroup", "terminal"]
        return attributes
    }
}

public enum GlassSpotlight {
    /// Settings ▸ Privacy ▸ Show Machines in Search. Off unless switched on.
    public static let settingKey = "com.glasspowertools.search.showsMachines"

    static let logger = Logger(subsystem: "sh.glas", category: "search")

    /// The index as the setting says: every machine and workgroup in `snapshot` when on — replacing
    /// whatever was there, so a removed machine leaves it — and nothing when off.
    public static func update(_ snapshot: GlassWidgetSnapshot?, enabled: Bool,
                              index: CSSearchableIndex = .default()) async {
        do {
            try await index.deleteAppEntities(ofType: GlassMachineEntity.self)
            try await index.deleteAppEntities(ofType: GlassWorkgroupEntity.self)
            guard enabled, let snapshot else { return }
            let machines = snapshot.machines.map(GlassMachineEntity.init)
            let workgroups = snapshot.workgroups.map(GlassWorkgroupEntity.init)
            if !machines.isEmpty { try await index.indexAppEntities(machines) }
            if !workgroups.isEmpty { try await index.indexAppEntities(workgroups) }
        } catch {
            logger.error("The search index could not be updated: \(String(describing: error), privacy: .public)")
        }
    }
}
