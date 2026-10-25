//
//  VisionTerminalPathPreviewer.swift
//  Glass Power Tools — GlassTerminalEmulator
//
//  A printed path's file in a popover over a Vision Pro terminal, as the Mac shows it
//  (`MacTerminalPathPreviewer`; the owner, 2026-10-22: "add Quick Look on the headset - even it if
//  has to be a mouse hover"). Quick Look leads a held path's menu; a trackpad or mouse pointer
//  resting on a path shows it, or Space while it rests there, as the window's Show previews says.
//  The eyes can't: visionOS tells an app nothing of where a person looks, only what they pinch.
//

#if os(visionOS)
import SwiftUI
import UIKit
import os

@MainActor
final class VisionTerminalPathPreviewer: NSObject, UIPopoverPresentationControllerDelegate {
    /// Where a preview stopped: the reason, never the path.
    private static let log = Logger(subsystem: "sh.glas", category: "path-preview")

    private weak var view: UIView?
    private let model: () -> SwiftTermHostModel?
    var mode: TerminalPathPreviews = .mouseover {
        didSet { if mode != oldValue { cancelPending() } }
    }
    /// How long the pointer rests on a path before its file shows, as on the Mac.
    static let restingTime: Duration = .milliseconds(600)
    /// The popover's size, as on the Mac: a page of text, or a picture at a size to read.
    static let size = CGSize(width: 560, height: 420)

    private var resting: Task<Void, Never>?
    private var restingPath: String?
    /// The path under the pointer now, and where: Space previews it, and a preview the pointer
    /// asked for shows only while the pointer is still on its path.
    private(set) var pointerPath: String?
    private var pointerPoint: CGPoint = .zero
    private weak var presented: UIViewController?
    private var shownFile: TerminalPreviewFile?
    /// Bumped by every preview asked for, so a slower one still fetching gives way to the newest.
    private var generation = 0

    init(view: UIView, model: @escaping () -> SwiftTermHostModel?) {
        self.view = view
        self.model = model
        super.init()
    }

    isolated deinit {
        resting?.cancel()
        shownFile?.discard?()
    }

    /// Whether this terminal can preview a file at all: its window wired both halves.
    var canPreview: Bool {
        guard let model = model() else { return false }
        return model.previewFile != nil && model.previewContent != nil
    }

    // MARK: The pointer

    /// The pointer is at `point` (in the view's coordinates), over `path` or over nothing.
    func pointer(at point: CGPoint, over path: String?) {
        pointerPath = path
        pointerPoint = point
        guard mode == .mouseover, let path, presented == nil else {
            if path == nil { cancelPending() }
            return
        }
        guard path != restingPath else { return }
        cancelPending()
        restingPath = path
        resting = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.restingTime)
            guard !Task.isCancelled, let self else { return }
            restingPath = nil
            await show(path: path, at: point, explicit: false)
        }
    }

    /// The pointer left the terminal.
    func pointerLeft() {
        pointerPath = nil
        cancelPending()
    }

    /// Space, with the pointer resting on a path and Show previews set to Mouseover + Space. True
    /// when it was taken.
    func spacePressed() -> Bool {
        guard mode == .mouseoverAndSpace, let path = pointerPath else { return false }
        if presented != nil {
            close()
            return true
        }
        Task { await show(path: path, at: pointerPoint, explicit: true) }
        return true
    }

    private func cancelPending() {
        resting?.cancel()
        resting = nil
        restingPath = nil
    }

    // MARK: The popover

    /// Shows the file `path` names beside `point`. `explicit` — Quick Look or Space — shows a
    /// spinner while a file on a server comes and says so when there is nothing to show; the
    /// pointer resting shows only a file it found, and only while the pointer is still on it.
    func show(path: String, at point: CGPoint, explicit: Bool) async {
        guard let view, let model = model(), let resolve = model.previewFile, let content = model.previewContent else {
            Self.log.error("event=show result=not-wired explicit=\(explicit, privacy: .public)")
            return
        }
        Self.log.notice("event=show asked explicit=\(explicit, privacy: .public)")
        generation &+= 1
        let mine = generation
        close()
        let controller = UIHostingController(rootView: framed(AnyView(ProgressView()), path: path, model: model))
        if explicit { present(controller, at: point, in: view) }

        let file = await resolve(path)
        guard mine == generation else {
            file?.discard?()
            return
        }
        guard let file else {
            Self.log.notice("event=show result=no-file explicit=\(explicit, privacy: .public)")
            if explicit, presented === controller {
                controller.rootView = framed(AnyView(ContentUnavailableView(
                    "No Preview", systemImage: "eye.slash",
                    description: Text("This file couldn't be read, or it's a folder or larger than 32 MB."))),
                    path: path, model: model)
            }
            return
        }
        if explicit {
            // Dismissed while the file came: nothing to show it in.
            guard presented === controller else {
                file.discard?()
                return
            }
        } else {
            // Still on the path, in a window still shown: the pointer may have moved on.
            guard pointerPath == path, view.window != nil else {
                Self.log.notice("event=show result=pointer-moved-on")
                file.discard?()
                return
            }
            present(controller, at: point, in: view)
        }
        shownFile = file
        controller.rootView = framed(content(file.url), path: path, model: model)
    }

    /// The preview under the shared bar: the file's name, Show in Files, Open in Editor.
    private func framed(_ content: AnyView, path: String, model: SwiftTermHostModel) -> AnyView {
        var open: (@MainActor () -> Void)?
        if let openPath = model.onOpenPath {
            open = { [weak self] in
                openPath(path)
                self?.close()
            }
        }
        var reveal: (@MainActor () -> Void)?
        if let revealPath = model.onRevealPath {
            reveal = { [weak self] in
                revealPath(path)
                self?.close()
            }
        }
        return AnyView(VStack(spacing: 0) {
            TerminalPreviewBar(name: (path as NSString).lastPathComponent, open: open,
                               revealTitle: model.revealPathTitle, reveal: reveal)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terminal-path-preview"))
    }

    private func present(_ controller: UIViewController, at point: CGPoint, in view: UIView) {
        guard let presenter = Self.presenter(for: view) else {
            Self.log.error("event=show result=no-presenter")
            return
        }
        controller.modalPresentationStyle = .popover
        controller.preferredContentSize = Self.size
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: point.x - 4, y: point.y - 8, width: 8, height: 16)
            popover.delegate = self
        }
        presenter.present(controller, animated: true)
        presented = controller
    }

    func close() {
        if let presented {
            presented.dismiss(animated: true)
            self.presented = nil
        }
        shownFile?.discard?()
        shownFile = nil
    }

    /// The view controller to present from: the nearest above the view, or what it presents.
    private static func presenter(for view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if var controller = current as? UIViewController {
                while let next = controller.presentedViewController { controller = next }
                return controller
            }
            responder = current.next
        }
        return nil
    }

    // MARK: UIPopoverPresentationControllerDelegate

    /// A popover, never a sheet.
    nonisolated func adaptivePresentationStyle(for controller: UIPresentationController,
                                               traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }

    /// Dismissed by a pinch elsewhere: its copy goes.
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        MainActor.assumeIsolated {
            presented = nil
            shownFile?.discard?()
            shownFile = nil
        }
    }
}
#endif
