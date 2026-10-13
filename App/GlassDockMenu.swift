//
//  GlassDockMenu.swift
//  Glass Power Tools
//
//  The Dock icon's menu (D72, 2026-10-13): New Terminal Window, then your favourite and recent
//  machines — a machine connects to its terminal, or its first service when it has none — read
//  from the snapshot the widgets read, and carried out as Siri's requests are.
//

#if os(macOS)
import AppKit
import GlassWidgetData

enum GlassDockMenu {
    /// How many machines the menu lists.
    static let machineLimit = 8

    @MainActor
    static func make(snapshot: GlassWidgetSnapshot? = GlassWidgetStore.read()) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("New Terminal Window", symbol: "terminal", request: .newLocalTerminal(folder: nil)))
        let machines = snapshot?.machines(limit: machineLimit) ?? []
        if !machines.isEmpty {
            menu.addItem(.separator())
            for machine in machines {
                guard let service = machine.services.first(where: { $0.kind == .terminal }) ?? machine.services.first else { continue }
                menu.addItem(item(machine.name, symbol: service.kind.symbolName,
                                  request: .connect(machine: machine.id, service: service.id)))
            }
        }
        return menu
    }

    @MainActor
    private static func item(_ title: String, symbol: String, request: GlassWidgetRequest) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(Target.perform(_:)), keyEquivalent: "")
        item.target = Target.shared
        item.representedObject = Box(request)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private final class Box: NSObject {
        let request: GlassWidgetRequest
        init(_ request: GlassWidgetRequest) { self.request = request }
    }

    @MainActor
    private final class Target: NSObject {
        static let shared = Target()
        @objc func perform(_ sender: NSMenuItem) {
            guard let box = sender.representedObject as? Box else { return }
            NSApp.activate()
            GlassWidgetRequests.shared.post(box.request)
        }
    }
}
#endif
