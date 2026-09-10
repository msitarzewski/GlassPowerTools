#if os(macOS)
#if os(macOS)

//
//  SFTPFilePromiseDragSource.swift
//  glas.sh
//
//  Native Finder drag source for verified remote-file downloads.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Owns only a uniquely-created drop directory, including while a source is
/// still exporting after cancellation. Never deletes a source application's file.
final class SFTPDropStaging: @unchecked Sendable {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glas-sh-drop-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    nonisolated func owns(_ url: URL) -> Bool {
        url.isFileURL && url.resolvingSymlinksInPath().path.hasPrefix(
            directory.resolvingSymlinksInPath().path + "/"
        )
    }

    nonisolated static func filename(_ suggestion: String?, fallback: String) -> String {
        guard let suggestion, !suggestion.isEmpty, suggestion != ".", suggestion != "..",
              !suggestion.contains("/"), !suggestion.contains(":"),
              !suggestion.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return fallback }
        return suggestion
    }

    nonisolated func retainFile(_ source: URL, suggestedName: String?) throws -> URL {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard source.isFileURL, values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        var name = Self.filename(suggestedName, fallback: source.lastPathComponent)
        if (name as NSString).pathExtension.isEmpty, !source.pathExtension.isEmpty {
            name += "." + source.pathExtension
        }
        let target = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
}

@MainActor
final class SFTPIncomingDrop {
    static let acceptedTypes = NSFilePromiseReceiver.readableDraggedTypes
        + [UTType.fileURL.identifier, UTType.image.identifier, UTType.movie.identifier,
           UTType.pdf.identifier, UTType.plainText.identifier]

    private enum Source {
        case promise(NSFilePromiseReceiver)
        case file(URL)
        case provider(NSItemProvider)
    }
    private let sources: [Source]

    /// Snapshot the drag pasteboard synchronously, before another drag can replace it.
    /// AppKit chooses one representation per item, preferring its file promise.
    init?(providers: [NSItemProvider], pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        guard !PromiseRetention.shared.hasActivePromises else { return nil }
        let native = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self, NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) ?? []
        let sources: [Source] = native.compactMap {
            if let promise = $0 as? NSFilePromiseReceiver { return .promise(promise) }
            if let url = $0 as? URL, url.isFileURL { return .file(url) }
            return nil
        }
        self.sources = sources.isEmpty ? providers.map(Source.provider) : sources
        if self.sources.isEmpty { return nil }
    }

    func materialize() async throws -> (urls: [URL], staging: SFTPDropStaging) {
        let staging = try SFTPDropStaging()
        var urls: [URL] = []
        for source in sources {
            try Task.checkCancellation()
            switch source {
            case .file(let url):
                urls.append(url)
            case .promise(let receiver):
                let expected = max(receiver.fileNames.count, 1)
                let queue = OperationQueue()
                queue.name = "sh.glas.receive-file-promise"
                queue.maxConcurrentOperationCount = 1
                let stream = AsyncThrowingStream<URL, Error> { continuation in
                    receiver.receivePromisedFiles(atDestination: staging.directory, options: [:],
                                                  operationQueue: queue) { url, error in
                        // Retain staging for late callbacks even if the upload task cancels.
                        withExtendedLifetime(staging) {
                            if let error { continuation.finish(throwing: error) }
                            else { continuation.yield(url) }
                        }
                    }
                }
                var received = 0
                for try await url in stream {
                    try Task.checkCancellation()
                    guard staging.owns(url) else {
                        throw CocoaError(.fileReadNoPermission)
                    }
                    urls.append(url)
                    received += 1
                    if received == expected { break }
                }
            case .provider(let provider):
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    let stream = AsyncThrowingStream<URL, Error> { continuation in
                        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                            do {
                                if let error { throw error }
                                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil),
                                      url.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
                                let accessed = url.startAccessingSecurityScopedResource()
                                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                                continuation.yield(try staging.retainFile(url, suggestedName: nil))
                                continuation.finish()
                            } catch { continuation.finish(throwing: error) }
                        }
                    }
                    for try await url in stream { urls.append(url) }
                    continue
                }
                guard let identifier = provider.registeredTypeIdentifiers.first(where: {
                    guard let type = UTType($0) else { return false }
                    return type.conforms(to: .content) && !type.conforms(to: .url)
                }) else { throw CocoaError(.fileReadUnsupportedScheme) }
                let name = provider.suggestedName
                let stream = AsyncThrowingStream<URL, Error> { continuation in
                    provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
                        do {
                            if let error { throw error }
                            guard let url else { throw CocoaError(.fileReadUnknown) }
                            // NSItemProvider deletes its temporary file after this callback.
                            let retained = try staging.retainFile(url, suggestedName: name)
                            continuation.yield(retained)
                            continuation.finish()
                        } catch { continuation.finish(throwing: error) }
                    }
                }
                for try await url in stream { urls.append(url) }
            }
        }
        try Task.checkCancellation()
        return (urls, staging)
    }
}

actor SFTPFilePromiseTransferRegistry {
    private var acceptsTransfers = true
    private var activeTransfers: [UUID: Task<Void, Error>] = [:]

    func perform(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        try Task.checkCancellation()
        guard acceptsTransfers else { throw CancellationError() }

        let id = UUID()
        let transfer = Task {
            try await operation()
        }
        activeTransfers[id] = transfer
        defer { activeTransfers.removeValue(forKey: id) }

        try await withTaskCancellationHandler {
            try await transfer.value
        } onCancel: {
            transfer.cancel()
        }
    }

    func cancelAllAndWait() async {
        acceptsTransfers = false
        let transfers = Array(activeTransfers.values)
        transfers.forEach { $0.cancel() }
        for transfer in transfers {
            _ = await transfer.result
        }
    }
}

struct SFTPFilePromisePayload: Identifiable, Sendable {
    let id: String
    let filename: String
    let fileType: UTType
    let prepare: @Sendable () async -> Void
    let write: @Sendable (URL) async throws -> Void

    init(
        id: String,
        filename: String,
        fileType: UTType,
        prepare: @escaping @Sendable () async -> Void = {},
        write: @escaping @Sendable (URL) async throws -> Void
    ) {
        self.id = id
        self.filename = filename
        self.fileType = fileType
        self.prepare = prepare
        self.write = write
    }

    func fulfill(at destinationURL: URL) async throws {
        await prepare()
        try await PromiseWriteQueue.shared.perform {
            try await write(destinationURL)
        }
    }
}

struct SFTPFilePromiseDragSource: NSViewRepresentable {
    let payloads: [SFTPFilePromisePayload]

    func makeCoordinator() -> Coordinator {
        Coordinator(payloads: payloads)
    }

    func makeNSView(context: Context) -> AttachmentView {
        let view = AttachmentView()
        view.setAccessibilityElement(false)
        view.onHierarchyChange = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: AttachmentView, context: Context) {
        context.coordinator.payloads = payloads
        context.coordinator.attachIfNeeded(from: nsView)
    }

    static func dismantleNSView(_ nsView: AttachmentView, coordinator: Coordinator) {
        nsView.onHierarchyChange = nil
        coordinator.detach()
    }

    final class AttachmentView: NSView {
        var onHierarchyChange: (() -> Void)?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            onHierarchyChange?()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onHierarchyChange?()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSDraggingSource, NSGestureRecognizerDelegate {
        var payloads: [SFTPFilePromisePayload]

        private weak var attachedRow: NSView?
        private let panGesture: NSPanGestureRecognizer
        private var activePromiseIDs: [UUID] = []

        init(payloads: [SFTPFilePromisePayload]) {
            self.payloads = payloads
            panGesture = NSPanGestureRecognizer()
            super.init()
            panGesture.target = self
            panGesture.action = #selector(handlePan(_:))
            panGesture.delegate = self
            panGesture.buttonMask = 0x1
            panGesture.delaysPrimaryMouseButtonEvents = false
        }

        func attachIfNeeded(from marker: NSView) {
            guard let row = marker.firstAncestor(of: NSTableRowView.self),
                  row !== attachedRow else {
                return
            }
            detach()
            row.addGestureRecognizer(panGesture)
            attachedRow = row
        }

        func detach() {
            attachedRow?.removeGestureRecognizer(panGesture)
            attachedRow = nil
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            !payloads.isEmpty
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard gesture.state == .began,
                  let sourceView = gesture.view,
                  let event = NSApp.currentEvent,
                  event.type == .leftMouseDragged,
                  !payloads.isEmpty else {
                return
            }

            let queue = OperationQueue()
            queue.name = "sh.glas.file-promise"
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = 1

            let origin = gesture.location(in: sourceView)
            var promiseIDs: [UUID] = []
            let draggingItems = payloads.enumerated().map { index, payload in
                let promiseID = UUID()
                let delegate = PromiseDelegate(
                    id: promiseID,
                    payload: payload,
                    operationQueue: queue
                )
                PromiseRetention.shared.retain(delegate)
                promiseIDs.append(promiseID)

                let provider = NSFilePromiseProvider(
                    fileType: payload.fileType.identifier,
                    delegate: delegate
                )
                let item = NSDraggingItem(pasteboardWriter: provider)
                let image = NSWorkspace.shared.icon(for: payload.fileType)
                image.size = NSSize(width: 32, height: 32)
                let offset = CGFloat(min(index, 6)) * 3
                item.setDraggingFrame(
                    NSRect(
                        x: origin.x - 16 + offset,
                        y: origin.y - 16 - offset,
                        width: 32,
                        height: 32
                    ),
                    contents: image
                )
                return item
            }

            activePromiseIDs = promiseIDs
            let session = sourceView.beginDraggingSession(
                with: draggingItems,
                event: event,
                source: self
            )
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            if operation.isEmpty {
                activePromiseIDs.forEach { PromiseRetention.shared.release($0) }
            }
            activePromiseIDs.removeAll()
        }
    }
}

struct SFTPTableClickTarget: NSViewRepresentable {
    let delayedSingleClick: @MainActor (_ wasSelectedBeforeClick: Bool) -> Void
    let doubleClick: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            delayedSingleClick: delayedSingleClick,
            doubleClick: doubleClick
        )
    }

    func makeNSView(context: Context) -> SFTPFilePromiseDragSource.AttachmentView {
        let view = SFTPFilePromiseDragSource.AttachmentView()
        view.setAccessibilityElement(false)
        view.onHierarchyChange = { [weak coordinator = context.coordinator, weak view] in
            guard let coordinator, let view else { return }
            coordinator.attachIfNeeded(from: view)
        }
        return view
    }

    func updateNSView(
        _ nsView: SFTPFilePromiseDragSource.AttachmentView,
        context: Context
    ) {
        context.coordinator.delayedSingleClick = delayedSingleClick
        context.coordinator.doubleClick = doubleClick
        context.coordinator.attachIfNeeded(from: nsView)
    }

    static func dismantleNSView(
        _ nsView: SFTPFilePromiseDragSource.AttachmentView,
        coordinator: Coordinator
    ) {
        nsView.onHierarchyChange = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        var delayedSingleClick: @MainActor (_ wasSelectedBeforeClick: Bool) -> Void
        var doubleClick: @MainActor () -> Void

        private weak var attachedRow: NSTableRowView?
        private weak var markerView: NSView?
        private let singleClickGesture: SelectionTrackingClickGestureRecognizer
        private let doubleClickGesture: SelectionTrackingClickGestureRecognizer

        init(
            delayedSingleClick: @escaping @MainActor (_ wasSelectedBeforeClick: Bool) -> Void,
            doubleClick: @escaping @MainActor () -> Void
        ) {
            self.delayedSingleClick = delayedSingleClick
            self.doubleClick = doubleClick
            singleClickGesture = SelectionTrackingClickGestureRecognizer()
            doubleClickGesture = SelectionTrackingClickGestureRecognizer()
            super.init()
            singleClickGesture.target = self
            singleClickGesture.action = #selector(handleSingleClick(_:))
            singleClickGesture.numberOfClicksRequired = 1
            singleClickGesture.buttonMask = 0x1
            singleClickGesture.delaysPrimaryMouseButtonEvents = false
            singleClickGesture.delegate = self
            doubleClickGesture.target = self
            doubleClickGesture.action = #selector(handleDoubleClick(_:))
            doubleClickGesture.numberOfClicksRequired = 2
            doubleClickGesture.buttonMask = 0x1
            doubleClickGesture.delaysPrimaryMouseButtonEvents = false
            doubleClickGesture.delegate = self
        }

        func attachIfNeeded(from marker: NSView) {
            guard let row = marker.firstAncestor(of: NSTableRowView.self),
                  row !== attachedRow else {
                markerView = marker
                singleClickGesture.targetView = marker
                doubleClickGesture.targetView = marker
                return
            }
            detach()
            markerView = marker
            singleClickGesture.trackedRow = row
            singleClickGesture.targetView = marker
            doubleClickGesture.trackedRow = row
            doubleClickGesture.targetView = marker
            row.addGestureRecognizer(singleClickGesture)
            row.addGestureRecognizer(doubleClickGesture)
            attachedRow = row
        }

        func detach() {
            attachedRow?.removeGestureRecognizer(singleClickGesture)
            attachedRow?.removeGestureRecognizer(doubleClickGesture)
            attachedRow = nil
            markerView = nil
            singleClickGesture.trackedRow = nil
            singleClickGesture.targetView = nil
            doubleClickGesture.trackedRow = nil
            doubleClickGesture.targetView = nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            gestureRecognizer === singleClickGesture
                && otherGestureRecognizer === doubleClickGesture
        }

        @objc private func handleSingleClick(_ gesture: SelectionTrackingClickGestureRecognizer) {
            guard gesture.state == .ended, gesture.beganInsideTarget else { return }
            delayedSingleClick(gesture.wasSelectedBeforeMouseDown)
        }

        @objc private func handleDoubleClick(_ gesture: SelectionTrackingClickGestureRecognizer) {
            guard gesture.state == .ended, gesture.beganInsideTarget else { return }
            doubleClick()
        }
    }
}

@MainActor
private final class SelectionTrackingClickGestureRecognizer: NSClickGestureRecognizer {
    weak var trackedRow: NSTableRowView?
    weak var targetView: NSView?
    private(set) var wasSelectedBeforeMouseDown = false
    private(set) var beganInsideTarget = false

    override func mouseDown(with event: NSEvent) {
        wasSelectedBeforeMouseDown = trackedRow?.isSelected == true
        if let targetView {
            let point = targetView.convert(event.locationInWindow, from: nil)
            beganInsideTarget = targetView.bounds.contains(point)
        } else {
            beganInsideTarget = false
        }
        super.mouseDown(with: event)
    }
}

@MainActor
private final class PromiseRetention {
    static let shared = PromiseRetention()

    private var delegates: [UUID: PromiseDelegate] = [:]
    var hasActivePromises: Bool { !delegates.isEmpty }

    func retain(_ delegate: PromiseDelegate) {
        delegates[delegate.id] = delegate
    }

    func release(_ id: UUID) {
        delegates.removeValue(forKey: id)
    }
}

private final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    let id: UUID

    private let payload: SFTPFilePromisePayload
    private let operationQueue: OperationQueue

    init(
        id: UUID,
        payload: SFTPFilePromisePayload,
        operationQueue: OperationQueue
    ) {
        self.id = id
        self.payload = payload
        self.operationQueue = operationQueue
    }

    @MainActor
    func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        fileNameForType fileType: String
    ) -> String {
        payload.filename
    }

    nonisolated func filePromiseProvider(
        _ filePromiseProvider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let payload = payload
        let id = id
        let completion = PromiseCompletion(completionHandler)

        Task {
            do {
                try await payload.fulfill(at: url)
                completion.call(nil)
            } catch {
                completion.call(error)
            }
            await MainActor.run {
                PromiseRetention.shared.release(id)
            }
        }
    }

    @MainActor
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
        operationQueue
    }
}

private actor PromiseWriteQueue {
    static let shared = PromiseWriteQueue()

    private var tail: Task<Void, Never>?

    func perform(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let predecessor = tail
        let current = Task<Void, Error> {
            if let predecessor {
                await predecessor.value
            }
            try await operation()
        }
        tail = Task {
            _ = await current.result
        }
        try await current.value
    }
}

nonisolated private struct PromiseCompletion: @unchecked Sendable {
    let call: (Error?) -> Void

    init(_ call: @escaping (Error?) -> Void) {
        self.call = call
    }
}

private extension NSView {
    func firstAncestor<ViewType: NSView>(of type: ViewType.Type) -> ViewType? {
        var candidate = superview
        while let view = candidate {
            if let match = view as? ViewType {
                return match
            }
            candidate = view.superview
        }
        return nil
    }
}

#endif

#endif
