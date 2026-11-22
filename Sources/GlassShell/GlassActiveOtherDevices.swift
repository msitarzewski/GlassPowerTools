//
//  GlassActiveOtherDevices.swift
//  Glass Power Tools — GlassShell
//
//  Active's list of what your other devices have open (the shared layout, phase 1, 2026-11-22): each device's terminal
//  windows and their tabs, as that device published them. Listed only; nothing here opens them yet.
//

import SwiftUI

/// One other device: a disclosure over its windows, each with its tabs.
struct GlassActiveOtherDevice: View {
    let device: GlassLayoutDevice
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(device.windows) { window in
                VStack(alignment: .leading, spacing: 4) {
                    Label(window.name, systemImage: "macwindow")
                        .font(.body)
                    ForEach(window.tabs) { tab in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(tab.title)
                                .font(.callout)
                                .lineLimit(1)
                            Text(tab.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 28)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.vertical, 2)
                .glassSpatialListRow()
                .selectionDisabled()
                .accessibilityIdentifier("active-device-window-\(window.id.uuidString)")
            }
        } label: {
            HStack {
                Label("On \(device.name)", systemImage: "rectangle.on.rectangle")
                    .font(.headline)
                Spacer()
                Text(device.windows.count, format: .number)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("active-device-\(device.id)")
        }
    }
}
