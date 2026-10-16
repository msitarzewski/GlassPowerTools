//
//  MacTerminalPathPreviewer.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  A printed path's file in a popover over a Mac terminal (`TerminalPathPreview.swift`): from the
//  right-click menu's Quick Look, the pointer resting on the path, or Space while it does, as the
//  window's Show previews says. SwiftTerm's `mouseMoved` and `keyDown` can't be overridden from
//  here, so the pointer and the keys are watched on their way to the view, as scrolling is
//  (`MacAlternateScreenScrollWatcher`); Space is taken only with the pointer on a path or an address.
//

#if !canImport(UIKit) && canImport(AppKit)
import AppKit
import SwiftUI
import SwiftTerm

/// A Mac terminal view with a previewer, for its right-click menu's Quick Look.
@MainActor
protocol MacTerminalPreviewHolding: AnyObject {
    var pathPreviewer: MacTerminalPathPreviewer? { get }
}

@MainActor
final class MacTerminalPathPreviewer: NSObject, NSPopoverDelegate {
    private weak var view: TerminalView?
    private let model: () -> SwiftTermHostModel?
    var mode: TerminalPathPreviews = .mouseover {
        didSet { if mode != oldValue { cancelPending() } }
    }
    /// How long the pointer rests on a path before its file shows.
    static let restingTime: Duration = .milliseconds(600)
    /// The popover's size: a page of text, or a picture at a size to read.
    static let size = CGSize(width: 560, height: 420)

    private var monitor: Any?
    private var resting: Task<Void, Never>?
    private var restingPath: String?
    /// The cell the pointer was last over, for looking a link up once a cell.
    private var lastCell: Position?
    private var popover: NSPopover?
    private var shownPath: String?
    private var shownFile: TerminalPreviewFile?
    /// Opened by the pointer resting, and so closed by it moving off; Quick Look and Space wait to
    /// be dismissed.
    private var shownByResting = false
    /// Bumped by every preview asked for, so a slower one still fetching gives way to the newest.
    private var generation = 0
    /// Keeps a preview the pointer opened while the pointer is on its path or inside it.
    private var watching: Task<Void, Never>?
    /// How long the pointer may be off both before that preview closes: the way from the path to
    /// the popover crosses a little of the terminal (the owner, 2026-10-16: "Keep the hover open so
    /// the user can mouse into it and scroll where allowed").
    static let leaveGrace: Duration = .milliseconds(400)

    init(view: TerminalView, model: @escaping () -> SwiftTermHostModel?) {
        self.view = view
        self.model = model
        super.init()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .keyDown, .leftMouseDown, .scrollWheel]) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let taken = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return taken ? nil : event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        resting?.cancel()
        watching?.cancel()
        popover?.close()
        shownFile?.discard?()
    }

    /// Whether this terminal can preview a file at all: its window wired both halves.
    var canPreview: Bool {
        guard let model = model() else { return false }
        return model.previewFile != nil && model.previewContent != nil
    }

    // MARK: Events

    private func handle(_ event: NSEvent) -> Bool {
        guard let view, let window = view.window, !view.isHiddenOrHasHiddenAncestor else { return false }
        switch event.type {
        case .mouseMoved:
            guard event.window === window else { return false }
            pointerMoved(to: event.locationInWindow, in: view)
            return false
        case .keyDown:
            guard event.window === window else { return false }
            return keyDown(event, in: view)
        case .leftMouseDown, .scrollWheel:
            // A click or a scroll in the terminal's window: the preview has done its job.
            if event.window === window { close() }
            return false
        default:
            return false
        }
    }

    private func pointerMoved(to windowPoint: NSPoint, in view: TerminalView) {
        // Only the pointer resting opens one, so only it is followed; and a link is looked for once
        // a cell, not at every move of the pointer.
        guard mode == .mouseover else { return }
        let cell = view.bounds.contains(view.convert(windowPoint, from: nil))
            ? MacTerminalContextMenu.position(in: view, at: windowPoint) : nil
        guard cell?.col != lastCell?.col || cell?.row != lastCell?.row else { return }
        lastCell = cell
        let path: String? = cell.flatMap {
            guard case .path(let path)? = TerminalLinkLookup.target(at: $0, in: view.getTerminal()) else { return nil }
            return path
        }
        if let shownPath, path == shownPath { return }
        // Off the path, a preview the pointer opened stays a moment, so the pointer can reach it,
        // and then as long as it is inside it (`watchPointer`).
        guard let path, view.window?.isKeyWindow == true else {
            cancelPending()
            return
        }
        guard path != restingPath else { return }
        cancelPending()
        restingPath = path
        resting = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.restingTime)
            guard !Task.isCancelled, let self else { return }
            restingPath = nil
            await show(path: path, at: windowPoint, explicit: false)
        }
    }

    private func keyDown(_ event: NSEvent, in view: TerminalView) -> Bool {
        let space = Self.isPlainSpace(event)
        if popover != nil {
            // Space again closes it, as Quick Look's does; Escape too. Any other key closes it and
            // goes on to the terminal.
            close()
            return (space && mode == .mouseoverAndSpace) || event.keyCode == 53
        }
        guard space, mode == .mouseoverAndSpace, let window = view.window, window.firstResponder === view,
              !view.hasMarkedText() else { return false }
        let point = window.mouseLocationOutsideOfEventStream
        guard view.bounds.contains(view.convert(point, from: nil)),
              let target = MacTerminalContextMenu.link(in: view, at: point) else { return false }
        switch target {
        case .path(let path):
            Task { await show(path: path, at: point, explicit: true) }
            return true
        case .url(let url):
            // Asked as a ⌘-click asks, never shown: a web page is not this preview's to open.
            guard let model = model(), SwiftTermExternalLinkPolicy.validatedRequest(for: url.absoluteString) != nil else {
                return false
            }
            model.requestExternalLink(url.absoluteString)
            return true
        }
    }

    /// Space, with nothing held, not a key's repeat.
    static func isPlainSpace(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers == " " && !event.isARepeat
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    /// The path under `windowPoint`, as printed; nil on anything else, a web address included.
    private func path(in view: TerminalView, at windowPoint: NSPoint) -> String? {
        guard case .path(let path)? = MacTerminalContextMenu.link(in: view, at: windowPoint) else { return nil }
        return path
    }

    private func cancelPending() {
        resting?.cancel()
        resting = nil
        restingPath = nil
    }

    // MARK: The popover

    /// Shows the file `path` names beside `windowPoint`. `explicit` — Quick Look or Space — shows
    /// a spinner while a file on a server comes, and beeps when there is nothing to show; the
    /// pointer resting shows only a file it found, and only while the pointer is still on it.
    func show(path: String, at windowPoint: NSPoint, explicit: Bool) async {
        guard let view, let model = model(), let resolve = model.previewFile, let content = model.previewContent else {
            if explicit { NSSound.beep() }
            return
        }
        generation &+= 1
        let mine = generation
        close()
        let controller = NSHostingController(rootView: AnyView(ProgressView().frame(width: Self.size.width, height: Self.size.height)))
        if explicit { present(controller, at: windowPoint, in: view, path: path, byResting: false) }

        let file = await resolve(path)
        guard mine == generation else {
            file?.discard?()
            return
        }
        guard let file else {
            close()
            if explicit { NSSound.beep() }
            return
        }
        if explicit {
            // Dismissed while the file came: nothing to show it in.
            guard popover?.contentViewController === controller else {
                file.discard?()
                return
            }
        } else {
            // Still on the path, in a window still in front: the pointer may have moved on.
            guard let window = view.window, window.isKeyWindow, !view.isHiddenOrHasHiddenAncestor,
                  self.path(in: view, at: window.mouseLocationOutsideOfEventStream) == path else {
                file.discard?()
                return
            }
            present(controller, at: windowPoint, in: view, path: path, byResting: true)
        }
        shownFile = file
        controller.rootView = AnyView(content(file.url).frame(width: Self.size.width, height: Self.size.height))
    }

    private func present(_ controller: NSViewController, at windowPoint: NSPoint, in view: TerminalView,
                         path: String, byResting: Bool) {
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = Self.size
        popover.behavior = .semitransient
        popover.animates = true
        popover.delegate = self
        let point = view.convert(windowPoint, from: nil)
        popover.show(relativeTo: NSRect(x: point.x - 4, y: point.y - 8, width: 8, height: 16), of: view, preferredEdge: .maxY)
        self.popover = popover
        shownPath = path
        shownByResting = byResting
        if byResting { watchPointer(path: path, popover: popover) }
    }

    /// While the pointer is on `path` or inside `popover` — scrolling it, clicking in it — the
    /// preview stays; off both for `leaveGrace`, it closes. Looked at a few times a second, because
    /// inside the popover the terminal's window hears nothing of the pointer.
    private func watchPointer(path: String, popover: NSPopover) {
        watching?.cancel()
        watching = Task { @MainActor [weak self, weak popover] in
            var awaySince: ContinuousClock.Instant?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, let popover, popover === self.popover else { return }
                if pointerIsOn(path, or: popover) {
                    awaySince = nil
                } else if let since = awaySince {
                    if since.duration(to: .now) >= Self.leaveGrace {
                        close()
                        return
                    }
                } else {
                    awaySince = .now
                }
            }
        }
    }

    private func pointerIsOn(_ path: String, or popover: NSPopover) -> Bool {
        let mouse = NSEvent.mouseLocation
        if let frame = popover.contentViewController?.view.window?.frame, frame.insetBy(dx: -12, dy: -12).contains(mouse) {
            return true
        }
        guard let view, let window = view.window, !view.isHiddenOrHasHiddenAncestor else { return false }
        let windowPoint = window.convertPoint(fromScreen: mouse)
        guard view.bounds.contains(view.convert(windowPoint, from: nil)) else { return false }
        return self.path(in: view, at: windowPoint) == path
    }

    func close() {
        guard let closing = popover else { return }
        forget(closing)
        closing.close()
    }

    /// Closed by the system too: a click elsewhere closes a semitransient popover.
    func popoverDidClose(_ notification: Notification) {
        guard let closed = notification.object as? NSPopover else { return }
        forget(closed)
    }

    /// Lets go of `closing` and its file, once, whichever way it closed; a newer one is left be.
    private func forget(_ closing: NSPopover) {
        guard closing === popover else { return }
        watching?.cancel()
        watching = nil
        popover = nil
        shownPath = nil
        shownByResting = false
        let file = shownFile
        shownFile = nil
        file?.discard?()
    }
}
#endif
