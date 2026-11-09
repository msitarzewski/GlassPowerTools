//
//  TerminalViewLifetimeTests.swift
//  Glass Power Tools — GlassTerminalTests
//
//  A closed terminal lets its SwiftTerm view go (2026-11-08). On iPhone, iPad and Vision Pro SwiftTerm's view runs
//  a display link whose target is the view itself, and the link holds its target until `updateUiClosed()`
//  invalidates it. Nothing called that, so every closed terminal kept its view, its `Terminal` and its whole
//  scrollback until the app quit. The Mac's view has no display link; the test runs there too, so it stays so.
//

import Foundation
import SwiftTerm
import SwiftUI
import Testing
import GlassTerminalEmulator
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@Suite("A closed terminal's view")
@MainActor
struct TerminalViewLifetimeTests {
    /// `explicitly`: closed as a session is (`releaseRenderer`), its model kept, as a closed session's can be.
    /// Otherwise only dropped, the model with it.
    @Test("a closed terminal's view is freed", arguments: [true, false])
    func closedTerminalViewIsFreed(explicitly: Bool) async throws {
        weak var view: TerminalView?
        weak var droppedModel: SwiftTermHostModel?
        var keptModel: SwiftTermHostModel?
        do {
            let model = SwiftTermHostModel()
            let host = HostedTerminal(SwiftTermHostView(
                model: model,
                theme: SwiftTermTheme(fontSize: 13, foreground: (1, 1, 1), background: (0, 0, 0, 1),
                                      cursor: (1, 1, 1)),
                runtimeSettings: SwiftTermRuntimeSettings(cursorStyle: "block", blinkingCursor: false,
                                                          scrollbackLines: 500),
                allowsFocusOwnership: false,
                onSendData: { _ in },
                onResize: { _, _ in }
            ))
            for _ in 0..<500 where !model.hasRetainedRenderer {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(model.hasRetainedRenderer, "the terminal was never drawn")
            model.ingest(data: Data("a line of scrollback\r\n".utf8), nonce: 1)
            for _ in 0..<500 where model.pendingRendererByteCount != 0 {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.pendingRendererByteCount == 0, "the terminal never took its output")
            view = try #require(host.terminalView(), "no SwiftTerm view in the hosted terminal")
            host.close()
            if explicitly {
                model.releaseRenderer()
                keptModel = model
            } else {
                droppedModel = model
            }
        }
        for _ in 0..<500 where view != nil || droppedModel != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(view == nil, "the closed terminal's SwiftTerm view is still alive")
        #expect(droppedModel == nil, "the dropped terminal's model is still alive")
        withExtendedLifetime(keptModel) {}
    }
}

/// A terminal in a window of its own, for as long as the test keeps it.
@MainActor
private final class HostedTerminal {
    #if canImport(UIKit)
    private var window: UIWindow?
    private var controller: UIHostingController<SwiftTermHostView>?

    init(_ root: SwiftTermHostView) {
        let controller = UIHostingController(rootView: root)
        controller.loadViewIfNeeded()
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.view.frame = frame
        // In the app's window scene when there is one; a package's test process has none.
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
            window.frame = frame
        } else {
            window = UIWindow(frame: frame)
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        self.window = window
        self.controller = controller
    }

    func terminalView() -> TerminalView? { Self.terminalView(in: controller?.view) }

    private static func terminalView(in view: UIView?) -> TerminalView? {
        guard let view else { return nil }
        if let terminal = view as? TerminalView { return terminal }
        for child in view.subviews { if let found = terminalView(in: child) { return found } }
        return nil
    }

    func close() {
        window?.isHidden = true
        window?.rootViewController = nil
        controller = nil
        window = nil
    }
    #else
    private var window: NSWindow?
    private var hosting: NSHostingView<SwiftTermHostView>?

    init(_ root: SwiftTermHostView) {
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 800, height: 600))
        hosting.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        self.window = window
        self.hosting = hosting
    }

    func terminalView() -> TerminalView? { Self.terminalView(in: hosting) }

    private static func terminalView(in view: NSView?) -> TerminalView? {
        guard let view else { return nil }
        if let terminal = view as? TerminalView { return terminal }
        for child in view.subviews { if let found = terminalView(in: child) { return found } }
        return nil
    }

    func close() {
        window?.contentView = nil
        window?.close()
        hosting = nil
        window = nil
    }
    #endif
}
