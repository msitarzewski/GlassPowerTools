import SwiftUI
import Combine
import SwiftTerm
#if canImport(UIKit)
import UIKit
#if canImport(MetalKit)
import MetalKit
#endif
#elseif canImport(AppKit)
import AppKit
import Darwin
import os
#endif

public enum SwiftTermRendererBackend: String, Equatable, Sendable {
    case awaitingWindow
    case metal
    case coreGraphics
    case coreGraphicsFallback
}

public enum SwiftTermRendererPreference: Equatable, Sendable {
    case coreGraphics
    case metal

    public static var platformDefault: Self {
        #if os(visionOS)
        // SwiftTerm's Metal view can report itself active on Vision Pro while
        // never presenting a drawable. Keep the proven UIKit renderer as the
        // device default until Metal presentation is validated independently.
        .coreGraphics
        #else
        .metal
        #endif
    }
}

public struct SwiftTermRendererDiagnostics: Equatable, Sendable {
    public let backend: SwiftTermRendererBackend
    public let isWindowAttached: Bool
    public let hostBackingIsClear: Bool?
    public let rendererBackingIsClear: Bool?
    public let failureDescription: String?

    public var preservesTransparentBacking: Bool? {
        guard let hostBackingIsClear else { return nil }
        guard hostBackingIsClear else { return false }
        guard backend == .metal else { return true }
        return rendererBackingIsClear
    }

    public static let awaitingWindow = SwiftTermRendererDiagnostics(
        backend: .awaitingWindow,
        isWindowAttached: false,
        hostBackingIsClear: nil,
        rendererBackingIsClear: nil,
        failureDescription: nil
    )
}

public struct SwiftTermPerformanceDiagnostics: Equatable, Sendable {
    public private(set) var lastOutputInstant: ContinuousClock.Instant?
    public private(set) var receivedChunkCount: UInt64 = 0
    public private(set) var receivedByteCount: UInt64 = 0
    public private(set) var emittedInputChunkCount: UInt64 = 0
    public private(set) var emittedInputByteCount: UInt64 = 0
    public private(set) var totalFeedDurationNanoseconds: UInt64 = 0
    public private(set) var maximumFeedDurationNanoseconds: UInt64 = 0

    public var averageFeedDurationNanoseconds: UInt64 {
        guard receivedChunkCount > 0 else { return 0 }
        return totalFeedDurationNanoseconds / receivedChunkCount
    }

    public init() {}

    fileprivate mutating func recordFeed(byteCount: Int, duration: Duration) {
        if byteCount > 0 { lastOutputInstant = .now }
        receivedChunkCount = Self.saturatingAdd(receivedChunkCount, 1)
        receivedByteCount = Self.saturatingAdd(receivedByteCount, Self.nonnegativeUInt64(byteCount))
        let nanoseconds = Self.nanoseconds(in: duration)
        totalFeedDurationNanoseconds = Self.saturatingAdd(totalFeedDurationNanoseconds, nanoseconds)
        maximumFeedDurationNanoseconds = max(maximumFeedDurationNanoseconds, nanoseconds)
    }

    fileprivate mutating func recordInput(byteCount: Int) {
        emittedInputChunkCount = Self.saturatingAdd(emittedInputChunkCount, 1)
        emittedInputByteCount = Self.saturatingAdd(emittedInputByteCount, Self.nonnegativeUInt64(byteCount))
    }

    private static func nanoseconds(in duration: Duration) -> UInt64 {
        let components = duration.components
        guard components.seconds >= 0, components.attoseconds >= 0 else { return 0 }
        let seconds = UInt64(components.seconds)
        let attoseconds = UInt64(components.attoseconds)
        return saturatingAdd(
            saturatingMultiply(seconds, 1_000_000_000),
            attoseconds / 1_000_000_000
        )
    }

    private static func nonnegativeUInt64(_ value: Int) -> UInt64 {
        value > 0 ? UInt64(value) : 0
    }

    private static func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : result
    }

    private static func saturatingMultiply(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? .max : result
    }
}

/// Version 1 contains only values SwiftTerm's public delegate reports. SwiftTerm
/// 1.13 does not report OSC 133 prompt, command-boundary, or exit-status values,
/// so this schema deliberately has no cases for those unsupported semantics.
public enum SwiftTermSemanticEventKind: Equatable, Sendable {
    case workingDirectoryChanged(directory: String?)
    case fileReference(SwiftTermFileReference)
    case unhandledITermContent(command: String?, contentByteCount: Int)
    case displayRangeChanged(startY: Int, endY: Int)
    case osc52Denied(SwiftTermOSC52Decision)
}

public struct SwiftTermSemanticEvent: Identifiable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let sequence: UInt64
    public let kind: SwiftTermSemanticEventKind

    public var id: UInt64 { sequence }

    fileprivate init(sequence: UInt64, kind: SwiftTermSemanticEventKind) {
        self.schemaVersion = Self.currentSchemaVersion
        self.sequence = sequence
        self.kind = kind
    }
}

/// Metadata from an unhandled iTerm2 OSC 1337 `File` request. The encoded
/// payload is intentionally not retained or decoded by this event flow.
public struct SwiftTermFileReference: Equatable, Sendable {
    public let suggestedName: String?
    public let declaredByteCount: UInt64?
    public let encodedPayloadByteCount: Int
    public let requestsInlineDisplay: Bool
}

public enum SwiftTermOSC52Disposition: String, Equatable, Sendable {
    case deniedWrite
    case deniedReadQuery
    case deniedUnsupportedSelection
    case rejectedMalformed
    case rejectedOversized
}

public struct SwiftTermOSC52Decision: Equatable, Sendable {
    public static let schemaVersion = 1

    public let disposition: SwiftTermOSC52Disposition
    public let requestByteCount: Int
    public let encodedPayloadByteCount: Int?
}

public enum SwiftTermOSC52Policy {
    /// Equivalent to a maximum decoded payload of 256 KiB, including Base64 expansion.
    public static let maximumEncodedPayloadBytes = 349_528

    public static func evaluate(_ request: ArraySlice<UInt8>) -> SwiftTermOSC52Decision {
        guard request.count <= maximumEncodedPayloadBytes + 2 else {
            return decision(.rejectedOversized, request: request, payloadByteCount: nil)
        }
        guard let separator = request.firstIndex(of: UInt8(ascii: ";")) else {
            return decision(.rejectedMalformed, request: request, payloadByteCount: nil)
        }

        let selection = request[..<separator]
        let payload = request[request.index(after: separator)...]
        if payload.elementsEqual([UInt8(ascii: "?")]) {
            return decision(.deniedReadQuery, request: request, payloadByteCount: 1)
        }
        guard selection.elementsEqual([UInt8(ascii: "c")]) else {
            return decision(
                .deniedUnsupportedSelection,
                request: request,
                payloadByteCount: payload.count
            )
        }
        guard payload.count <= maximumEncodedPayloadBytes else {
            return decision(
                .rejectedOversized,
                request: request,
                payloadByteCount: payload.count
            )
        }
        guard isValidBase64(payload) else {
            return decision(
                .rejectedMalformed,
                request: request,
                payloadByteCount: payload.count
            )
        }
        return decision(.deniedWrite, request: request, payloadByteCount: payload.count)
    }

    private static func decision(
        _ disposition: SwiftTermOSC52Disposition,
        request: ArraySlice<UInt8>,
        payloadByteCount: Int?
    ) -> SwiftTermOSC52Decision {
        SwiftTermOSC52Decision(
            disposition: disposition,
            requestByteCount: request.count,
            encodedPayloadByteCount: payloadByteCount
        )
    }

    private static func isValidBase64(_ payload: ArraySlice<UInt8>) -> Bool {
        guard payload.count.isMultiple(of: 4) else { return false }
        var paddingCount = 0
        for byte in payload.reversed() where byte == UInt8(ascii: "=") {
            paddingCount += 1
        }
        guard paddingCount <= 2 else { return false }
        let dataEnd = payload.index(payload.endIndex, offsetBy: -paddingCount)
        guard payload[..<dataEnd].allSatisfy({ byte in
            (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || byte == UInt8(ascii: "+")
                || byte == UInt8(ascii: "/")
        }) else { return false }
        return payload[dataEnd...].allSatisfy { $0 == UInt8(ascii: "=") }
    }
}

public enum SwiftTermITermContentPolicy {
    public static let maximumSuggestedNameBytes = 4_096
    public static let maximumMetadataBytes = 16_384

    public static func semanticEventKind(
        for content: ArraySlice<UInt8>
    ) -> SwiftTermSemanticEventKind {
        let contentByteCount = content.count
        let metadataPrefix = content.prefix(maximumMetadataBytes + 1)
        guard let colonIndex = metadataPrefix.firstIndex(of: UInt8(ascii: ":")),
              content.distance(from: content.startIndex, to: colonIndex) <= maximumMetadataBytes else {
            return .unhandledITermContent(
                command: commandName(in: content),
                contentByteCount: contentByteCount
            )
        }

        let header = content[..<colonIndex]
        guard header.starts(with: Array("File=".utf8)) else {
            return .unhandledITermContent(
                command: commandName(in: header),
                contentByteCount: contentByteCount
            )
        }

        let optionBytes = header.dropFirst("File=".utf8.count)
        guard let optionString = String(bytes: optionBytes, encoding: .utf8) else {
            return .unhandledITermContent(
                command: "File",
                contentByteCount: contentByteCount
            )
        }
        let options = optionString
            .split(separator: ";", omittingEmptySubsequences: true)
            .reduce(into: [String: String]()) { result, part in
                let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pair.count == 2 else { return }
                result[String(pair[0])] = String(pair[1])
            }

        return .fileReference(
            SwiftTermFileReference(
                suggestedName: decodedSuggestedName(options["name"]),
                declaredByteCount: options["size"].flatMap(UInt64.init),
                encodedPayloadByteCount: content.distance(
                    from: content.index(after: colonIndex),
                    to: content.endIndex
                ),
                requestsInlineDisplay: options["inline"] == "1"
            )
        )
    }

    private static func commandName(in content: ArraySlice<UInt8>) -> String? {
        let boundedPrefix = content.prefix(65)
        let boundary = boundedPrefix.firstIndex { byte in
            byte == UInt8(ascii: "=") || byte == UInt8(ascii: ";") || byte == UInt8(ascii: ":")
        } ?? boundedPrefix.endIndex
        let bytes = boundedPrefix[..<boundary]
        guard !bytes.isEmpty, bytes.count <= 64,
              let command = String(bytes: bytes, encoding: .utf8) else { return nil }
        return command
    }

    private static func decodedSuggestedName(_ value: String?) -> String? {
        guard let value,
              let encoded = value.data(using: .utf8),
              encoded.count <= maximumSuggestedNameBytes * 2,
              let decoded = Data(base64Encoded: encoded),
              !decoded.isEmpty,
              decoded.count <= maximumSuggestedNameBytes,
              let name = String(data: decoded, encoding: .utf8),
              !name.unicodeScalars.contains(where: { scalar in
                  switch scalar.properties.generalCategory {
                  case .control, .format, .lineSeparator, .paragraphSeparator:
                      return true
                  default:
                      return false
                  }
              }) else { return nil }
        return name
    }
}

@MainActor
public final class SwiftTermHostModel: ObservableObject {
    /// Presentation-only zoom belongs to the live terminal, not the saved theme.
    @Published public private(set) var fontSizeOverride: CGFloat?

    public func resolvedFontSize(defaultSize: CGFloat) -> CGFloat {
        fontSizeOverride ?? defaultSize
    }

    public func adjustFontSize(by delta: CGFloat, defaultSize: CGFloat) {
        fontSizeOverride = min(72, max(10, resolvedFontSize(defaultSize: defaultSize) + delta))
    }

    public func resetFontSize() {
        fontSizeOverride = nil
    }

    public static let semanticEventHistoryLimit = 256
    /// Remote output can arrive before SwiftUI installs the first platform
    /// renderer. Bound that short bootstrap window so an untrusted host cannot
    /// grow process memory without limit.
    public static let maximumPendingRendererBytes = 4 * 1_024 * 1_024

    @Published public private(set) var currentDirectory: String?
    /// Told that output arrived, at most four times a second — a tab's activity indicator
    /// (2026-10-07). Not published: the listener keeps its own state.
    public var onOutputActivity: (@MainActor () -> Void)?
    private var lastOutputActivity: ContinuousClock.Instant?

    fileprivate func noteOutputActivity() {
        guard let onOutputActivity else { return }
        let now = ContinuousClock.now
        if let last = lastOutputActivity, now - last < .milliseconds(250) { return }
        lastOutputActivity = now
        onOutputActivity()
    }

    /// The title the remote shell or program set (OSC 0/2): "user@host: ~/src" from Ubuntu's
    /// default prompt, a file name from vim. Nil until one is set. Names the terminal's tab.
    ///
    /// Not published. Programs animate it — Claude Code's spinner changes it several times a
    /// second — and every published change re-renders each view observing this model: the whole
    /// terminal window, its toolbar and ornaments. Only a tab that names itself listens.
    public private(set) var terminalTitle: String?
    public var onTerminalTitleChange: (@MainActor (String?) -> Void)?

    /// Scrolling over a full-screen program that asked for no mouse, which a terminal otherwise
    /// sends as arrow keys — in tmux, Claude Code then steps through its earlier messages. A
    /// listener that takes it returns true: a local tmux pane scrolls tmux's own history instead
    /// (2026-10-08). `deltaY` is positive toward earlier output; `precise` means points, else lines.
    public var onAlternateScreenScroll: (@MainActor (_ deltaY: CGFloat, _ precise: Bool) -> Bool)?
    /// Everything a full-screen program keeps that the terminal does not, as text: a tmux
    /// session's history and screen, which never reach the terminal because tmux draws on the
    /// alternate screen. Select All on the Mac takes it, so Copy copies all of it (2026-10-11).
    public var onFullHistory: (@MainActor () async -> String?)?
    /// Watch Log File, on a path the terminal shows (`MacTerminalContextMenu`, 2026-10-14): the
    /// path as written — absolute, `~/…`, `$VAR/…` or relative to the shell's folder — for the
    /// host to follow in a tab of its own, on the same machine. Nil where the host cannot, and the
    /// menu leaves it out.
    public var onWatchFile: (@MainActor (String) -> Void)?
    @Published public private(set) var scrollPosition: Double = 1
    @Published public private(set) var pendingPasteReview: SwiftTermPasteReview?
    @Published public private(set) var pendingExternalLink: SwiftTermExternalLinkRequest?
    public private(set) var rendererDiagnostics = SwiftTermRendererDiagnostics.awaitingWindow
    public private(set) var semanticEvents: [SwiftTermSemanticEvent] = []
    public let semanticEventPublisher = PassthroughSubject<SwiftTermSemanticEvent, Never>()
    /// The emulator belongs to the live terminal session, not to a transient
    /// SwiftUI representable. Keeping this reference strong preserves the
    /// terminal buffer while adaptive tabs and sidebars reconstruct views.
    private weak var terminalEngine: (any TerminalEngine)?
    private var retainedRemoteEngine: (any TerminalEngine)?
    private var rendererDelegateOwner: AnyObject?
    private var attachedViewID: ObjectIdentifier?
    private var pendingChunks: [Data] = []
    private var pendingFlushTask: Task<Void, Never>?
    public private(set) var pendingRendererByteCount = 0
    public private(set) var droppedPendingRendererByteCount = 0
    private var lastNonce: UInt64 = 0
    private var focusRetryTask: Task<Void, Never>?
    public private(set) var allowsFocusOwnership = true
    private var nextSemanticEventSequence: UInt64 = 1

    /// Whether the terminal's keyboard accessory — Dismiss, Tools, the cursor pad, Keys — is on
    /// screen: with the software keyboard, or alone at the bottom of the screen while a hardware
    /// keyboard is in use. Told by the accessory itself as it joins or leaves a window, so no
    /// keyboard frame has to be converted between screens: on a folded iPhone Duo that conversion
    /// missed, and the terminal's own Tools stayed on screen above the accessory's (2026-10-12).
    @Published public private(set) var keyboardAccessoryShown = false

    func keyboardAccessoryMoved(shown: Bool) {
        if keyboardAccessoryShown != shown { keyboardAccessoryShown = shown }
    }

    #if os(iOS)
    private var keyboardToolsView: (UIView & UIContentView)?

    /// Keep application actions in the terminal's existing native accessory.
    public func setKeyboardTools<Content: View>(_ content: Content) {
        let configuration = UIHostingConfiguration { content }.margins(.all, 0)
        if let keyboardToolsView {
            keyboardToolsView.configuration = configuration
        } else {
            keyboardToolsView = configuration.makeContentView()
            keyboardToolsView?.backgroundColor = .clear
        }
        installKeyboardTools()
    }

    public func clearKeyboardTools() {
        keyboardToolsView?.removeFromSuperview()
        keyboardToolsView = nil
        installKeyboardTools()
    }

    public func keyboardOverlapsHost(_ screenFrame: CGRect) -> Bool {
        guard let view = terminalEngine?.hostView, let window = view.window,
              allowsFocusOwnership else { return false }
        let frame = window.convert(screenFrame, from: window.screen.coordinateSpace)
        return window.bounds.intersection(frame).height > 0
    }

    private func installKeyboardTools() {
        func visit(_ view: UIView) {
            if let accessory = view.inputAccessoryView as? MinimalTerminalAccessoryView {
                accessory.setToolsView(keyboardToolsView)
            }
            for child in view.subviews { visit(child) }
        }
        if let view = terminalEngine?.hostView { visit(view) }
    }
    #endif


    public init() {}

    public var hasRetainedRenderer: Bool {
        retainedRemoteEngine != nil
    }

    fileprivate func retainedRenderer() -> (any TerminalEngine)? {
        retainedRemoteEngine
    }

    fileprivate func retainedDelegate<Delegate: AnyObject>(
        as type: Delegate.Type
    ) -> Delegate? {
        rendererDelegateOwner as? Delegate
    }

    fileprivate func attach(
        _ engine: any TerminalEngine,
        delegateOwner: AnyObject
    ) {
        retainedRemoteEngine = engine
        terminalEngine = engine
        rendererDelegateOwner = delegateOwner
        #if os(iOS)
        installKeyboardTools()
        #endif
        let viewID = engine.identity
        guard attachedViewID != viewID else {
            return
        }
        attachedViewID = viewID
        publishRendererDiagnosticsIfChanged(engine.rendererDiagnostics)
        schedulePendingFlush()
        focus()
    }

    /// Local PTY renderers retain their engine through
    /// `SwiftTermLocalProcessRuntime`; keep this non-owning attachment so the
    /// established explicit local-process teardown remains authoritative.
    fileprivate func attach(_ engine: any TerminalEngine) {
        terminalEngine = engine
        #if canImport(UIKit)
        engine.onLeavingWindow = { [weak self] in self?.rememberPreview() }
        #endif
        let viewID = engine.identity
        guard attachedViewID != viewID else { return }
        attachedViewID = viewID
        publishRendererDiagnosticsIfChanged(engine.rendererDiagnostics)
        schedulePendingFlush()
        focus()
    }

    /// Explicit terminal-close authority releases the renderer and its complete
    /// in-memory scrollback. View disappearance intentionally never calls this.
    public func releaseRenderer() {
        #if os(iOS)
        clearKeyboardTools()
        #endif
        stopFocusMaintenance()
        pendingFlushTask?.cancel()
        pendingFlushTask = nil
        terminalEngine?.resignFocus()
        terminalEngine = nil
        retainedRemoteEngine = nil
        rendererDelegateOwner = nil
        attachedViewID = nil
        pendingChunks.removeAll(keepingCapacity: false)
        pendingRendererByteCount = 0
        droppedPendingRendererByteCount = 0
        pendingPasteReview = nil
        pendingExternalLink = nil
        publishRendererDiagnosticsIfChanged(.awaitingWindow)
    }

    #if os(macOS)
    /// Resizes the containing macOS window by the exact point delta between the
    /// renderer's current grid and the requested grid. The surrounding SwiftUI
    /// chrome keeps its existing size; only the terminal canvas delta is added.
    @discardableResult
    public func fitMacWindowToTerminalGrid(columns: Int, rows: Int) -> Bool {
        terminalEngine?.fitHostWindow(columns: columns, rows: rows) ?? false
    }
    #endif

    fileprivate func updateRendererDiagnostics(_ diagnostics: SwiftTermRendererDiagnostics) {
        publishRendererDiagnosticsIfChanged(diagnostics)
    }

    private func publishRendererDiagnosticsIfChanged(
        _ diagnostics: SwiftTermRendererDiagnostics
    ) {
        guard rendererDiagnostics != diagnostics else { return }
        rendererDiagnostics = diagnostics
    }

    public func focus() {
        guard allowsFocusOwnership else {
            stopFocusMaintenance()
            return
        }
        focusRetryTask?.cancel()
        focusRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // First responder can fail transiently during window activation;
            // retry briefly, but only while this terminal's window is active.
            // Focus is otherwise driven explicitly by the host UI so sheets,
            // search fields, alerts, and IME composition retain ownership.
            for _ in 0..<3 {
                guard self.allowsFocusOwnership,
                      let engine = self.terminalEngine else { return }
                if engine.focusIfActive() {
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    public func setFocusOwnershipAllowed(_ allowed: Bool) {
        guard allowsFocusOwnership != allowed else { return }
        allowsFocusOwnership = allowed
        if allowed {
            focus()
        } else {
            stopFocusMaintenance()
            #if canImport(UIKit)
            // updateUIView can revoke ownership during a TabView transaction.
            // Resigning synchronously asks the hosting view for its next
            // responder, re-entering that same SwiftUI graph update. Vision Pro
            // too: its workgroup tabs revoke it the same way (W10).
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.allowsFocusOwnership else { return }
                self.terminalEngine?.resignFocus()
            }
            #else
            terminalEngine?.resignFocus()
            #endif
        }
    }

    public func dismissInputFocus() {
        stopFocusMaintenance()
        terminalEngine?.resignFocus()
    }

    public func stopFocusMaintenance() {
        focusRetryTask?.cancel()
        focusRetryTask = nil
    }

    public var isLikelyRunningInteractiveProgram: Bool {
        terminalEngine?.isLikelyRunningInteractiveProgram ?? false
    }

    public var isComposingText: Bool {
        terminalEngine?.isComposingText ?? false
    }

    public var performanceDiagnostics: SwiftTermPerformanceDiagnostics {
        terminalEngine?.performanceDiagnostics ?? SwiftTermPerformanceDiagnostics()
    }

    public func getVisibleText(lastNLines: Int = 20) -> [String] {
        terminalEngine?.visibleText(lastNLines: lastNLines) ?? []
    }

    #if os(macOS)
    /// An in-memory, bounded rendering of the existing viewport. Never reparents
    /// the terminal, changes its grid, starts a process, or acquires input focus.
    public func previewImage(maxPixelWidth: Int = 640) -> NSImage? {
        guard let view = terminalEngine?.hostView,
              view.bounds.width > 0, view.bounds.height > 0 else { return nil }
        let scale = min(1, CGFloat(max(1, min(maxPixelWidth, 1024))) / view.bounds.width,
                        640 / view.bounds.height)
        let width = max(1, Int(view.bounds.width * scale))
        let height = max(1, Int(view.bounds.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.cgContext.scaleBy(x: scale, y: scale)
        view.displayIgnoringOpacity(view.bounds, in: context)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }
    #endif

    #if canImport(UIKit)
    /// Snapshot the existing UIKit viewport without moving it or changing PTY geometry.
    ///
    /// **`canImport(UIKit)`, not `os(visionOS)`.** Every call here — `UIGraphicsImageRenderer`,
    /// `layer.render(in:)` — is ordinary UIKit and has always worked on iPhone and iPad. The
    /// narrower fence was around the *feature* that happened to want it first (the spatial
    /// overview), so a terminal could not draw itself on a phone and the session gallery had
    /// nothing to show there. Rule 52: fence the API, not the capability.
    public func previewImage(maxPixelWidth: Int = 640) -> UIImage? {
        // Off the screen — a terminal the person has left, on an iPhone — the view may draw
        // nothing current, so it gives the picture it last drew there (2026-10-14: All Windows'
        // cards; Blur previews softens it like every other).
        guard let view = terminalEngine?.hostView, view.window != nil,
              view.bounds.width > 0, view.bounds.height > 0 else { return rememberedPreview }
        let scale = min(1, CGFloat(max(1, min(maxPixelWidth, 1024))) / view.bounds.width,
                        640 / view.bounds.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        view.layoutIfNeeded()
        view.layer.displayIfNeeded()
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            // What is on screen, as it is composited: on iPhone and iPad the terminal draws with
            // Metal, which `layer.render` cannot see — its pictures were empty (the owner,
            // 2026-10-14: "i didnt see a preview"). Vision Pro's Core Graphics drawing renders
            // either way; the layer is the fallback when a snapshot cannot be had.
            if !view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: false) {
                context.cgContext.scaleBy(x: scale, y: scale)
                view.layer.render(in: context.cgContext)
            }
        }
        rememberedPreview = image
        return image
    }

    /// The picture the terminal last drew on screen, for while it is not.
    private var rememberedPreview: UIImage?

    /// Takes the picture as the view leaves the screen, while it can still draw itself.
    fileprivate func rememberPreview() {
        _ = previewImage(maxPixelWidth: 800)
    }
    #endif

    // MARK: Find

    /// One find step in this terminal's buffer: toward older output from the hit, or from the
    /// newest line when there is none, so the first search finds the newest match. Nil when no
    /// renderer is attached yet, which is not the same as "no match".
    public func find(_ term: String, towardOlder: Bool) -> SwiftTermFindResult? {
        guard !term.isEmpty else {
            clearSearch()
            return SwiftTermFindResult(found: false, index: 0, total: 0)
        }
        return terminalEngine?.find(term, towardOlder: towardOlder)
    }

    /// Forgets the hit and clears its highlight.
    public func clearSearch() {
        terminalEngine?.clearSearch()
    }

    /// The line the current hit is on, while it is highlighted; nil when there is none.
    public var selectedFindLine: String? {
        terminalEngine?.selectedFindLine
    }

    public func resolvePendingPaste(approvedText: String?) {
        guard let request = pendingPasteReview else { return }
        pendingPasteReview = nil
        guard let approvedText,
              SwiftTermPastePolicy.isAllowed(approvedText) else { return }
        terminalEngine?.commitPaste(approvedText, bracketed: request.bracketedPasteMode)
    }

    /// Text dropped on the terminal — files from Finder, as their paths — typed in the way a paste
    /// is: bracketed when the program asked for it, and reviewed first when it is long or spans
    /// lines, by the same rules as ⌘V (2026-10-07).
    public func insertDroppedText(_ text: String) {
        guard let engine = terminalEngine else { return }
        requestPaste(text, bracketed: engine.isBracketedPasteMode)
    }

    public func resolvePendingExternalLink(approved: Bool) -> URL? {
        guard let request = pendingExternalLink else { return nil }
        pendingExternalLink = nil
        return approved ? request.url : nil
    }

    fileprivate func requestPaste(_ text: String, bracketed: Bool) {
        guard pendingPasteReview == nil, !text.isEmpty else { return }
        if let review = SwiftTermPastePolicy.reviewRequest(for: text, bracketed: bracketed) {
            pendingPasteReview = review
        } else if SwiftTermPastePolicy.isAllowed(text) {
            terminalEngine?.commitPaste(text, bracketed: bracketed)
        }
    }

    func requestExternalLink(_ link: String) {
        guard pendingExternalLink == nil,
              let request = SwiftTermExternalLinkPolicy.validatedRequest(for: link) else {
            return
        }
        pendingExternalLink = request
    }

    fileprivate func updateCurrentDirectory(_ directory: String?) {
        guard currentDirectory != directory else { return }
        currentDirectory = directory
        appendSemanticEvent(.workingDirectoryChanged(directory: directory))
    }

    fileprivate func updateTerminalTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard terminalTitle != value else { return }
        terminalTitle = value
        onTerminalTitleChange?(value)
    }

    fileprivate func updateScrollPosition(_ position: Double) {
        let clampedPosition = min(1, max(0, position))
        guard scrollPosition != clampedPosition else { return }
        scrollPosition = clampedPosition
    }

    fileprivate func recordITermEvent(_ kind: SwiftTermSemanticEventKind) {
        appendSemanticEvent(kind)
    }

    fileprivate func recordDisplayRange(startY: Int, endY: Int) {
        appendSemanticEvent(.displayRangeChanged(startY: startY, endY: endY))
    }

    fileprivate func recordOSC52Decision(_ decision: SwiftTermOSC52Decision) {
        appendSemanticEvent(.osc52Denied(decision))
    }

    private func appendSemanticEvent(_ kind: SwiftTermSemanticEventKind) {
        let event = SwiftTermSemanticEvent(sequence: nextSemanticEventSequence, kind: kind)
        semanticEvents.append(event)
        nextSemanticEventSequence += 1
        if semanticEvents.count > Self.semanticEventHistoryLimit {
            semanticEvents.removeFirst(semanticEvents.count - Self.semanticEventHistoryLimit)
        }
        semanticEventPublisher.send(event)
    }

    public func ingest(data: Data, nonce: UInt64) {
        guard nonce != lastNonce else { return }
        lastNonce = nonce
        noteOutputActivity()
        guard let terminalEngine,
              pendingFlushTask == nil,
              pendingChunks.isEmpty,
              droppedPendingRendererByteCount == 0 else {
            enqueuePendingRendererData(data)
            schedulePendingFlush()
            return
        }
        terminalEngine.receive(data)
    }

    /// SwiftUI invokes representable creation during a view update. Deferring
    /// the bootstrap feed one main-actor turn avoids delegate-published model
    /// changes during that update. New bytes remain queued until this task
    /// drains the retained prefix, preserving transport order exactly.
    private func schedulePendingFlush() {
        guard pendingFlushTask == nil,
              terminalEngine != nil,
              !pendingChunks.isEmpty || droppedPendingRendererByteCount > 0 else {
            return
        }
        pendingFlushTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.pendingFlushTask = nil
            self.flushPending()
        }
    }

    private func flushPending() {
        guard let terminalEngine else { return }
        for chunk in pendingChunks {
            terminalEngine.receive(chunk)
        }
        pendingChunks.removeAll(keepingCapacity: true)
        pendingRendererByteCount = 0
        if droppedPendingRendererByteCount > 0 {
            // CAN aborts an incomplete escape/control string and SGR 0 returns
            // the parser to a readable style before the truthful truncation
            // notice. The count is metadata; omitted remote bytes are not
            // fabricated or silently hidden.
            let notice = Data(
                (
                    "\u{18}\u{1B}[0m\r\n"
                        + "[omitted \(droppedPendingRendererByteCount) bytes "
                        + "received before the terminal renderer attached]\r\n"
                ).utf8
            )
            terminalEngine.receive(notice)
            droppedPendingRendererByteCount = 0
        }
    }

    private func enqueuePendingRendererData(_ data: Data) {
        guard !data.isEmpty else { return }
        let available = max(
            0,
            Self.maximumPendingRendererBytes - pendingRendererByteCount
        )
        if available > 0 {
            let retained = Data(data.prefix(available))
            pendingChunks.append(retained)
            pendingRendererByteCount += retained.count
        }
        droppedPendingRendererByteCount += max(0, data.count - available)
    }
}

/// What one find step found, and where that match is among all of them.
public struct SwiftTermFindResult: Equatable, Sendable {
    public let found: Bool
    /// The match's place counted from the newest, 1 being the newest; 0 when it is not known.
    public let index: Int
    /// Every match in the buffer, up to SwiftTerm's limit of 1,000.
    public let total: Int

    public init(found: Bool, index: Int, total: Int) {
        self.found = found
        self.index = index
        self.total = total
    }
}

/// A find hit that survives output (2026-10-08).
///
/// SwiftTerm keeps a hit only as the selection, and `feedPrepare` clears the selection on every
/// chunk while mouse reporting is on, which is its default. The selection is also where the next
/// search starts, so one spinner frame erased the hit before it was drawn and sent the next search
/// back to the oldest line. Mouse reporting is not turned off for this: on iOS that makes a pan
/// send arrow keys. The hit is remembered in buffer terms instead, put back after each chunk and
/// before each find, and dropped when the scrollback trims past it or its text is gone.
@MainActor
private final class SwiftTermFindTracker {
    private struct Hit {
        var start: Position
        var end: Position
        /// `totalLinesTrimmed` when the hit was found: rows shift up by one per trimmed line.
        var trimmed: Int
        var buffer: ObjectIdentifier
        var term: String
    }

    private var hit: Hit?
    /// Where the hit was last selected. A selection anywhere else is someone else's, and wins.
    private var applied: (start: Position, end: Position)?

    func find(_ term: String, towardOlder: Bool, in view: TerminalView) -> SwiftTermFindResult {
        reapply(in: view)
        let found = towardOlder ? view.findPrevious(term) : view.findNext(term)
        guard found, let selection = view.selection, selection.active else {
            forget()
            return SwiftTermFindResult(found: false, index: 0, total: 0)
        }
        // Asked at once: SwiftTerm forgets its last result on the next chunk of output.
        let summary = view.searchMatchSummary(term)
        let buffer = view.getTerminal().buffer
        hit = Hit(start: selection.start, end: selection.end, trimmed: buffer.totalLinesTrimmed,
                  buffer: ObjectIdentifier(buffer), term: term)
        applied = (selection.start, selection.end)
        let index = summary.index > 0 ? summary.total - summary.index + 1 : 0
        return SwiftTermFindResult(found: true, index: index, total: max(summary.total, 1))
    }

    /// Puts the hit back after output cleared it.
    func reapply(in view: TerminalView) {
        guard let hit, let selection = view.selection else { return }
        let terminal = view.getTerminal()
        let buffer = terminal.buffer
        // The other screen is showing: the hit belongs to the one that comes back.
        guard ObjectIdentifier(buffer) == hit.buffer else { return }
        if let applied, selection.start != applied.start || selection.end != applied.end {
            forget()
            return
        }
        let shift = buffer.totalLinesTrimmed - hit.trimmed
        let start = Position(col: hit.start.col, row: hit.start.row - shift)
        let end = Position(col: hit.end.col, row: hit.end.row - shift)
        guard shift >= 0, start.row >= 0,
              Self.text(rows: start.row...max(start.row, end.row), in: terminal)
                .range(of: hit.term, options: .caseInsensitive) != nil else {
            forget()
            return
        }
        applied = (start, end)
        guard !selection.active || selection.start != start || selection.end != end else { return }
        selection.setSelection(start: start, end: end)
    }

    func clear(in view: TerminalView) {
        forget()
        view.clearSearch()
    }

    func selectedLine(in view: TerminalView) -> String? {
        guard hit != nil, let applied, let selection = view.selection, selection.active,
              selection.start == applied.start, selection.end == applied.end else { return nil }
        return Self.text(rows: applied.start.row...applied.start.row, in: view.getTerminal())
    }

    private func forget() {
        hit = nil
        applied = nil
    }

    /// The text of buffer rows, counted from the oldest line still kept.
    private static func text(rows: ClosedRange<Int>, in terminal: Terminal) -> String {
        let top = terminal.buffer.totalLinesTrimmed
        return rows.compactMap { row in
            terminal.getScrollInvariantLine(row: top + row)?.translateToString(
                trimRight: true,
                skipNullCellsFollowingWide: true,
                characterProvider: { terminal.getCharacter(for: $0) }
            )
        }.joined()
    }
}

/// Keeps what someone selected while output arrives. SwiftTerm lets go of the selection at
/// every chunk of output while mouse reporting is allowed (`feedPrepare`), so with anything
/// printing — Claude Code's spinner, tmux's status line — a selection lasted until the next frame
/// (owner, 2026-10-09: "I can't select text in terminals... it seems to be deselected with a
/// refresh of screen"). Taken before a chunk and put back after it, where its text still is; a
/// selection whose text the output changed is gone, as SwiftTerm meant.
@MainActor
enum SwiftTermSelectionKeeper {
    struct Kept {
        let start: Position
        let end: Position
        /// `totalLinesTrimmed` when taken: rows shift up by one per trimmed line.
        let trimmed: Int
        let buffer: ObjectIdentifier
        let text: String
    }

    static func take(from view: TerminalView) -> Kept? {
        guard let selection = view.selection, selection.active else { return nil }
        let buffer = view.getTerminal().buffer
        return Kept(start: selection.start, end: selection.end, trimmed: buffer.totalLinesTrimmed,
                    buffer: ObjectIdentifier(buffer), text: selection.getSelectedText())
    }

    static func restore(_ kept: Kept?, in view: TerminalView) {
        guard let kept, let selection = view.selection, !selection.active else { return }
        let buffer = view.getTerminal().buffer
        // The other screen is showing, or the selected lines were trimmed away.
        let shift = buffer.totalLinesTrimmed - kept.trimmed
        guard ObjectIdentifier(buffer) == kept.buffer, shift >= 0,
              min(kept.start.row, kept.end.row) - shift >= 0 else { return }
        selection.setSelection(start: Position(col: kept.start.col, row: kept.start.row - shift),
                               end: Position(col: kept.end.col, row: kept.end.row - shift))
        if selection.getSelectedText() != kept.text { selection.selectNone() }
    }
}

public struct SwiftTermExternalLinkRequest: Identifiable, Equatable {
    public let id: UUID
    public let url: URL
    public let normalizedHost: String
    public let port: Int?

    public var exactURL: String { url.absoluteString }

    fileprivate init(
        id: UUID = UUID(),
        url: URL,
        normalizedHost: String,
        port: Int?
    ) {
        self.id = id
        self.url = url
        self.normalizedHost = normalizedHost
        self.port = port
    }
}

public enum SwiftTermExternalLinkPolicy {
    public static let maximumURLBytes = 8_192

    private static func containsUnsafeDisplayScalar(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .spaceSeparator:
                return true
            default:
                return false
            }
        }
    }

    public static func validatedRequest(for link: String) -> SwiftTermExternalLinkRequest? {
        guard !link.isEmpty,
              link.utf8.count <= maximumURLBytes,
              link == link.trimmingCharacters(in: .whitespacesAndNewlines),
              !link.unicodeScalars.contains(where: { scalar in
                  switch scalar.properties.generalCategory {
                  case .control, .format:
                      return true
                  default:
                      return false
                  }
              }),
              var components = URLComponents(string: link),
              let rawScheme = components.scheme,
              ["http", "https"].contains(rawScheme.lowercased()),
              components.user == nil,
              components.password == nil,
              let rawHost = components.host,
              !rawHost.isEmpty,
              !containsUnsafeDisplayScalar(rawHost) else {
            return nil
        }

        components.scheme = rawScheme.lowercased()
        guard let url = components.url,
              let normalizedURLHost = url.host?.lowercased(),
              !normalizedURLHost.isEmpty,
              !containsUnsafeDisplayScalar(normalizedURLHost) else {
            return nil
        }

        return SwiftTermExternalLinkRequest(
            url: url,
            normalizedHost: normalizedURLHost,
            port: components.port
        )
    }
}

public struct SwiftTermPasteReview: Identifiable, Equatable {
    public let id: UUID
    public let content: String
    public let byteCount: Int
    public let lineCount: Int
    public let bracketedPasteMode: Bool
    public let exceedsMaximumSize: Bool
}

public enum SwiftTermPastePolicy {
    public static let directPasteMaximumBytes = 4_096
    public static let maximumPayloadBytes = 262_144
    private static let bracketedPasteStart = Data([0x1b, 0x5b, 0x32, 0x30, 0x30, 0x7e])
    private static let bracketedPasteEnd = Data([0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e])

    public static func isAllowed(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= maximumPayloadBytes
    }

    public static func requiresReview(_ text: String) -> Bool {
        text.contains("\n")
            || text.contains("\r")
            || text.utf8.count > directPasteMaximumBytes
    }

    public static func reviewRequest(
        for text: String,
        bracketed: Bool
    ) -> SwiftTermPasteReview? {
        guard requiresReview(text) || !isAllowed(text) else { return nil }
        let byteCount = text.utf8.count
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return SwiftTermPasteReview(
            id: UUID(),
            content: byteCount <= maximumPayloadBytes ? text : "",
            byteCount: byteCount,
            lineCount: normalized.split(separator: "\n", omittingEmptySubsequences: false).count,
            bracketedPasteMode: bracketed,
            exceedsMaximumSize: byteCount > maximumPayloadBytes
        )
    }

    public static func framedData(for text: String, bracketed: Bool) -> Data {
        var data = Data()
        if bracketed {
            data.append(bracketedPasteStart)
        }
        data.append(Data(text.utf8))
        if bracketed {
            data.append(bracketedPasteEnd)
        }
        return data
    }
}

public struct SwiftTermThemeColor: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public struct SwiftTermTheme: Equatable {
    public var fontSize: CGFloat
    public var fontName: String
    public var foreground: (red: Double, green: Double, blue: Double)
    public var background: (red: Double, green: Double, blue: Double, alpha: Double)
    public var cursor: (red: Double, green: Double, blue: Double)
    public var selection: (red: Double, green: Double, blue: Double, alpha: Double)
    public var ansiColors: [SwiftTermThemeColor]

    public init(
        fontSize: CGFloat,
        foreground: (red: Double, green: Double, blue: Double),
        background: (red: Double, green: Double, blue: Double, alpha: Double),
        cursor: (red: Double, green: Double, blue: Double),
        fontName: String = "SF Mono",
        selection: (red: Double, green: Double, blue: Double, alpha: Double) = (0, 0.48, 1, 0.3),
        ansiColors: [SwiftTermThemeColor] = []
    ) {
        self.fontSize = fontSize
        self.fontName = fontName
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.ansiColors = ansiColors
    }

    public static func == (lhs: SwiftTermTheme, rhs: SwiftTermTheme) -> Bool {
        lhs.fontSize == rhs.fontSize
            && lhs.fontName == rhs.fontName
            && lhs.foreground == rhs.foreground
            && lhs.background == rhs.background
            && lhs.cursor == rhs.cursor
            && lhs.selection == rhs.selection
            && lhs.ansiColors == rhs.ansiColors
    }
}

public struct SwiftTermRuntimeSettings: Equatable {
    public var cursorStyle: String
    public var blinkingCursor: Bool
    public var scrollbackLines: Int
    public var optionAsMetaKey: Bool

    public init(
        cursorStyle: String,
        blinkingCursor: Bool,
        scrollbackLines: Int,
        optionAsMetaKey: Bool = false
    ) {
        self.cursorStyle = cursorStyle
        self.blinkingCursor = blinkingCursor
        self.scrollbackLines = min(100_000, max(0, scrollbackLines))
        self.optionAsMetaKey = optionAsMetaKey
    }
}

/// Narrow boundary between terminal transport/state and the concrete renderer.
/// The active implementation remains SwiftTerm; an alternate renderer only needs to
/// conform here and be selected by `SwiftTermHostView.makeEngine`.
#if canImport(UIKit)
@MainActor
private protocol TerminalEngine: AnyObject {
    var identity: ObjectIdentifier { get }
    var hostView: UIView { get }
    var isLikelyRunningInteractiveProgram: Bool { get }
    var isComposingText: Bool { get }
    var rendererDiagnostics: SwiftTermRendererDiagnostics { get }
    var performanceDiagnostics: SwiftTermPerformanceDiagnostics { get }

    func configure(theme: SwiftTermTheme, runtimeSettings: SwiftTermRuntimeSettings)
    func updateDelegate(_ delegate: TerminalViewDelegate)
    func receive(_ data: Data)
    func recordInput(byteCount: Int)
    func focusIfActive() -> Bool
    func resignFocus()
    func refreshAccessibilityViewport()
    func visibleText(lastNLines: Int) -> [String]
    func find(_ term: String, towardOlder: Bool) -> SwiftTermFindResult
    func clearSearch()
    var selectedFindLine: String? { get }
    func commitPaste(_ text: String, bracketed: Bool)
    /// Whether the program in the terminal asked for bracketed paste.
    var isBracketedPasteMode: Bool { get }
    /// Called as the view is about to leave the screen, while it can still draw itself.
    var onLeavingWindow: (@MainActor () -> Void)? { get set }
}

public enum SwiftTermHardwareKeyPolicy {
    /// SwiftTerm's legacy input path maps F10 to F9 and drops F12-F24. Keep
    /// Kitty protocol handling in SwiftTerm, but provide the standard xterm
    /// sequences when the remote has not enabled Kitty keyboard reporting.
    public static func legacyFunctionKeySequence(for keyCode: UIKeyboardHIDUsage) -> [UInt8]? {
        switch keyCode {
        case .keyboardF10:
            return EscapeSequences.cmdF[9]
        case .keyboardF12:
            return EscapeSequences.cmdF[11]
        case .keyboardF13:
            return csiTilde(25)
        case .keyboardF14:
            return csiTilde(26)
        case .keyboardF15:
            return csiTilde(28)
        case .keyboardF16:
            return csiTilde(29)
        case .keyboardF17:
            return csiTilde(31)
        case .keyboardF18:
            return csiTilde(32)
        case .keyboardF19:
            return csiTilde(33)
        case .keyboardF20:
            return csiTilde(34)
        case .keyboardF21:
            return csiTilde(42)
        case .keyboardF22:
            return csiTilde(43)
        case .keyboardF23:
            return csiTilde(44)
        case .keyboardF24:
            return csiTilde(45)
        default:
            return nil
        }
    }

    private static func csiTilde(_ number: Int) -> [UInt8] {
        Array("\u{1B}[\(number)~".utf8)
    }
}

public enum SwiftTermSpecialKey: Equatable, Sendable {
    case escape
    case tab
    case left(applicationCursor: Bool)
    case down(applicationCursor: Bool)
    case up(applicationCursor: Bool)
    case right(applicationCursor: Bool)
    case function(Int)
}

public enum SwiftTermSpecialKeyPolicy {
    public static func sequence(for key: SwiftTermSpecialKey) -> [UInt8]? {
        switch key {
        case .escape:
            return EscapeSequences.cmdEsc
        case .tab:
            return EscapeSequences.cmdTab
        case .left(let applicationCursor):
            return applicationCursor ? EscapeSequences.moveLeftApp : EscapeSequences.moveLeftNormal
        case .down(let applicationCursor):
            return applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal
        case .up(let applicationCursor):
            return applicationCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal
        case .right(let applicationCursor):
            return applicationCursor ? EscapeSequences.moveRightApp : EscapeSequences.moveRightNormal
        case .function(let number):
            guard (1...EscapeSequences.cmdF.count).contains(number) else { return nil }
            return EscapeSequences.cmdF[number - 1]
        }
    }
}

public struct SwiftTermCursorScrubDelta: Equatable, Sendable {
    public let horizontal: Int
    public let vertical: Int

    public static let zero = SwiftTermCursorScrubDelta(horizontal: 0, vertical: 0)

    public init(horizontal: Int, vertical: Int) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}

public enum SwiftTermCursorScrubAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

public enum SwiftTermCursorScrubPolicy {
    /// Both axes remain available for the entire drag, including direction changes.
    public static func freeformDelta(
        horizontalPoints: Double, verticalPoints: Double,
        cellWidth: Double, cellHeight: Double
    ) -> SwiftTermCursorScrubDelta {
        SwiftTermCursorScrubDelta(
            horizontal: quantizedSteps(points: horizontalPoints, cellSize: cellWidth),
            vertical: quantizedSteps(points: verticalPoints, cellSize: cellHeight)
        )
    }
    public static let maximumStepsPerAxis = 256
    public static let maximumStepsPerUpdate = 4
    public static let deadZoneInCells = 0.45

    public static func dominantAxis(
        horizontalPoints: Double,
        verticalPoints: Double,
        cellWidth: Double,
        cellHeight: Double
    ) -> SwiftTermCursorScrubAxis? {
        guard horizontalPoints.isFinite,
              verticalPoints.isFinite,
              cellWidth.isFinite,
              cellHeight.isFinite,
              cellWidth > 0,
              cellHeight > 0 else { return nil }

        let horizontalCells = abs(horizontalPoints / cellWidth)
        let verticalCells = abs(verticalPoints / cellHeight)
        guard max(horizontalCells, verticalCells) >= deadZoneInCells else { return nil }
        return horizontalCells >= verticalCells ? .horizontal : .vertical
    }

    public static func quantizedDelta(
        horizontalPoints: Double,
        verticalPoints: Double,
        cellWidth: Double,
        cellHeight: Double,
        lockedAxis: SwiftTermCursorScrubAxis
    ) -> SwiftTermCursorScrubDelta {
        switch lockedAxis {
        case .horizontal:
            return SwiftTermCursorScrubDelta(
                horizontal: quantizedSteps(points: horizontalPoints, cellSize: cellWidth),
                vertical: 0
            )
        case .vertical:
            return SwiftTermCursorScrubDelta(
                horizontal: 0,
                vertical: quantizedSteps(points: verticalPoints, cellSize: cellHeight)
            )
        }
    }

    public static func incrementalDelta(
        current: SwiftTermCursorScrubDelta,
        previouslyApplied: SwiftTermCursorScrubDelta
    ) -> SwiftTermCursorScrubDelta {
        SwiftTermCursorScrubDelta(
            horizontal: cappedDifference(current.horizontal, previouslyApplied.horizontal),
            vertical: cappedDifference(current.vertical, previouslyApplied.vertical)
        )
    }

    public static func adding(
        _ delta: SwiftTermCursorScrubDelta,
        to applied: SwiftTermCursorScrubDelta
    ) -> SwiftTermCursorScrubDelta {
        SwiftTermCursorScrubDelta(
            horizontal: applied.horizontal + delta.horizontal,
            vertical: applied.vertical + delta.vertical
        )
    }

    public static func keys(
        for delta: SwiftTermCursorScrubDelta,
        applicationCursor: Bool
    ) -> [SwiftTermSpecialKey] {
        var keys: [SwiftTermSpecialKey] = []
        let horizontalCount = boundedMagnitude(delta.horizontal)
        let verticalCount = boundedMagnitude(delta.vertical)
        keys.reserveCapacity(horizontalCount + verticalCount)

        if delta.horizontal < 0 {
            keys.append(contentsOf: repeatElement(
                .left(applicationCursor: applicationCursor),
                count: horizontalCount
            ))
        } else if delta.horizontal > 0 {
            keys.append(contentsOf: repeatElement(
                .right(applicationCursor: applicationCursor),
                count: horizontalCount
            ))
        }

        if delta.vertical < 0 {
            keys.append(contentsOf: repeatElement(
                .up(applicationCursor: applicationCursor),
                count: verticalCount
            ))
        } else if delta.vertical > 0 {
            keys.append(contentsOf: repeatElement(
                .down(applicationCursor: applicationCursor),
                count: verticalCount
            ))
        }

        return keys
    }

    public static func sequences(
        for delta: SwiftTermCursorScrubDelta,
        applicationCursor: Bool
    ) -> [[UInt8]] {
        keys(for: delta, applicationCursor: applicationCursor).compactMap {
            SwiftTermSpecialKeyPolicy.sequence(for: $0)
        }
    }

    private static func quantizedSteps(points: Double, cellSize: Double) -> Int {
        guard points.isFinite, cellSize.isFinite, cellSize > 0 else { return 0 }
        let rawSteps = points / cellSize
        guard rawSteps.isFinite else { return 0 }
        let boundedSteps = min(
            max(rawSteps, -Double(maximumStepsPerAxis)),
            Double(maximumStepsPerAxis)
        )
        return Int(boundedSteps.rounded(.towardZero))
    }

    private static func cappedDifference(_ current: Int, _ previous: Int) -> Int {
        let (difference, overflow) = current.subtractingReportingOverflow(previous)
        if overflow {
            return current >= previous ? maximumStepsPerUpdate : -maximumStepsPerUpdate
        }
        return min(max(difference, -maximumStepsPerUpdate), maximumStepsPerUpdate)
    }

    private static func boundedMagnitude(_ value: Int) -> Int {
        guard value != .min else { return maximumStepsPerAxis }
        return min(abs(value), maximumStepsPerAxis)
    }
}

/// A native keyboard toolbar replaces SwiftTerm's permanently expanded
/// engineering key row. UIKit supplies the accessory material and spacing;
/// only the drag-capable cursor control needs a custom view.
@MainActor
private final class MinimalTerminalAccessoryView: UIToolbar {
    private var baseItems: [UIBarButtonItem] = []
    private weak var installedToolsView: UIView?

    #if os(iOS)
    func setToolsView(_ view: UIView?) {
        guard view !== installedToolsView else { return }
        installedToolsView = view
        guard let view else { items = baseItems; return }
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        view.widthAnchor.constraint(equalToConstant: 100).isActive = true
        view.heightAnchor.constraint(equalToConstant: 44).isActive = true
        var updated = baseItems
        updated.insert(UIBarButtonItem(customView: view), at: 2)
        items = updated
    }
    #endif
    private weak var terminalView: ReviewingTerminalView?
    private let onDismissKeyboard: @MainActor () -> Void
    private let onShownChange: @MainActor (Bool) -> Void
    private var appliedCursorDelta = SwiftTermCursorScrubDelta.zero
    private var lockedCursorAxis: SwiftTermCursorScrubAxis?
    private var cursorDrainTask: Task<Void, Never>?

    init(
        terminalView: ReviewingTerminalView,
        onDismissKeyboard: @escaping @MainActor () -> Void,
        onShownChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.terminalView = terminalView
        self.onDismissKeyboard = onDismissKeyboard
        self.onShownChange = onShownChange
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        sizeToFit()
        #if os(iOS)
        frame.size.height = 60
        #else
        frame.size.height = 44
        #endif
        autoresizingMask = [.flexibleWidth]

        let dismissItem = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.chevron.compact.down"),
            style: .plain,
            target: self,
            action: #selector(dismissKeyboard)
        )
        dismissItem.accessibilityLabel = "Dismiss Keyboard"

        var cursorConfiguration = UIButton.Configuration.tinted()
        #if !os(iOS)
        cursorConfiguration.title = "Cursor"
        #endif
        cursorConfiguration.image = UIImage(
            systemName: "arrow.up.and.down.and.arrow.left.and.right"
        )
        cursorConfiguration.imagePadding = 5
        cursorConfiguration.cornerStyle = .capsule
        #if os(iOS)
        cursorConfiguration.titleLineBreakMode = .byTruncatingTail
        #endif
        let cursorPad = UIButton(configuration: cursorConfiguration)
        #if os(iOS)
        cursorPad.titleLabel?.numberOfLines = 1
        #endif
        cursorPad.accessibilityLabel = "Drag to move cursor"
        cursorPad.accessibilityHint = "Drag to move by terminal character cells."
        #if os(iOS)
        cursorPad.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move left") { [weak self] _ in
                self?.sendArrow(.left); return self != nil
            },
            UIAccessibilityCustomAction(name: "Move right") { [weak self] _ in
                self?.sendArrow(.right); return self != nil
            },
            UIAccessibilityCustomAction(name: "Move up") { [weak self] _ in
                self?.sendArrow(.up); return self != nil
            },
            UIAccessibilityCustomAction(name: "Move down") { [weak self] _ in
                self?.sendArrow(.down); return self != nil
            },
        ]
        #endif
        cursorPad.isExclusiveTouch = true
        let cursorPan = UIPanGestureRecognizer(target: self, action: #selector(scrubCursor(_:)))
        cursorPan.maximumNumberOfTouches = 1
        cursorPad.addGestureRecognizer(cursorPan)
        #if os(iOS)
        cursorPad.frame.size = CGSize(width: 44, height: 32)
        cursorPad.widthAnchor.constraint(equalToConstant: 44).isActive = true
        #else
        cursorPad.frame.size = CGSize(width: 104, height: 32)
        cursorPad.widthAnchor.constraint(equalToConstant: 104).isActive = true
        #endif
        #if os(iOS)
        cursorPad.heightAnchor.constraint(equalToConstant: 44).isActive = true
        #else
        cursorPad.heightAnchor.constraint(equalToConstant: 32).isActive = true
        #endif
        let cursorItem = UIBarButtonItem(customView: cursorPad)

        let keysItem = UIBarButtonItem(
            image: UIImage(systemName: "keyboard.badge.ellipsis"),
            style: .plain,
            target: nil,
            action: nil
        )
        keysItem.menu = makeMenu()
        keysItem.accessibilityLabel = "Terminal Keys"
        keysItem.accessibilityHint = "Shows Escape, Control, navigation, and function keys."

        baseItems = [
            dismissItem,
            .flexibleSpace(),
            cursorItem,
            .flexibleSpace(),
            keysItem,
        ]
        items = baseItems
    }

    required init?(coder: NSCoder) {
        nil
    }

    #if os(iOS)
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 60)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: 60)
    }
    #endif

    deinit {
        cursorDrainTask?.cancel()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil {
            cancelCursorScrub()
        }
        super.willMove(toWindow: newWindow)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onShownChange(window != nil)
    }

    private func makeMenu() -> UIMenu {
        let escape = action("Escape", image: "escape") { [weak self] in
            self?.send(.escape)
        }
        let tab = action("Tab", image: "arrow.right.to.line.compact") { [weak self] in
            self?.send(.tab)
        }
        let control = action("Control for Next Key", image: "control") { [weak self] in
            self?.armControlModifier()
        }
        let navigation = UIMenu(title: "Navigation", image: UIImage(systemName: "arrow.up.and.down.and.arrow.left.and.right"), children: [
            action("Left", image: "arrow.left") { [weak self] in self?.sendArrow(.left) },
            action("Down", image: "arrow.down") { [weak self] in self?.sendArrow(.down) },
            action("Up", image: "arrow.up") { [weak self] in self?.sendArrow(.up) },
            action("Right", image: "arrow.right") { [weak self] in self?.sendArrow(.right) },
        ])
        let functions = UIMenu(title: "Function Keys", image: UIImage(systemName: "f.square"), children: (1...12).map { number in
            action("F\(number)") { [weak self] in self?.send(.function(number)) }
        })
        #if os(iOS)
        return UIMenu(children: [escape, tab, control, functions])
        #else
        return UIMenu(children: [escape, tab, control, navigation, functions])
        #endif
    }

    private enum Arrow { case left, down, up, right }

    @objc private func dismissKeyboard() {
        cancelCursorScrub()
        onDismissKeyboard()
    }

    @objc private func scrubCursor(_ gesture: UIPanGestureRecognizer) {
        guard let terminalView else { return }
        switch gesture.state {
        case .began:
            cancelCursorScrub()
        case .changed, .ended:
            let translation = gesture.translation(in: gesture.view)
            let terminal = terminalView.getTerminal()
            let cellWidth = Double(terminalView.bounds.width) / Double(max(terminal.cols, 1))
            let cellHeight = Double(terminalView.bounds.height) / Double(max(terminal.rows, 1))
            #if os(iOS)
            let currentDelta = SwiftTermCursorScrubPolicy.freeformDelta(
                horizontalPoints: Double(translation.x), verticalPoints: Double(translation.y),
                cellWidth: cellWidth, cellHeight: cellHeight
            )
            #else
            if lockedCursorAxis == nil {
                lockedCursorAxis = SwiftTermCursorScrubPolicy.dominantAxis(
                    horizontalPoints: Double(translation.x),
                    verticalPoints: Double(translation.y),
                    cellWidth: cellWidth,
                    cellHeight: cellHeight
                )
            }
            guard let lockedCursorAxis else { return }
            let currentDelta = SwiftTermCursorScrubPolicy.quantizedDelta(
                horizontalPoints: Double(translation.x),
                verticalPoints: Double(translation.y),
                cellWidth: cellWidth,
                cellHeight: cellHeight,
                lockedAxis: lockedCursorAxis
            )
            #endif
            let incrementalDelta = SwiftTermCursorScrubPolicy.incrementalDelta(
                current: currentDelta,
                previouslyApplied: appliedCursorDelta
            )
            appliedCursorDelta = SwiftTermCursorScrubPolicy.adding(
                incrementalDelta,
                to: appliedCursorDelta
            )
            sendCursorDelta(incrementalDelta)
            if gesture.state == .ended {
                finishCursorScrub(at: currentDelta)
            }
        case .cancelled, .failed:
            cancelCursorScrub()
        default:
            break
        }
    }

    fileprivate func cancelCursorScrub() {
        cursorDrainTask?.cancel()
        cursorDrainTask = nil
        appliedCursorDelta = .zero
        lockedCursorAxis = nil
    }

    private func finishCursorScrub(at target: SwiftTermCursorScrubDelta) {
        guard appliedCursorDelta != target else {
            appliedCursorDelta = .zero
            lockedCursorAxis = nil
            return
        }

        cursorDrainTask?.cancel()
        cursorDrainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.appliedCursorDelta != target {
                let incrementalDelta = SwiftTermCursorScrubPolicy.incrementalDelta(
                    current: target,
                    previouslyApplied: self.appliedCursorDelta
                )
                guard incrementalDelta != .zero else { break }
                self.appliedCursorDelta = SwiftTermCursorScrubPolicy.adding(
                    incrementalDelta,
                    to: self.appliedCursorDelta
                )
                self.sendCursorDelta(incrementalDelta)
                try? await Task.sleep(for: .milliseconds(8))
            }
            guard !Task.isCancelled else { return }
            self.appliedCursorDelta = .zero
            self.lockedCursorAxis = nil
            self.cursorDrainTask = nil
        }
    }

    private func armControlModifier() {
        guard let terminalView else { return }
        terminalView.controlModifier = true
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        UIAccessibility.post(
            notification: .announcement,
            argument: "Control is armed for the next key."
        )
    }

    private func sendArrow(_ arrow: Arrow) {
        let applicationCursor = terminalView?.getTerminal().applicationCursor ?? false
        switch arrow {
        case .left: send(.left(applicationCursor: applicationCursor))
        case .down: send(.down(applicationCursor: applicationCursor))
        case .up: send(.up(applicationCursor: applicationCursor))
        case .right: send(.right(applicationCursor: applicationCursor))
        }
    }

    private func sendCursorDelta(_ delta: SwiftTermCursorScrubDelta) {
        let applicationCursor = terminalView?.getTerminal().applicationCursor ?? false
        let keys = SwiftTermCursorScrubPolicy.keys(
            for: delta,
            applicationCursor: applicationCursor
        )
        guard !keys.isEmpty else { return }
        #if os(iOS)
        UIDevice.current.playInputClick()
        #endif
        for key in keys {
            send(key, playsInputClick: false)
        }
    }

    private func send(_ key: SwiftTermSpecialKey, playsInputClick: Bool = true) {
        guard let terminalView,
              let bytes = SwiftTermSpecialKeyPolicy.sequence(for: key) else { return }
        #if os(iOS)
        if playsInputClick {
            UIDevice.current.playInputClick()
        }
        #endif
        terminalView.terminalDelegate?.send(source: terminalView, data: bytes[...])
    }

    private func action(
        _ title: String,
        image: String? = nil,
        handler: @escaping @MainActor () -> Void
    ) -> UIAction {
        UIAction(title: title, image: image.flatMap(UIImage.init(systemName:))) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}

@MainActor
private final class ReviewingTerminalView: TerminalView {
    var onPasteRequest: ((String, Bool) -> Void)?
    var onWindowAttachmentChanged: (() -> Void)?
    var onLeavingWindow: (() -> Void)?

    override func willMove(toWindow newWindow: UIWindow?) {
        if newWindow == nil, window != nil { onLeavingWindow?() }
        super.willMove(toWindow: newWindow)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        #if os(visionOS)
        installHoldToSelect()
        #endif
        onWindowAttachmentChanged?()
    }

    /// The height of one row, or 0 before the font is measured.
    var rowHeight: CGFloat {
        let rows = getTerminal().rows
        guard rows > 0 else { return 0 }
        return getOptimalFrameSize().height / CGFloat(rows)
    }

    #if os(visionOS)
    /// **Pinch and hold, then drag, selects** — the way visionOS selects text (the owner on the
    /// headset, 2026-10-13: "the pinch drag select method doesn't work … I can triple click and get
    /// a whole line but I can't adjust it after"). SwiftTerm's long press only opened a menu, a
    /// pinch-drag scrolls, and a drag after a triple tap went to the scrolling too. Held, the
    /// selection starts at the character looked at — or, held on either end of the selection there
    /// is, moves that end; dragging while held extends it; letting go offers Copy. A plain
    /// pinch-drag still scrolls, and a double or triple tap still selects a word or a line.
    private lazy var holdToSelect: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(holdToSelectChanged(_:)))
        recognizer.minimumPressDuration = 0.5
        return recognizer
    }()

    /// The Copy menu after a hold: `UIMenuController`, which SwiftTerm uses, is deprecated on
    /// visionOS since 1.0.
    private lazy var selectionMenu = UIEditMenuInteraction(delegate: nil)

    private func installHoldToSelect() {
        guard holdToSelect.view == nil else { return }
        addInteraction(selectionMenu)
        // SwiftTerm's own long press (`setupGestures`, 0.7 s) shows a menu and would answer the
        // same hold; it is the only long press on this view.
        for recognizer in gestureRecognizers ?? [] where recognizer is UILongPressGestureRecognizer {
            recognizer.isEnabled = false
        }
        addGestureRecognizer(holdToSelect)
    }

    /// The buffer cell under `point` (the view scrolls over the whole buffer, so rows count from
    /// its first line, as SwiftTerm's own hit test does), or nil before the font is measured.
    private func bufferCell(at point: CGPoint) -> Position? {
        let terminal = getTerminal()
        guard terminal.cols > 0, terminal.rows > 0 else { return nil }
        let size = getOptimalFrameSize()
        let width = size.width / CGFloat(terminal.cols), height = size.height / CGFloat(terminal.rows)
        guard width > 0, height > 0, width.isFinite, height.isFinite else { return nil }
        let column = min(max(0, Int(point.x / width)), terminal.cols - 1)
        let row = max(0, Int(point.y / height))
        return Position(col: column, row: row)
    }

    @objc private func holdToSelectChanged(_ gesture: UILongPressGestureRecognizer) {
        guard let cell = bufferCell(at: gesture.location(in: self)) else { return }
        switch gesture.state {
        case .began:
            _ = becomeFirstResponder()
            selectionMenu.dismissMenu()
            if selection.active, Self.isNear(cell, selection.end) {
                selection.pivot = selection.start
            } else if selection.active, Self.isNear(cell, selection.start) {
                selection.pivot = selection.end
            } else {
                selection.setSelection(start: cell, end: cell)
                selection.pivot = cell
            }
            selection.pivotExtend(bufferPosition: cell)
        case .changed:
            selection.pivotExtend(bufferPosition: cell)
        case .ended:
            selection.pivotExtend(bufferPosition: cell)
            showCopyMenu()
        default:
            break
        }
    }

    /// Within reach of a selection's end for a hold aimed by the eyes: SwiftTerm's own drag asks
    /// for 3 columns and 2 rows.
    private static func isNear(_ cell: Position, _ end: Position) -> Bool {
        abs(cell.col - end.col) < 3 && abs(cell.row - end.row) < 2
    }

    private func showCopyMenu() {
        let terminal = getTerminal()
        guard selection.active, terminal.cols > 0, terminal.rows > 0 else { return }
        let size = getOptimalFrameSize()
        let width = size.width / CGFloat(terminal.cols), height = size.height / CGFloat(terminal.rows)
        let start = selection.start, end = selection.end
        let region = CGRect(x: start.row == end.row ? CGFloat(start.col) * width : 0,
                            y: CGFloat(start.row) * height,
                            width: start.row == end.row ? CGFloat(end.col - start.col + 1) * width : bounds.width,
                            height: CGFloat(end.row - start.row + 1) * height)
        selectionMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil,
                                                                    sourcePoint: CGPoint(x: region.midX, y: region.minY)))
    }
    #endif

    @objc override func paste(_ sender: Any?) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        onPasteRequest?(text, getTerminal().bracketedPasteMode)
    }

    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        commands.append(correctedFunctionKeyCommand(input: UIKeyCommand.f10))
        commands.append(correctedFunctionKeyCommand(input: UIKeyCommand.f12))
        // Not while text is being composed, nor under the Kitty keyboard protocol: SwiftTerm's own
        // handling of the press is the right one then.
        if markedTextRange == nil, getTerminal().keyboardEnhancementFlags.isEmpty {
            commands += Self.arrowCommands
            commands.append(Self.deleteCommand)
        }
        return commands
    }

    /// **Delete, held, repeats** (the owner on visionOS with a hardware keyboard, 2026-10-13: held
    /// delete deleted one character). SwiftTerm repeats the keys it takes in `pressesBegan` on a
    /// timer of its own, but delete is not one of them: it reaches `deleteBackward` through the
    /// text system, and on the headset nothing repeated it. As a key command with priority that
    /// may repeat, the system repeats it; the action is SwiftTerm's own `deleteBackward`, so the
    /// byte it sends and its text bookkeeping stay SwiftTerm's.
    private static let deleteCommand: UIKeyCommand = {
        let command = UIKeyCommand(input: UIKeyCommand.inputDelete, modifierFlags: [], action: #selector(deleteHeld(_:)))
        command.wantsPriorityOverSystemBehavior = true
        command.repeatBehavior = .repeatable
        return command
    }()

    @objc private func deleteHeld(_ command: UIKeyCommand) {
        deleteBackward()
    }

    /// **The arrow keys ahead of the system** (the owner on visionOS 27.2, 2026-10-11: no arrow
    /// worked in a terminal or a desktop, while Mac Virtual Display took them). A press reaches
    /// `pressesBegan` only after the system has passed on it, and visionOS uses arrows for its own
    /// navigation; a key command with priority is offered the press first, as F10 and F12 are. The
    /// bytes are SwiftTerm's own for each arrow (`iOSTerminalView.pressesBegan`); with marked text or
    /// the Kitty keyboard protocol the press goes to SwiftTerm as before.
    private static let arrowCommands: [UIKeyCommand] = {
        let inputs = [UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow, UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow]
        let modifiers: [UIKeyModifierFlags] = [[], .shift, .alternate, .control]
        return inputs.flatMap { input in
            modifiers.map { flags in
                let command = UIKeyCommand(input: input, modifierFlags: flags, action: #selector(sendArrow(_:)))
                command.wantsPriorityOverSystemBehavior = true
                // Held, an arrow repeats, as SwiftTerm's own handling of it did (2026-10-13).
                command.repeatBehavior = .repeatable
                return command
            }
        }
    }()

    @objc private func sendArrow(_ command: UIKeyCommand) {
        guard let input = command.input,
              let bytes = SwiftTermArrowKeys.bytes(input: input, modifiers: command.modifierFlags,
                                                   applicationCursor: getTerminal().applicationCursor) else { return }
        send(bytes)
    }

    private func correctedFunctionKeyCommand(input: String) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: [],
            action: #selector(sendCorrectedFunctionKey(_:))
        )
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    @objc private func sendCorrectedFunctionKey(_ command: UIKeyCommand) {
        let keyCode: UIKeyboardHIDUsage
        switch command.input {
        case UIKeyCommand.f10: keyCode = .keyboardF10
        case UIKeyCommand.f12: keyCode = .keyboardF12
        default: return
        }
        _ = sendLegacyFunctionKeyIfEligible(keyCode)
    }

    /// Sends only legacy function keys SwiftTerm does not encode
    /// correctly. Marked text belongs to UIKit's input method, while Kitty
    /// keyboard mode remains wholly owned by SwiftTerm.
    fileprivate func sendLegacyFunctionKeyIfEligible(_ keyCode: UIKeyboardHIDUsage) -> Bool {
        guard markedTextRange == nil,
              getTerminal().keyboardEnhancementFlags.isEmpty,
              let bytes = SwiftTermHardwareKeyPolicy.legacyFunctionKeySequence(for: keyCode)
        else { return false }
        terminalDelegate?.send(source: self, data: bytes[...])
        return true
    }
}

/// SwiftTerm's iOS `pressesBegan` override is public but not open, so a
/// subclass cannot repair its legacy F13-F24 handling. Those keys are left
/// unhandled and forwarded through the public UIResponder chain; this parent
/// consumes just those events after SwiftTerm has declined them.
@MainActor
private final class TerminalHardwareKeyContainerView: UIView {
    weak var terminalView: ReviewingTerminalView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let terminalView else { return }
        // **A whole number of rows, top-aligned.** SwiftTerm fits `floor(height / row)` rows and
        // then pins its scroll offset to the content's bottom edge, but draws from the first
        // visible row's top — so the spare fraction of a row pushed every line down by that much
        // and the last one, the prompt, went under the keyboard's accessory bar, out of reach of
        // scrolling (2026-09-27, on the phone with the keyboard up: 370pt, 21 rows of 17pt, the
        // prompt 13pt low). Sized to whole rows the two agree; the spare points stay blank below.
        var frame = bounds
        let row = terminalView.rowHeight
        if row > 0, bounds.height >= row {
            frame.size.height = (bounds.height / row).rounded(.down) * row
        }
        terminalView.frame = frame
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandledPresses = presses
        for press in presses {
            guard let keyCode = press.key?.keyCode,
                  keyCode.rawValue >= UIKeyboardHIDUsage.keyboardF13.rawValue,
                  keyCode.rawValue <= UIKeyboardHIDUsage.keyboardF24.rawValue,
                  terminalView?.sendLegacyFunctionKeyIfEligible(keyCode) == true
            else { continue }
            unhandledPresses.remove(press)
        }

        if !unhandledPresses.isEmpty {
            super.pressesBegan(unhandledPresses, with: event)
        }
    }
}

@MainActor
/// A scroll over the terminal on the alternate screen, where no program asked for the mouse,
/// goes to the model's `onAlternateScreenScroll` (2026-10-08). SwiftTerm's iOS view does nothing
/// with one there — it has no scrollback to move — so in tmux a scroll was lost; this hands it to
/// the session, which scrolls tmux's history. A finger, a trackpad's two-finger scroll and, on
/// Vision Pro, a pinch-and-drag all arrive as this pan; anywhere else the gesture never begins.
private final class UIKitAlternateScreenScrollWatcher: NSObject, UIGestureRecognizerDelegate {
    private weak var view: TerminalView?
    private let handler: () -> (@MainActor (CGFloat, Bool) -> Bool)?
    private var lastTranslation: CGFloat = 0

    init(view: TerminalView, handler: @escaping () -> (@MainActor (CGFloat, Bool) -> Bool)?) {
        self.view = view
        self.handler = handler
        super.init()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.allowedScrollTypesMask = .all
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let view, handler() != nil,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let terminal = view.getTerminal()
        guard terminal.isCurrentBufferAlternate, terminal.mouseMode == .off else { return false }
        // Up and down only: a sideways drag stays the terminal's own.
        let velocity = pan.velocity(in: view)
        return abs(velocity.y) >= abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        guard let view else { return }
        switch pan.state {
        case .began:
            lastTranslation = 0
        case .changed:
            // Fingers moving down bring earlier output into view, as a scroll view does.
            let translation = pan.translation(in: view).y
            let delta = translation - lastTranslation
            lastTranslation = translation
            if delta != 0 { _ = handler()?(delta, true) }
        default:
            lastTranslation = 0
        }
    }
}

@MainActor
private final class SwiftTermEngine: TerminalEngine {
    var onLeavingWindow: (@MainActor () -> Void)?
    /// Black backgrounds show the glass (`TerminalClearBlacks`).
    private var clearBlacks = TerminalClearBlacks()
    var isBracketedPasteMode: Bool { terminalView.getTerminal().bracketedPasteMode }

    let terminalView: ReviewingTerminalView
    private let containerView: TerminalHardwareKeyContainerView
    private let onPasteData: (Data) -> Void
    private let onRendererDiagnostics: (SwiftTermRendererDiagnostics) -> Void
    private let onOSC52Decision: (SwiftTermOSC52Decision) -> Void
    private let performanceClock = ContinuousClock()
    private let rendererPreference = SwiftTermRendererPreference.platformDefault
    private var metalActivationAttempted = false
    private var configuredTheme: SwiftTermTheme?
    private(set) var rendererDiagnostics = SwiftTermRendererDiagnostics.awaitingWindow
    private(set) var performanceDiagnostics = SwiftTermPerformanceDiagnostics()

    init(
        delegate: TerminalViewDelegate,
        onPasteRequest: @escaping (String, Bool) -> Void,
        onPasteData: @escaping (Data) -> Void,
        onRendererDiagnostics: @escaping (SwiftTermRendererDiagnostics) -> Void,
        onOSC52Decision: @escaping (SwiftTermOSC52Decision) -> Void,
        onDismissKeyboard: @escaping @MainActor () -> Void,
        onKeyboardAccessoryShown: @escaping @MainActor (Bool) -> Void,
        alternateScreenScroll: @escaping () -> (@MainActor (CGFloat, Bool) -> Bool)? = { nil }
    ) {
        let terminalView = ReviewingTerminalView(frame: .zero)
        let containerView = TerminalHardwareKeyContainerView(frame: .zero)
        terminalView.terminalDelegate = delegate
        terminalView.onPasteRequest = onPasteRequest
        terminalView.notifyUpdateChanges = true
        terminalView.isOpaque = false
        terminalView.backgroundColor = .clear
        terminalView.clearsContextBeforeDrawing = false
        terminalView.layer.cornerRadius = SwiftTermHostView.terminalViewCornerRadius
        terminalView.layer.masksToBounds = true
        terminalView.isAccessibilityElement = true
        terminalView.accessibilityLabel = "Terminal"
        terminalView.accessibilityHint = "Double-tap to enter terminal input."
        terminalView.accessibilityTraits.insert(.updatesFrequently)
        terminalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        terminalView.inputAccessoryView = MinimalTerminalAccessoryView(
            terminalView: terminalView,
            onDismissKeyboard: onDismissKeyboard,
            onShownChange: onKeyboardAccessoryShown
        )
        containerView.isOpaque = false
        containerView.backgroundColor = .clear
        containerView.terminalView = terminalView
        containerView.addSubview(terminalView)
        self.terminalView = terminalView
        self.containerView = containerView
        self.onPasteData = onPasteData
        self.onRendererDiagnostics = onRendererDiagnostics
        self.onOSC52Decision = onOSC52Decision
        terminalView.onWindowAttachmentChanged = { [weak self] in
            self?.activateRendererIfAttached()
        }
        terminalView.onLeavingWindow = { [weak self] in self?.onLeavingWindow?() }
        terminalView.getTerminal().parser.oscHandlers[52] = { [weak self] request in
            guard let self else { return }
            self.onOSC52Decision(SwiftTermOSC52Policy.evaluate(request))
        }
        scrollWatcher = UIKitAlternateScreenScrollWatcher(view: terminalView, handler: alternateScreenScroll)
    }

    private var scrollWatcher: UIKitAlternateScreenScrollWatcher?

    var identity: ObjectIdentifier { ObjectIdentifier(terminalView) }
    var hostView: UIView { containerView }
    var isLikelyRunningInteractiveProgram: Bool {
        terminalView.getTerminal().isCurrentBufferAlternate
    }
    var isComposingText: Bool { terminalView.markedTextRange != nil }

    func configure(theme: SwiftTermTheme, runtimeSettings: SwiftTermRuntimeSettings) {
        configuredTheme = theme
        applyTheme(theme)
        applyRuntimeSettings(runtimeSettings)
        activateRendererIfAttached()
    }

    func updateDelegate(_ delegate: TerminalViewDelegate) {
        terminalView.terminalDelegate = delegate
    }

    func receive(_ data: Data) {
        let start = performanceClock.now
        let kept = SwiftTermSelectionKeeper.take(from: terminalView)
        terminalView.feed(byteArray: clearBlacks.filter(ArraySlice(data)))
        // Find's hit first: it knows where its own selection went. Any other selection after.
        reapplyFindHit()
        SwiftTermSelectionKeeper.restore(kept, in: terminalView)
        performanceDiagnostics.recordFeed(
            byteCount: data.count,
            duration: start.duration(to: performanceClock.now)
        )
        refreshAccessibilityValue()
    }

    func recordInput(byteCount: Int) {
        performanceDiagnostics.recordInput(byteCount: byteCount)
    }

    func refreshAccessibilityViewport() {
        refreshAccessibilityValue()
    }

    func focusIfActive() -> Bool {
        #if DEBUG
        // Screenshots (App/GlassDemoMode.swift): focus raises the on-screen keyboard over the shot.
        // `--demo-keyboard` keeps it, for checking the layout with the keyboard up.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--demo-open"), !arguments.contains("--demo-keyboard") { return false }
        #endif
        guard let window = terminalView.window, window.isKeyWindow else { return false }
        if terminalView.isFirstResponder {
            applyConfiguredCaretTheme()
            return true
        }
        guard !isComposingText else { return false }
        let focused = terminalView.becomeFirstResponder()
        if focused {
            // SwiftTerm creates its iOS caret view while becoming first responder.
            // The initial pre-attachment theme assignment therefore cannot color
            // the caret and must be replayed after focus is established.
            applyConfiguredCaretTheme()
        }
        return focused
    }

    func resignFocus() {
        (terminalView.inputAccessoryView as? MinimalTerminalAccessoryView)?.cancelCursorScrub()
        guard terminalView.isFirstResponder else { return }
        _ = terminalView.resignFirstResponder()
    }

    func visibleText(lastNLines: Int) -> [String] {
        let buffer = terminalView.getTerminal().getBufferAsData()
        let fullText = String(data: buffer, encoding: .utf8) ?? ""
        let allLines = fullText.components(separatedBy: "\n")
        let nonEmpty = allLines.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return Array(nonEmpty.suffix(max(0, lastNLines)))
    }

    private let findTracker = SwiftTermFindTracker()
    func find(_ term: String, towardOlder: Bool) -> SwiftTermFindResult {
        findTracker.find(term, towardOlder: towardOlder, in: terminalView)
    }
    func clearSearch() { findTracker.clear(in: terminalView) }
    var selectedFindLine: String? { findTracker.selectedLine(in: terminalView) }
    /// After each chunk of output, which clears the selection the hit is drawn with.
    func reapplyFindHit() { findTracker.reapply(in: terminalView) }
    func commitPaste(_ text: String, bracketed: Bool) {
        let data = SwiftTermPastePolicy.framedData(for: text, bracketed: bracketed)
        recordInput(byteCount: data.count)
        onPasteData(data)
    }

    private func refreshAccessibilityValue() {
        let terminal = terminalView.getTerminal()
        let maximumLines = 40
        let maximumCharacters = 4_096
        let firstRow = max(0, terminal.rows - maximumLines)
        var remainingCharacters = maximumCharacters
        var visibleLines: [String] = []
        visibleLines.reserveCapacity(min(maximumLines, terminal.rows))

        for row in firstRow..<terminal.rows where remainingCharacters > 0 {
            guard let line = terminal.getLine(row: row) else { continue }
            let text = line.translateToString(
                trimRight: true,
                skipNullCellsFollowingWide: true,
                characterProvider: { terminal.getCharacter(for: $0) }
            )
            guard !text.isEmpty else { continue }
            let boundedText = String(text.prefix(remainingCharacters))
            visibleLines.append(boundedText)
            remainingCharacters -= boundedText.count
        }

        terminalView.accessibilityValue = visibleLines.isEmpty
            ? "No visible output"
            : visibleLines.joined(separator: "\n")
    }

    private func activateRendererIfAttached() {
        enforceClearBacking()

        guard terminalView.window != nil else {
            #if canImport(MetalKit)
            let detachedBackend: SwiftTermRendererBackend = terminalView.isUsingMetalRenderer
                ? .metal
                : .awaitingWindow
            #else
            let detachedBackend: SwiftTermRendererBackend = .awaitingWindow
            #endif
            publishRendererDiagnostics(
                backend: detachedBackend,
                failureDescription: rendererDiagnostics.failureDescription
            )
            return
        }

        #if canImport(MetalKit)
        if rendererPreference == .coreGraphics {
            if terminalView.isUsingMetalRenderer {
                do {
                    try terminalView.setUseMetal(false)
                } catch {
                    publishRendererDiagnostics(
                        backend: .coreGraphicsFallback,
                        failureDescription: String(describing: error)
                    )
                    return
                }
            }
            enforceClearBacking()
            publishRendererDiagnostics(backend: .coreGraphics, failureDescription: nil)
            return
        }

        if !terminalView.isUsingMetalRenderer && !metalActivationAttempted {
            metalActivationAttempted = true
            do {
                try terminalView.setUseMetal(true)
            } catch {
                enforceClearBacking()
                publishRendererDiagnostics(
                    backend: .coreGraphicsFallback,
                    failureDescription: String(describing: error)
                )
                return
            }
        }

        enforceClearBacking()
        publishRendererDiagnostics(
            backend: terminalView.isUsingMetalRenderer ? .metal : .coreGraphicsFallback,
            failureDescription: terminalView.isUsingMetalRenderer
                ? nil
                : "SwiftTerm did not activate its Metal renderer."
        )
        #else
        publishRendererDiagnostics(
            backend: .coreGraphicsFallback,
            failureDescription: "MetalKit is unavailable on this platform."
        )
        #endif
    }

    private func enforceClearBacking() {
        terminalView.isOpaque = false
        terminalView.backgroundColor = .clear
        terminalView.layer.backgroundColor = UIColor.clear.cgColor

        #if canImport(MetalKit)
        for metalView in terminalView.subviews.compactMap({ $0 as? MTKView }) {
            metalView.isOpaque = false
            metalView.backgroundColor = .clear
            metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
            (metalView.layer as? CAMetalLayer)?.isOpaque = false
        }
        #endif
    }

    private func publishRendererDiagnostics(
        backend: SwiftTermRendererBackend,
        failureDescription: String?
    ) {
        #if canImport(MetalKit)
        let metalViews = terminalView.subviews.compactMap { $0 as? MTKView }
        let rendererBackingIsClear: Bool? = metalViews.isEmpty
            ? nil
            : metalViews.allSatisfy { metalView in
                !metalView.isOpaque
                    && Self.alpha(of: metalView.backgroundColor) == 0
                    && metalView.clearColor.alpha == 0
                    && (metalView.layer as? CAMetalLayer)?.isOpaque == false
            }
        #else
        let rendererBackingIsClear: Bool? = nil
        #endif

        let diagnostics = SwiftTermRendererDiagnostics(
            backend: backend,
            isWindowAttached: terminalView.window != nil,
            hostBackingIsClear: !terminalView.isOpaque
                && Self.alpha(of: terminalView.backgroundColor) == 0
                && Self.alpha(of: terminalView.layer.backgroundColor) == 0
                && Self.alpha(of: terminalView.nativeBackgroundColor) == 0,
            rendererBackingIsClear: rendererBackingIsClear,
            failureDescription: failureDescription
        )
        rendererDiagnostics = diagnostics
        onRendererDiagnostics(diagnostics)
    }

    private static func alpha(of color: UIColor?) -> CGFloat {
        color?.cgColor.alpha ?? 0
    }

    private static func alpha(of color: CGColor?) -> CGFloat {
        color?.alpha ?? 0
    }

    private func applyTheme(_ theme: SwiftTermTheme) {
        clearBlacks.configure(theme)
        let fontSize = max(10, theme.fontSize)
        if theme.fontName == "SF Mono" {
            terminalView.font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        } else {
            terminalView.font = UIFont(name: theme.fontName, size: fontSize)
                ?? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        terminalView.nativeForegroundColor = UIColor(
            red: theme.foreground.red,
            green: theme.foreground.green,
            blue: theme.foreground.blue,
            alpha: 1
        )
        terminalView.nativeBackgroundColor = UIColor(
            red: theme.background.red,
            green: theme.background.green,
            blue: theme.background.blue,
            alpha: theme.background.alpha
        )
        enforceClearBacking()
        terminalView.caretColor = UIColor(
            red: theme.cursor.red,
            green: theme.cursor.green,
            blue: theme.cursor.blue,
            alpha: 1
        )
        terminalView.selectedTextBackgroundColor = UIColor(
            red: theme.selection.red,
            green: theme.selection.green,
            blue: theme.selection.blue,
            alpha: theme.selection.alpha
        )
        if theme.ansiColors.count == 16 {
            terminalView.installColors(theme.ansiColors.map { color in
                SwiftTerm.Color(
                    red: Self.terminalColorComponent(color.red),
                    green: Self.terminalColorComponent(color.green),
                    blue: Self.terminalColorComponent(color.blue)
                )
            })
        }
    }

    private func applyConfiguredCaretTheme() {
        guard let theme = configuredTheme else { return }
        terminalView.caretColor = UIColor(
            red: theme.cursor.red,
            green: theme.cursor.green,
            blue: theme.cursor.blue,
            alpha: 1
        )
    }

    private static func terminalColorComponent(_ component: Double) -> UInt16 {
        UInt16((min(1, max(0, component)) * Double(UInt16.max)).rounded())
    }

    private func applyRuntimeSettings(_ settings: SwiftTermRuntimeSettings) {
        let normalizedStyle = settings.cursorStyle.lowercased()
        let cursorStyle: CursorStyle
        switch (normalizedStyle, settings.blinkingCursor) {
        case ("underline", true): cursorStyle = .blinkUnderline
        case ("underline", false): cursorStyle = .steadyUnderline
        case ("bar", true): cursorStyle = .blinkBar
        case ("bar", false): cursorStyle = .steadyBar
        case (_, true): cursorStyle = .blinkBlock
        case (_, false): cursorStyle = .steadyBlock
        }

        let terminal = terminalView.getTerminal()
        terminal.setCursorStyle(cursorStyle)
        terminal.changeScrollback(settings.scrollbackLines)
        terminalView.optionAsMetaKey = settings.optionAsMetaKey
    }
}

/// The view SwiftUI holds for a terminal; the engine's view goes inside it, filling it. The
/// engine's view can arrive a turn later (see `makeUIView`) and moves between hosts as SwiftUI
/// rebuilds them, so it is never itself the view SwiftUI made.
@MainActor
private final class TerminalRendererHostView: UIView {
    init() {
        super.init(frame: .zero)
        isOpaque = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func install(_ view: UIView) {
        guard view.superview !== self else { return }
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
    }
}

public struct SwiftTermHostView: UIViewRepresentable {
    /// The terminal view's own corner: none on iPhone, and none on Vision Pro, where its rows sit
    /// square inside the canvas's corner (owner, 2026-10-10: "the inner radius on the terminal
    /// itself... remove that radius all together"); iPad keeps its 18.
    static var terminalViewCornerRadius: CGFloat {
        #if os(visionOS)
        0
        #else
        UIDevice.current.userInterfaceIdiom == .phone ? 0 : 18
        #endif
    }

    @ObservedObject var model: SwiftTermHostModel
    let theme: SwiftTermTheme
    let runtimeSettings: SwiftTermRuntimeSettings
    let allowsFocusOwnership: Bool
    let onSendData: (Data) -> Void
    let onResize: (Int, Int) -> Void
    let onTitleChanged: (String) -> Void
    let onBell: () -> Void

    public init(
        model: SwiftTermHostModel,
        theme: SwiftTermTheme,
        runtimeSettings: SwiftTermRuntimeSettings,
        allowsFocusOwnership: Bool = true,
        onSendData: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        onTitleChanged: @escaping (String) -> Void = { _ in },
        onBell: @escaping () -> Void = {}
    ) {
        self.model = model
        self.theme = theme
        self.runtimeSettings = runtimeSettings
        self.allowsFocusOwnership = allowsFocusOwnership
        self.onSendData = onSendData
        self.onResize = onResize
        self.onTitleChanged = onTitleChanged
        self.onBell = onBell
    }

    public func makeCoordinator() -> Coordinator {
        if let coordinator = model.retainedDelegate(as: Coordinator.self) {
            coordinator.update(
                model: model,
                onSendData: onSendData,
                onResize: onResize,
                onTitleChanged: onTitleChanged,
                onBell: onBell
            )
            return coordinator
        }
        return Coordinator(
            model: model,
            onSendData: onSendData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onBell: onBell
        )
    }

    public func makeUIView(context: Context) -> UIView {
        model.setFocusOwnershipAllowed(allowsFocusOwnership)
        context.coordinator.update(
            model: model,
            onSendData: onSendData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onBell: onBell
        )
        context.coordinator.lastTheme = theme
        context.coordinator.lastRuntimeSettings = runtimeSettings
        let host = TerminalRendererHostView()
        if let engine = model.retainedRenderer() {
            #if os(visionOS)
            // **A terminal moving in from another window is installed after this update too**
            // (W15, 2026-10-09). Its view is still in the other window's host; taking it into
            // this one inside SwiftUI's layout moves a view with a keyboard accessory between
            // scenes, which is the focus change the headset's layout crash came from (rule 64).
            if engine.hostView.window != nil {
                let model = model
                DispatchQueue.main.async { [weak host, weak coordinator = context.coordinator] in
                    guard let host, let coordinator, let engine = model.retainedRenderer() else { return }
                    Self.install(engine, in: host, model: model, coordinator: coordinator)
                }
                return host
            }
            #endif
            Self.install(engine, in: host, model: model, coordinator: context.coordinator)
            return host
        }
        // **SwiftTerm's views are built after this update, never inside it** (W10, 2026-10-08).
        // Vision Pro's SwiftUI makes this view from inside its 3D stack layout. SwiftTerm's view
        // builds a keyboard accessory (a `UIInputView`); the first in a window makes UIKit create
        // the scene's text-effects window, whose focus update re-enters SwiftUI's view graph while
        // that stack layout still runs — leaving it with freed children, the headset's crashes in
        // `StackLayout` and `HVStack.updateCache`. Output arriving meanwhile is queued by the model.
        let model = model
        DispatchQueue.main.async { [weak host, weak coordinator = context.coordinator] in
            guard let host, let coordinator else { return }
            let engine = model.retainedRenderer() ?? Self.makeEngine(model: model, delegate: coordinator)
            Self.install(engine, in: host, model: model, coordinator: coordinator)
        }
        return host
    }

    /// Puts the engine's view in `host`, configured with the latest theme the view was given.
    private static func install(
        _ engine: any TerminalEngine,
        in host: TerminalRendererHostView,
        model: SwiftTermHostModel,
        coordinator: Coordinator
    ) {
        engine.updateDelegate(coordinator)
        if let theme = coordinator.lastTheme, let runtimeSettings = coordinator.lastRuntimeSettings {
            engine.configure(theme: theme, runtimeSettings: runtimeSettings)
        }
        host.install(engine.hostView)
        model.attach(engine, delegateOwner: coordinator)
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        model.setFocusOwnershipAllowed(allowsFocusOwnership)
        context.coordinator.update(
            model: model,
            onSendData: onSendData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onBell: onBell
        )
        let cornerRadius = SwiftTermHostView.terminalViewCornerRadius
        if uiView.layer.cornerRadius != cornerRadius {
            uiView.layer.cornerRadius = cornerRadius
        }
        if !uiView.layer.masksToBounds {
            uiView.layer.masksToBounds = true
        }
        guard let engine = model.retainedRenderer() else {
            // Not built yet: the build after this update configures it with these.
            context.coordinator.lastTheme = theme
            context.coordinator.lastRuntimeSettings = runtimeSettings
            return
        }
        guard engine.hostView.superview === uiView else { return }
        engine.updateDelegate(context.coordinator)
        var needsConfiguration = false
        if context.coordinator.lastTheme != theme {
            context.coordinator.lastTheme = theme
            needsConfiguration = true
        }
        if context.coordinator.lastRuntimeSettings != runtimeSettings {
            context.coordinator.lastRuntimeSettings = runtimeSettings
            needsConfiguration = true
        }
        if needsConfiguration {
            engine.configure(theme: theme, runtimeSettings: runtimeSettings)
        }
        model.attach(engine, delegateOwner: context.coordinator)
    }

    public static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.prepareForDismantle()
    }

    private static func makeEngine(model: SwiftTermHostModel, delegate: Coordinator) -> any TerminalEngine {
        let engine = SwiftTermEngine(
            delegate: delegate,
            onPasteRequest: { [weak model] text, bracketed in
                model?.requestPaste(text, bracketed: bracketed)
            },
            onPasteData: { [weak delegate] data in
                delegate?.sendPasteData(data)
            },
            onRendererDiagnostics: { [weak model] diagnostics in
                DispatchQueue.main.async { [weak model] in
                    model?.updateRendererDiagnostics(diagnostics)
                }
            },
            onOSC52Decision: { [weak model] decision in
                model?.recordOSC52Decision(decision)
            },
            onDismissKeyboard: { [weak model] in
                model?.dismissInputFocus()
            },
            onKeyboardAccessoryShown: { [weak model] shown in
                model?.keyboardAccessoryMoved(shown: shown)
            },
            alternateScreenScroll: { [weak model] in model?.onAlternateScreenScroll }
        )
        // Dismiss an active edit menu on any tap. The eye+hand input model can
        // otherwise leave it visible after the selection interaction ends.
        let dismissMenuTap = UITapGestureRecognizer(
            target: delegate,
            action: #selector(Coordinator.dismissEditMenu(_:))
        )
        dismissMenuTap.cancelsTouchesInView = false
        engine.hostView.addGestureRecognizer(dismissMenuTap)
        return engine
    }

    @MainActor
    public final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        private weak var model: SwiftTermHostModel?
        private var onSendData: (Data) -> Void
        private var onResize: (Int, Int) -> Void
        private var onTitleChanged: (String) -> Void
        private var onBell: () -> Void
        fileprivate var lastTheme: SwiftTermTheme?
        fileprivate var lastRuntimeSettings: SwiftTermRuntimeSettings?

        init(
            model: SwiftTermHostModel,
            onSendData: @escaping (Data) -> Void,
            onResize: @escaping (Int, Int) -> Void,
            onTitleChanged: @escaping (String) -> Void,
            onBell: @escaping () -> Void
        ) {
            self.model = model
            self.onSendData = onSendData
            self.onResize = onResize
            self.onTitleChanged = onTitleChanged
            self.onBell = onBell
        }

        fileprivate func update(
            model: SwiftTermHostModel,
            onSendData: @escaping (Data) -> Void,
            onResize: @escaping (Int, Int) -> Void,
            onTitleChanged: @escaping (String) -> Void,
            onBell: @escaping () -> Void
        ) {
            self.model = model
            self.onSendData = onSendData
            self.onResize = onResize
            self.onTitleChanged = onTitleChanged
            self.onBell = onBell
        }

        fileprivate func prepareForDismantle() {
            model?.dismissInputFocus()
        }

        fileprivate func sendPasteData(_ data: Data) {
            onSendData(data)
        }

        @objc @MainActor func dismissEditMenu(_ sender: UITapGestureRecognizer) {
            sender.view?.interactions
                .compactMap { $0 as? UIEditMenuInteraction }
                .forEach { $0.dismissMenu() }
        }

        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize(newCols, newRows)
        }

        public func setTerminalTitle(source: TerminalView, title: String) {
            Task { @MainActor [weak model] in model?.updateTerminalTitle(title) }
            onTitleChanged(title)
        }

        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            Task { @MainActor [weak model] in
                model?.updateCurrentDirectory(directory)
            }
        }

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            model?.retainedRenderer()?.recordInput(byteCount: data.count)
            onSendData(Data(data))
        }

        public func scrolled(source: TerminalView, position: Double) {
            model?.retainedRenderer()?.refreshAccessibilityViewport()
            Task { @MainActor [weak model] in
                model?.updateScrollPosition(position)
            }
        }

        public func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {
            // Remote OSC data can request review, but only the app-owned host
            // UI may authorize navigation and call UIApplication.open.
            Task { @MainActor [weak model] in
                model?.requestExternalLink(link)
            }
        }
        public func bell(source: TerminalView) { onBell() }
        public func clipboardCopy(source: TerminalView, content: Data) {
            // Backstop only: the engine's OSC 52 override denies requests
            // before SwiftTerm decodes content or reaches this delegate.
        }
        public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
            // Record bounded metadata only. Remote file payloads are never
            // retained or persisted by the semantic event stream.
            let kind = SwiftTermITermContentPolicy.semanticEventKind(for: content)
            Task { @MainActor [weak model] in
                model?.recordITermEvent(kind)
            }
        }
        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
            Task { @MainActor [weak model] in
                model?.recordDisplayRange(startY: startY, endY: endY)
            }
        }
    }
}
#elseif canImport(AppKit)
@MainActor
private protocol TerminalEngine: AnyObject {
    var identity: ObjectIdentifier { get }
    var hostView: NSView { get }
    var isLikelyRunningInteractiveProgram: Bool { get }
    var isComposingText: Bool { get }
    var rendererDiagnostics: SwiftTermRendererDiagnostics { get }
    var performanceDiagnostics: SwiftTermPerformanceDiagnostics { get }

    func configure(theme: SwiftTermTheme, runtimeSettings: SwiftTermRuntimeSettings)
    func updateDelegate(_ delegate: TerminalViewDelegate)
    func receive(_ data: Data)
    func recordInput(byteCount: Int)
    func focusIfActive() -> Bool
    func resignFocus()
    func refreshAccessibilityViewport()
    func visibleText(lastNLines: Int) -> [String]
    func find(_ term: String, towardOlder: Bool) -> SwiftTermFindResult
    func clearSearch()
    var selectedFindLine: String? { get }
    func commitPaste(_ text: String, bracketed: Bool)
    func fitHostWindow(columns: Int, rows: Int) -> Bool
    /// Whether the program in the terminal asked for bracketed paste.
    var isBracketedPasteMode: Bool { get }
}

@MainActor
private func fitMacTerminalHostWindow(
    _ terminalView: TerminalView,
    columns: Int,
    rows: Int
) -> Bool {
    guard columns > 0,
          rows > 0,
          let window = terminalView.window,
          window.styleMask.contains(.resizable),
          !window.styleMask.contains(.fullScreen),
          terminalView.frame.width > 0,
          terminalView.frame.height > 0 else { return false }

    let terminal = terminalView.getTerminal()
    let currentColumns = max(1, terminal.cols)
    let currentRows = max(1, terminal.rows)
    guard currentColumns != columns || currentRows != rows else { return false }

    let optimalFrame = terminalView.getOptimalFrameSize()
    let scrollerWidth = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
    let cellWidth = (optimalFrame.width - scrollerWidth) / CGFloat(currentColumns)
    let cellHeight = optimalFrame.height / CGFloat(currentRows)
    guard cellWidth.isFinite,
          cellHeight.isFinite,
          cellWidth > 0,
          cellHeight > 0 else { return false }

    let targetTerminalSize = NSSize(
        width: cellWidth * CGFloat(columns) + scrollerWidth,
        height: cellHeight * CGFloat(rows)
    )
    let widthDelta = targetTerminalSize.width - terminalView.frame.width
    let heightDelta = targetTerminalSize.height - terminalView.frame.height
    guard abs(widthDelta) >= 0.5 || abs(heightDelta) >= 0.5 else { return false }

    let currentFrame = window.frame
    var targetFrame = NSRect(
        x: currentFrame.minX,
        y: currentFrame.maxY - (currentFrame.height + heightDelta),
        width: currentFrame.width + widthDelta,
        height: currentFrame.height + heightDelta
    )

    if let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
        targetFrame.size.width = min(
            visibleFrame.width,
            max(window.minSize.width, targetFrame.width)
        )
        targetFrame.size.height = min(
            visibleFrame.height,
            max(window.minSize.height, targetFrame.height)
        )
        targetFrame.origin.x = min(
            max(targetFrame.minX, visibleFrame.minX),
            visibleFrame.maxX - targetFrame.width
        )
        targetFrame.origin.y = min(
            max(targetFrame.minY, visibleFrame.minY),
            visibleFrame.maxY - targetFrame.height
        )
    }

    window.setFrame(targetFrame, display: true, animate: false)
    window.contentView?.layoutSubtreeIfNeeded()
    return true
}

@MainActor
private final class ReviewingMacTerminalView: TerminalView, MacTerminalHistoryHolding, MacTerminalModelHolding {
    var onPasteRequest: ((String, Bool) -> Void)?
    var onWindowAttachmentChanged: (() -> Void)?

    // Select All over a program's history (`MacTerminalContextMenu.selectAll`).
    var heldSelection: String?
    var historyRead: Task<Void, Never>?
    var fullHistoryProvider: () -> (@MainActor () async -> String?)? = { nil }
    var fullHistory: (@MainActor () async -> String?)? { fullHistoryProvider() }
    // A link's actions in the menu (`MacTerminalContextMenu`): the model the view draws.
    var hostModelProvider: () -> SwiftTermHostModel? = { nil }
    var hostModel: SwiftTermHostModel? { hostModelProvider() }

    // ⌘A: SwiftTerm's Select All can't be overridden from here, so its key is taken first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, MacTerminalContextMenu.isSelectAll(event) {
            MacTerminalContextMenu.selectAll(in: self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        dropHeldSelection()
        super.mouseDown(with: event)
    }

    override func copy(_ sender: Any) {
        if let heldSelection {
            MacTerminalContextMenu.copy(heldSelection, to: MacTerminalContextMenu.copyPasteboard)
        } else {
            super.copy(sender)
        }
    }

    override var isOpaque: Bool { false }
    // Window chrome may drag, but terminal gestures belong to selection and
    // remote mouse reporting, including on a transparent terminal canvas.
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowAttachmentChanged?()
    }

    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onPasteRequest?(text, getTerminal().bracketedPasteMode)
    }

    // The contextual menu, and the selection handed to Services (`MacTerminalContextMenu`).
    override func menu(for event: NSEvent) -> NSMenu? {
        MacTerminalContextMenu.menu(for: self, event: event)
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        MacTerminalContextMenu.servesSelection(of: self, sendType: sendType, returnType: returnType)
            ? self : super.validRequestor(forSendType: sendType, returnType: returnType)
    }
}

// AppKit asks for the selection on the main thread, from the Services menu.
extension ReviewingMacTerminalView: @preconcurrency NSServicesMenuRequestor {
    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        MacTerminalContextMenu.writeSelection(of: self, to: pboard, types: types)
    }
}

@MainActor
private final class MacSwiftTermEngine: TerminalEngine {
    /// Black backgrounds show the glass (`TerminalClearBlacks`).
    private var clearBlacks = TerminalClearBlacks()
    var isBracketedPasteMode: Bool { terminalView.getTerminal().bracketedPasteMode }

    let terminalView: ReviewingMacTerminalView
    private let onPasteData: (Data) -> Void
    private let onRendererDiagnostics: (SwiftTermRendererDiagnostics) -> Void
    private let onOSC52Decision: (SwiftTermOSC52Decision) -> Void
    private let performanceClock = ContinuousClock()
    private(set) var rendererDiagnostics = SwiftTermRendererDiagnostics.awaitingWindow
    private(set) var performanceDiagnostics = SwiftTermPerformanceDiagnostics()
    private var scrollWatcher: MacAlternateScreenScrollWatcher?

    init(
        delegate: TerminalViewDelegate,
        onPasteRequest: @escaping (String, Bool) -> Void,
        onPasteData: @escaping (Data) -> Void,
        onRendererDiagnostics: @escaping (SwiftTermRendererDiagnostics) -> Void,
        onOSC52Decision: @escaping (SwiftTermOSC52Decision) -> Void,
        alternateScreenScroll: @escaping () -> (@MainActor (CGFloat, Bool) -> Bool)? = { nil },
        fullHistory: @escaping () -> (@MainActor () async -> String?)? = { nil },
        hostModel: @escaping () -> SwiftTermHostModel? = { nil }
    ) {
        terminalView = ReviewingMacTerminalView(frame: .zero)
        scrollWatcher = MacAlternateScreenScrollWatcher(view: terminalView, handler: alternateScreenScroll)
        terminalView.fullHistoryProvider = fullHistory
        terminalView.hostModelProvider = hostModel
        self.onPasteData = onPasteData
        self.onRendererDiagnostics = onRendererDiagnostics
        self.onOSC52Decision = onOSC52Decision
        terminalView.terminalDelegate = delegate
        terminalView.onPasteRequest = onPasteRequest
        terminalView.notifyUpdateChanges = true
        terminalView.wantsLayer = true
        terminalView.layer?.backgroundColor = NSColor.clear.cgColor
        terminalView.setAccessibilityElement(true)
        terminalView.setAccessibilityLabel("Terminal")
        terminalView.setAccessibilityHelp("Interactive terminal input and output")
        terminalView.onWindowAttachmentChanged = { [weak self] in
            self?.publishRendererDiagnostics()
        }
        terminalView.getTerminal().parser.oscHandlers[52] = { [weak self] request in
            guard let self else { return }
            self.onOSC52Decision(SwiftTermOSC52Policy.evaluate(request))
        }
    }

    var identity: ObjectIdentifier { ObjectIdentifier(terminalView) }
    var hostView: NSView { terminalView }
    var isLikelyRunningInteractiveProgram: Bool {
        terminalView.getTerminal().isCurrentBufferAlternate
    }
    var isComposingText: Bool { terminalView.hasMarkedText() }

    func configure(theme: SwiftTermTheme, runtimeSettings: SwiftTermRuntimeSettings) {
        applyTheme(theme)
        applyRuntimeSettings(runtimeSettings)
        publishRendererDiagnostics()
    }

    func updateDelegate(_ delegate: TerminalViewDelegate) {
        terminalView.terminalDelegate = delegate
    }

    func receive(_ data: Data) {
        let start = performanceClock.now
        let kept = SwiftTermSelectionKeeper.take(from: terminalView)
        terminalView.feed(byteArray: clearBlacks.filter(ArraySlice(data)))
        // Find's hit first: it knows where its own selection went. Any other selection after.
        reapplyFindHit()
        SwiftTermSelectionKeeper.restore(kept, in: terminalView)
        performanceDiagnostics.recordFeed(
            byteCount: data.count,
            duration: start.duration(to: performanceClock.now)
        )
        refreshAccessibilityViewport()
    }

    func recordInput(byteCount: Int) {
        performanceDiagnostics.recordInput(byteCount: byteCount)
    }

    func focusIfActive() -> Bool {
        guard let window = terminalView.window, window.isKeyWindow else { return false }
        if window.firstResponder === terminalView { return true }
        guard !isComposingText else { return false }
        return window.makeFirstResponder(terminalView)
    }

    func resignFocus() {
        guard let window = terminalView.window, window.firstResponder === terminalView else { return }
        window.makeFirstResponder(nil)
    }

    func refreshAccessibilityViewport() {
        let value = visibleText(lastNLines: 40).joined(separator: "\n")
        terminalView.setAccessibilityValue(value.isEmpty ? "No visible output" : value)
    }

    func visibleText(lastNLines: Int) -> [String] {
        let data = terminalView.getTerminal().getBufferAsData()
        let lines = (String(data: data, encoding: .utf8) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(lines.suffix(max(0, lastNLines)))
    }

    private let findTracker = SwiftTermFindTracker()
    func find(_ term: String, towardOlder: Bool) -> SwiftTermFindResult {
        findTracker.find(term, towardOlder: towardOlder, in: terminalView)
    }
    func clearSearch() { findTracker.clear(in: terminalView) }
    var selectedFindLine: String? { findTracker.selectedLine(in: terminalView) }
    /// After each chunk of output, which clears the selection the hit is drawn with.
    func reapplyFindHit() { findTracker.reapply(in: terminalView) }

    func commitPaste(_ text: String, bracketed: Bool) {
        let data = SwiftTermPastePolicy.framedData(for: text, bracketed: bracketed)
        recordInput(byteCount: data.count)
        onPasteData(data)
    }

    func fitHostWindow(columns: Int, rows: Int) -> Bool {
        fitMacTerminalHostWindow(terminalView, columns: columns, rows: rows)
    }

    private func applyTheme(_ theme: SwiftTermTheme) {
        clearBlacks.configure(theme)
        let fontSize = max(10, theme.fontSize)
        terminalView.font = theme.fontName == "SF Mono"
            ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : NSFont(name: theme.fontName, size: fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeForegroundColor = NSColor(
            srgbRed: theme.foreground.red,
            green: theme.foreground.green,
            blue: theme.foreground.blue,
            alpha: 1
        )
        terminalView.nativeBackgroundColor = NSColor(
            srgbRed: theme.background.red,
            green: theme.background.green,
            blue: theme.background.blue,
            alpha: theme.background.alpha
        )
        terminalView.caretColor = NSColor(
            srgbRed: theme.cursor.red,
            green: theme.cursor.green,
            blue: theme.cursor.blue,
            alpha: 1
        )
        terminalView.selectedTextBackgroundColor = NSColor(
            srgbRed: theme.selection.red,
            green: theme.selection.green,
            blue: theme.selection.blue,
            alpha: theme.selection.alpha
        )
        terminalView.layer?.backgroundColor = NSColor.clear.cgColor
        if theme.ansiColors.count == 16 {
            terminalView.installColors(theme.ansiColors.map { color in
                SwiftTerm.Color(
                    red: Self.terminalColorComponent(color.red),
                    green: Self.terminalColorComponent(color.green),
                    blue: Self.terminalColorComponent(color.blue)
                )
            })
        }
    }

    private func applyRuntimeSettings(_ settings: SwiftTermRuntimeSettings) {
        let normalizedStyle = settings.cursorStyle.lowercased()
        let cursorStyle: CursorStyle
        switch (normalizedStyle, settings.blinkingCursor) {
        case ("underline", true): cursorStyle = .blinkUnderline
        case ("underline", false): cursorStyle = .steadyUnderline
        case ("bar", true): cursorStyle = .blinkBar
        case ("bar", false): cursorStyle = .steadyBar
        case (_, true): cursorStyle = .blinkBlock
        case (_, false): cursorStyle = .steadyBlock
        }
        terminalView.getTerminal().setCursorStyle(cursorStyle)
        terminalView.changeScrollback(settings.scrollbackLines)
        terminalView.optionAsMetaKey = settings.optionAsMetaKey
    }

    private func publishRendererDiagnostics() {
        let diagnostics = SwiftTermRendererDiagnostics(
            backend: .coreGraphicsFallback,
            isWindowAttached: terminalView.window != nil,
            hostBackingIsClear: terminalView.layer?.backgroundColor?.alpha == 0,
            rendererBackingIsClear: true,
            failureDescription: nil
        )
        rendererDiagnostics = diagnostics
        onRendererDiagnostics(diagnostics)
    }

    private static func terminalColorComponent(_ component: Double) -> UInt16 {
        UInt16((min(1, max(0, component)) * Double(UInt16.max)).rounded())
    }
}

public struct SwiftTermHostView: NSViewRepresentable {
    @ObservedObject var model: SwiftTermHostModel
    let theme: SwiftTermTheme
    let runtimeSettings: SwiftTermRuntimeSettings
    let allowsFocusOwnership: Bool
    let onSendData: (Data) -> Void
    let onResize: (Int, Int) -> Void
    let onTitleChanged: (String) -> Void
    let onBell: () -> Void

    public init(
        model: SwiftTermHostModel,
        theme: SwiftTermTheme,
        runtimeSettings: SwiftTermRuntimeSettings,
        allowsFocusOwnership: Bool = true,
        onSendData: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        onTitleChanged: @escaping (String) -> Void = { _ in },
        onBell: @escaping () -> Void = {}
    ) {
        self.model = model
        self.theme = theme
        self.runtimeSettings = runtimeSettings
        self.allowsFocusOwnership = allowsFocusOwnership
        self.onSendData = onSendData
        self.onResize = onResize
        self.onTitleChanged = onTitleChanged
        self.onBell = onBell
    }

    public func makeCoordinator() -> Coordinator {
        if let coordinator = model.retainedDelegate(as: Coordinator.self) {
            coordinator.update(
                model: model,
                onSendData: onSendData,
                onResize: onResize,
                onTitleChanged: onTitleChanged,
                onBell: onBell
            )
            return coordinator
        }
        return Coordinator(
            model: model,
            onSendData: onSendData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onBell: onBell
        )
    }

    public func makeNSView(context: Context) -> NSView {
        model.setFocusOwnershipAllowed(allowsFocusOwnership)
        context.coordinator.update(
            model: model,
            onSendData: onSendData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onBell: onBell
        )
        let engine = resolveEngine(coordinator: context.coordinator)
        engine.updateDelegate(context.coordinator)
        engine.configure(theme: theme, runtimeSettings: runtimeSettings)
        context.coordinator.lastTheme = theme
        context.coordinator.lastRuntimeSettings = runtimeSettings
        model.attach(engine, delegateOwner: context.coordinator)
        return engine.hostView
    }

    /// Establish the session's sole renderer before its lazy workspace tab is
    /// displayed. Uses the already configured PTY grid; snapshots never resize it.
    public func prepareOffscreen(columns: Int, rows: Int) {
        guard !model.hasRetainedRenderer, columns > 0, rows > 0 else { return }
        model.setFocusOwnershipAllowed(false)
        let coordinator = makeCoordinator()
        let engine = resolveEngine(coordinator: coordinator)
        engine.configure(theme: theme, runtimeSettings: runtimeSettings)
        if let remote = engine as? MacSwiftTermEngine {
            remote.terminalView.getTerminal().resize(cols: columns, rows: rows)
            remote.hostView.setFrameSize(remote.terminalView.getOptimalFrameSize().size)
        }
        coordinator.lastTheme = theme
        coordinator.lastRuntimeSettings = runtimeSettings
        model.attach(engine, delegateOwner: coordinator)
    }

    private func resolveEngine(coordinator: Coordinator) -> any TerminalEngine {
        model.retainedRenderer() ?? MacSwiftTermEngine(
            delegate: coordinator,
            onPasteRequest: { [weak model] text, bracketed in
                model?.requestPaste(text, bracketed: bracketed)
            },
            onPasteData: { [weak coordinator] data in
                coordinator?.sendPasteData(data)
            },
            onRendererDiagnostics: { [weak model] diagnostics in
                model?.updateRendererDiagnostics(diagnostics)
            },
            onOSC52Decision: { [weak model] decision in
                model?.recordOSC52Decision(decision)
            },
            alternateScreenScroll: { [weak model] in model?.onAlternateScreenScroll },
            fullHistory: { [weak model] in model?.onFullHistory },
            hostModel: { [weak model] in model }
        )
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        model.setFocusOwnershipAllowed(allowsFocusOwnership)
        context.coordinator.update(
            model: model,
            onSendData: onSendData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onBell: onBell
        )
        guard let engine = model.retainedRenderer(), engine.hostView === nsView else { return }
        engine.updateDelegate(context.coordinator)
        if context.coordinator.lastTheme != theme
            || context.coordinator.lastRuntimeSettings != runtimeSettings {
            context.coordinator.lastTheme = theme
            context.coordinator.lastRuntimeSettings = runtimeSettings
            engine.configure(theme: theme, runtimeSettings: runtimeSettings)
        }
        model.attach(engine, delegateOwner: context.coordinator)
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.prepareForDismantle()
    }

    @MainActor
    public final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        private weak var model: SwiftTermHostModel?
        private var onSendData: (Data) -> Void
        private var onResize: (Int, Int) -> Void
        private var onTitleChanged: (String) -> Void
        private var onBell: () -> Void
        fileprivate var lastTheme: SwiftTermTheme?
        fileprivate var lastRuntimeSettings: SwiftTermRuntimeSettings?

        init(
            model: SwiftTermHostModel,
            onSendData: @escaping (Data) -> Void,
            onResize: @escaping (Int, Int) -> Void,
            onTitleChanged: @escaping (String) -> Void,
            onBell: @escaping () -> Void
        ) {
            self.model = model
            self.onSendData = onSendData
            self.onResize = onResize
            self.onTitleChanged = onTitleChanged
            self.onBell = onBell
        }

        fileprivate func update(
            model: SwiftTermHostModel,
            onSendData: @escaping (Data) -> Void,
            onResize: @escaping (Int, Int) -> Void,
            onTitleChanged: @escaping (String) -> Void,
            onBell: @escaping () -> Void
        ) {
            self.model = model
            self.onSendData = onSendData
            self.onResize = onResize
            self.onTitleChanged = onTitleChanged
            self.onBell = onBell
        }

        fileprivate func prepareForDismantle() {
            model?.dismissInputFocus()
        }

        fileprivate func sendPasteData(_ data: Data) {
            onSendData(data)
        }

        public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            onResize(newCols, newRows)
        }

        public func setTerminalTitle(source: TerminalView, title: String) {
            model?.updateTerminalTitle(title)
            onTitleChanged(title)
        }

        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            model?.updateCurrentDirectory(directory)
        }

        public func send(source: TerminalView, data: ArraySlice<UInt8>) {
            model?.retainedRenderer()?.recordInput(byteCount: data.count)
            onSendData(Data(data))
        }

        public func scrolled(source: TerminalView, position: Double) {
            model?.retainedRenderer()?.refreshAccessibilityViewport()
            Task { @MainActor [weak model] in
                await Task.yield()
                model?.updateScrollPosition(position)
            }
        }

        public func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            model?.requestExternalLink(link)
        }

        public func bell(source: TerminalView) { onBell() }
        public func clipboardCopy(source: TerminalView, content: Data) {
            // Backstop only: the engine's OSC 52 override denies requests
            // before SwiftTerm decodes content or reaches this delegate.
        }

        public func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
            model?.recordITermEvent(SwiftTermITermContentPolicy.semanticEventKind(for: content))
        }

        public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
            model?.recordDisplayRange(startY: startY, endY: endY)
        }
    }
}

/// A local-process launch description that always passes the executable and
/// arguments to `exec` separately. No shell command string is constructed.
public struct SwiftTermLocalProcessConfiguration: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String]?
    public var executableName: String?
    public var currentDirectory: String?
    /// Where the process starts instead when `currentDirectory` is not a folder by the time it
    /// starts: deleted since it was chosen, or on a volume since unmounted. Nil fails the launch,
    /// saying so.
    public var fallbackDirectory: String?

    public init(
        executable: String = "/bin/zsh",
        arguments: [String] = ["-l"],
        environment: [String]? = nil,
        executableName: String? = nil,
        currentDirectory: String? = nil,
        fallbackDirectory: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.executableName = executableName
        self.currentDirectory = currentDirectory
        self.fallbackDirectory = fallbackDirectory
    }

    /// This launch with `fallbackDirectory` in place of a `currentDirectory` that is not a folder
    /// now; unchanged otherwise. Asked as the process starts, so a folder that went between
    /// choosing it and starting there is still caught.
    public func startingInAFolderThatExists(isFolder: (String) -> Bool = Self.isFolder) -> Self {
        guard let currentDirectory, let fallbackDirectory, currentDirectory != fallbackDirectory,
              !isFolder(currentDirectory) else { return self }
        var resolved = self
        resolved.currentDirectory = fallbackDirectory
        return resolved
    }

    public static func isFolder(_ path: String) -> Bool {
        var isDirectory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    fileprivate var validationFailure: String? {
        guard !executable.isEmpty, executable.hasPrefix("/") else {
            return "The local terminal executable must be an absolute path."
        }
        guard !Self.containsNullByte(executable),
              !arguments.contains(where: Self.containsNullByte),
              executableName.map({ !$0.isEmpty && !Self.containsNullByte($0) }) ?? true,
              currentDirectory.map({ $0.hasPrefix("/") && !Self.containsNullByte($0) }) ?? true,
              fallbackDirectory.map({ $0.hasPrefix("/") && !Self.containsNullByte($0) }) ?? true else {
            return "The local terminal launch configuration contains an invalid path or argument."
        }
        if let environmentFailure = Self.environmentValidationFailure(environment) {
            return environmentFailure
        }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return "The local terminal executable does not exist or is not executable."
        }
        if let currentDirectory {
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: currentDirectory, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return "The local terminal working directory does not exist or is not a directory."
            }
        }
        return nil
    }

    private static func containsNullByte(_ value: String) -> Bool {
        value.utf8.contains(0)
    }

    private static func environmentValidationFailure(_ environment: [String]?) -> String? {
        guard let environment else { return nil }
        var names = Set<Substring>()
        for entry in environment {
            guard !containsNullByte(entry),
                  let separator = entry.firstIndex(of: "="),
                  separator != entry.startIndex else {
                return "Each local terminal environment entry must use a non-empty NAME=value form."
            }
            let name = entry[..<separator]
            guard names.insert(name).inserted else {
                return "The local terminal environment contains a duplicate variable named \(name)."
            }
        }
        return nil
    }
}

@MainActor
private protocol SwiftTermLocalProcessControlling: AnyObject {
    func focusLocalProcess()
    func terminateLocalProcess()
    @discardableResult
    func restartLocalProcess(_ configuration: SwiftTermLocalProcessConfiguration) -> Bool
    @discardableResult
    func sendLocalCommand(_ command: String) -> Bool
    func clearLocalDisplay()
    func toggleLocalProcessFullScreen()
}

/// Observable lifecycle state for a local SwiftTerm process. The controller is
/// weak so retaining this model never keeps a window or shell process alive.
@MainActor
public final class SwiftTermLocalProcessState: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var terminalTitle: String?
    @Published public private(set) var currentDirectory: String?
    @Published public private(set) var exitCode: Int32?
    @Published public private(set) var launchError: String?

    private weak var controller: (any SwiftTermLocalProcessControlling)?

    public init() {}

    public func focus() {
        controller?.focusLocalProcess()
    }

    public func terminate() {
        controller?.terminateLocalProcess()
    }

    /// Relaunches the configured local process in the existing terminal after
    /// the prior child has exited. A running process is never replaced.
    @discardableResult
    public func restart(_ configuration: SwiftTermLocalProcessConfiguration) -> Bool {
        controller?.restartLocalProcess(configuration) ?? false
    }

    /// Sends the exact command bytes followed by a carriage return to the
    /// existing PTY. This never invokes a second shell or constructs a
    /// `shell -c` command line; the running interactive process receives the
    /// same input it would receive from the keyboard.
    @discardableResult
    public func sendCommand(_ command: String) -> Bool {
        controller?.sendLocalCommand(command) ?? false
    }

    /// Clears only the local terminal emulator's display and scrollback. The
    /// shell process, working directory, environment, and PTY remain intact.
    public func clearDisplay() {
        controller?.clearLocalDisplay()
    }

    /// Toggles full screen on the NSWindow that owns this PTY, avoiding global
    /// key-window routing when several terminal windows are open.
    public func toggleFullScreen() {
        controller?.toggleLocalProcessFullScreen()
    }

    fileprivate func attach(_ controller: any SwiftTermLocalProcessControlling) {
        self.controller = controller
    }

    fileprivate func beganRunning(currentDirectory: String?) {
        isRunning = true
        exitCode = nil
        launchError = nil
        terminalTitle = nil
        self.currentDirectory = currentDirectory
    }

    fileprivate func failedToLaunch(_ message: String) {
        isRunning = false
        exitCode = nil
        launchError = message
    }

    fileprivate func processTerminated(exitCode: Int32?) {
        isRunning = false
        self.exitCode = exitCode
    }

    fileprivate func updateTitle(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : trimmed
        guard terminalTitle != value else { return }
        terminalTitle = value
    }

    fileprivate func updateCurrentDirectory(_ directory: String?) {
        // Read again after every quiet spell of output, so publish only a change.
        guard currentDirectory != directory else { return }
        currentDirectory = directory
    }
}

@MainActor
private final class ReviewingMacLocalProcessTerminalView: LocalProcessTerminalView, MacTerminalHistoryHolding, MacTerminalModelHolding {
    var onPasteRequest: ((String, Bool) -> Void)?
    var onWindowAttachmentChanged: (() -> Void)?
    var onProcessOutput: ((ArraySlice<UInt8>, Duration) -> Void)?
    /// Black backgrounds show the glass (`TerminalClearBlacks`): the shell's output and the
    /// engine's own notices go through one filter, because they are one stream to the screen.
    var clearBlacks = TerminalClearBlacks()

    // Select All over a program's history (`MacTerminalContextMenu.selectAll`).
    var heldSelection: String?
    var historyRead: Task<Void, Never>?
    var fullHistoryProvider: () -> (@MainActor () async -> String?)? = { nil }
    var fullHistory: (@MainActor () async -> String?)? { fullHistoryProvider() }
    // A link's actions in the menu (`MacTerminalContextMenu`): the model the view draws.
    var hostModelProvider: () -> SwiftTermHostModel? = { nil }
    var hostModel: SwiftTermHostModel? { hostModelProvider() }

    // ⌘A: SwiftTerm's Select All can't be overridden from here, so its key is taken first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, MacTerminalContextMenu.isSelectAll(event) {
            MacTerminalContextMenu.selectAll(in: self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        dropHeldSelection()
        super.mouseDown(with: event)
    }

    override func copy(_ sender: Any) {
        if let heldSelection {
            MacTerminalContextMenu.copy(heldSelection, to: MacTerminalContextMenu.copyPasteboard)
        } else {
            super.copy(sender)
        }
    }

    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowAttachmentChanged?()
    }

    override func paste(_ sender: Any) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onPasteRequest?(text, getTerminal().bracketedPasteMode)
    }

    // The contextual menu, and the selection handed to Services (`MacTerminalContextMenu`).
    override func menu(for event: NSEvent) -> NSMenu? {
        MacTerminalContextMenu.menu(for: self, event: event)
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        MacTerminalContextMenu.servesSelection(of: self, sendType: sendType, returnType: returnType)
            ? self : super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        let clock = ContinuousClock()
        let start = clock.now
        let kept = SwiftTermSelectionKeeper.take(from: self)
        super.dataReceived(slice: clearBlacks.filter(slice))
        // After Find's hit, which `onProcessOutput` puts back.
        onProcessOutput?(slice, start.duration(to: clock.now))
        SwiftTermSelectionKeeper.restore(kept, in: self)
    }
}

// AppKit asks for the selection on the main thread, from the Services menu.
extension ReviewingMacLocalProcessTerminalView: @preconcurrency NSServicesMenuRequestor {
    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        MacTerminalContextMenu.writeSelection(of: self, to: pboard, types: types)
    }
}

@MainActor
private final class MacLocalProcessDelegateProxy:
    NSObject,
    @preconcurrency TerminalViewDelegate,
    @preconcurrency LocalProcessTerminalViewDelegate
{
    weak var terminalView: ReviewingMacLocalProcessTerminalView?
    weak var engine: MacLocalProcessEngine?
    weak var hostModel: SwiftTermHostModel?
    weak var processState: SwiftTermLocalProcessState?

    var onResize: (Int, Int) -> Void
    var onTitleChanged: (String) -> Void
    var onCurrentDirectoryChanged: (String?) -> Void
    var onBell: () -> Void
    var onProcessTerminated: (Int32?) -> Void

    init(
        hostModel: SwiftTermHostModel,
        processState: SwiftTermLocalProcessState,
        onResize: @escaping (Int, Int) -> Void,
        onTitleChanged: @escaping (String) -> Void,
        onCurrentDirectoryChanged: @escaping (String?) -> Void,
        onBell: @escaping () -> Void,
        onProcessTerminated: @escaping (Int32?) -> Void
    ) {
        self.hostModel = hostModel
        self.processState = processState
        self.onResize = onResize
        self.onTitleChanged = onTitleChanged
        self.onCurrentDirectoryChanged = onCurrentDirectoryChanged
        self.onBell = onBell
        self.onProcessTerminated = onProcessTerminated
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // Preserve LocalProcessTerminalView's ioctl-backed resize behavior after
        // replacing its delegate with this policy proxy.
        terminalView?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        processState?.updateTitle(title)
        onTitleChanged(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        hostModel?.updateCurrentDirectory(directory)
        processState?.updateCurrentDirectory(directory)
        onCurrentDirectoryChanged(directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        engine?.sendUserInput(data)
    }

    func scrolled(source: TerminalView, position: Double) {
        engine?.refreshAccessibilityViewport()
        hostModel?.updateScrollPosition(position)
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        // Never inherit SwiftTerm's macOS default, which opens NSWorkspace
        // immediately. The shared host model requires explicit user review.
        hostModel?.requestExternalLink(link)
    }

    func bell(source: TerminalView) {
        onBell()
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        // Backstop only. OSC 52 is replaced at the parser before SwiftTerm can
        // decode or deliver clipboard content here.
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        hostModel?.recordITermEvent(SwiftTermITermContentPolicy.semanticEventKind(for: content))
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        hostModel?.recordDisplayRange(startY: startY, endY: endY)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        onResize(newCols, newRows)
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        processState?.updateTitle(title)
        onTitleChanged(title)
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        if let engine {
            engine.processDidTerminate(waitStatus: exitCode)
        } else {
            let normalizedExitCode = Self.normalizedForkPTYExitCode(exitCode)
            processState?.processTerminated(exitCode: normalizedExitCode)
            onProcessTerminated(normalizedExitCode)
        }
    }

    fileprivate static func normalizedForkPTYExitCode(_ waitStatus: Int32?) -> Int32? {
        guard let waitStatus else { return nil }
        let terminatingSignal = waitStatus & 0x7f
        if terminatingSignal == 0 {
            return (waitStatus >> 8) & 0xff
        }
        if terminatingSignal == 0x7f {
            return nil
        }
        return 128 + terminatingSignal
    }
}

@MainActor
/// Scrolls over a terminal view on their way to it (SwiftTerm's `scrollWheel` cannot be overridden
/// from here): one on the alternate screen, where no program asked for the mouse, goes to the
/// model's `onAlternateScreenScroll` when something listens and takes it (2026-10-08).
private final class MacAlternateScreenScrollWatcher {
    private weak var view: TerminalView?
    private let handler: () -> (@MainActor (CGFloat, Bool) -> Bool)?
    private var monitor: Any?

    init(view: TerminalView, handler: @escaping () -> (@MainActor (CGFloat, Bool) -> Bool)?) {
        self.view = view
        self.handler = handler
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let taken = MainActor.assumeIsolated { self?.takes(event) ?? false }
            return taken ? nil : event
        }
    }

    isolated deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    private func takes(_ event: NSEvent) -> Bool {
        guard event.scrollingDeltaY != 0, let view, let handler = handler(),
              let window = view.window, event.window === window,
              view.bounds.contains(view.convert(event.locationInWindow, from: nil)) else { return false }
        let terminal = view.getTerminal()
        guard terminal.isCurrentBufferAlternate, terminal.mouseMode == .off else { return false }
        return handler(event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
    }
}

private let localProcessLogger = Logger(subsystem: "sh.glas", category: "terminal")

@MainActor
private final class MacLocalProcessEngine: TerminalEngine, SwiftTermLocalProcessControlling {
    var isBracketedPasteMode: Bool { terminalView.getTerminal().bracketedPasteMode }

    static let maximumRecordingCallbackBytes = 64 * 1024

    let terminalView: ReviewingMacLocalProcessTerminalView
    private let delegateProxy: MacLocalProcessDelegateProxy
    private weak var processState: SwiftTermLocalProcessState?
    private var onOutputData: (Data) -> Void
    private var onInputData: (Data) -> Void
    private var onProcessReady: () -> Void
    private var onProcessTerminated: (Int32?) -> Void
    private var onRendererDiagnostics: (SwiftTermRendererDiagnostics) -> Void
    private var onOSC52Decision: (SwiftTermOSC52Decision) -> Void
    private var didReportTermination = false
    /// Set by the first `start`, whether or not the process launched. A host view starts only an
    /// engine that never has, so an exited shell waits for Restart instead of coming back alone.
    private(set) var hasStarted = false
    private(set) var launchedShell: String?
    private(set) var rendererDiagnostics = SwiftTermRendererDiagnostics.awaitingWindow
    private(set) var performanceDiagnostics = SwiftTermPerformanceDiagnostics()
    private var scrollWatcher: MacAlternateScreenScrollWatcher?

    init(
        hostModel: SwiftTermHostModel,
        processState: SwiftTermLocalProcessState,
        onPasteRequest: @escaping (String, Bool) -> Void,
        onOutputData: @escaping (Data) -> Void,
        onInputData: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        onTitleChanged: @escaping (String) -> Void,
        onCurrentDirectoryChanged: @escaping (String?) -> Void,
        onBell: @escaping () -> Void,
        onProcessReady: @escaping () -> Void,
        onProcessTerminated: @escaping (Int32?) -> Void,
        onRendererDiagnostics: @escaping (SwiftTermRendererDiagnostics) -> Void,
        onOSC52Decision: @escaping (SwiftTermOSC52Decision) -> Void
    ) {
        let terminalView = ReviewingMacLocalProcessTerminalView(frame: .zero)
        let delegateProxy = MacLocalProcessDelegateProxy(
            hostModel: hostModel,
            processState: processState,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onCurrentDirectoryChanged: onCurrentDirectoryChanged,
            onBell: onBell,
            onProcessTerminated: onProcessTerminated
        )
        self.terminalView = terminalView
        self.delegateProxy = delegateProxy
        self.processState = processState
        self.onOutputData = onOutputData
        self.onInputData = onInputData
        self.onProcessReady = onProcessReady
        self.onProcessTerminated = onProcessTerminated
        self.onRendererDiagnostics = onRendererDiagnostics
        self.onOSC52Decision = onOSC52Decision

        delegateProxy.terminalView = terminalView
        delegateProxy.engine = self
        terminalView.terminalDelegate = delegateProxy
        terminalView.processDelegate = delegateProxy
        terminalView.onPasteRequest = onPasteRequest
        terminalView.onProcessOutput = { [weak self] bytes, duration in
            self?.recordProcessOutput(bytes, duration: duration)
            self?.reapplyFindHit()
            self?.scheduleWorkingDirectoryCheck()
            self?.delegateProxy.hostModel?.noteOutputActivity()
        }
        scrollWatcher = MacAlternateScreenScrollWatcher(view: terminalView) { [weak self] in
            self?.delegateProxy.hostModel?.onAlternateScreenScroll
        }
        terminalView.fullHistoryProvider = { [weak self] in self?.delegateProxy.hostModel?.onFullHistory }
        terminalView.hostModelProvider = { [weak self] in self?.delegateProxy.hostModel }
        terminalView.onWindowAttachmentChanged = { [weak self] in
            self?.publishRendererDiagnostics()
        }
        terminalView.notifyUpdateChanges = true
        terminalView.wantsLayer = true
        terminalView.layer?.backgroundColor = NSColor.clear.cgColor
        terminalView.setAccessibilityElement(true)
        terminalView.setAccessibilityLabel("Local terminal")
        terminalView.setAccessibilityHelp("Interactive local process terminal input and output")

        terminalView.getTerminal().parser.oscHandlers[52] = { [weak self] request in
            guard let self else { return }
            self.onOSC52Decision(SwiftTermOSC52Policy.evaluate(request))
        }
    }

    var identity: ObjectIdentifier { ObjectIdentifier(terminalView) }
    var hostView: NSView { terminalView }
    var isLikelyRunningInteractiveProgram: Bool {
        terminalView.getTerminal().isCurrentBufferAlternate
    }
    var isComposingText: Bool { terminalView.hasMarkedText() }

    /// Local PTY input must continue through its ioctl/process delegate proxy.
    /// Remote hosts use this protocol hook to refresh presentation callbacks;
    /// the local runtime intentionally preserves its existing proxy.
    func updateDelegate(_ delegate: TerminalViewDelegate) {
        _ = delegate
    }

    func updateCallbacks(
        hostModel: SwiftTermHostModel,
        processState: SwiftTermLocalProcessState,
        onPasteRequest: @escaping (String, Bool) -> Void,
        onOutputData: @escaping (Data) -> Void,
        onInputData: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        onTitleChanged: @escaping (String) -> Void,
        onCurrentDirectoryChanged: @escaping (String?) -> Void,
        onBell: @escaping () -> Void,
        onProcessReady: @escaping () -> Void,
        onProcessTerminated: @escaping (Int32?) -> Void,
        onRendererDiagnostics: @escaping (SwiftTermRendererDiagnostics) -> Void,
        onOSC52Decision: @escaping (SwiftTermOSC52Decision) -> Void
    ) {
        self.processState = processState
        self.onOutputData = onOutputData
        self.onInputData = onInputData
        self.onProcessReady = onProcessReady
        self.onProcessTerminated = onProcessTerminated
        self.onRendererDiagnostics = onRendererDiagnostics
        self.onOSC52Decision = onOSC52Decision
        delegateProxy.hostModel = hostModel
        delegateProxy.processState = processState
        delegateProxy.onResize = onResize
        delegateProxy.onTitleChanged = onTitleChanged
        delegateProxy.onCurrentDirectoryChanged = onCurrentDirectoryChanged
        delegateProxy.onBell = onBell
        delegateProxy.onProcessTerminated = onProcessTerminated
        terminalView.onPasteRequest = onPasteRequest
        terminalView.getTerminal().parser.oscHandlers[52] = { [weak self] request in
            guard let self else { return }
            self.onOSC52Decision(SwiftTermOSC52Policy.evaluate(request))
        }
    }

    func configure(theme: SwiftTermTheme, runtimeSettings: SwiftTermRuntimeSettings) {
        applyTheme(theme)
        applyRuntimeSettings(runtimeSettings)
        publishRendererDiagnostics()
        updatePTYSize()
    }

    func start(_ requested: SwiftTermLocalProcessConfiguration) {
        guard let processState else { return }
        hasStarted = true
        let configuration = requested.startingInAFolderThatExists()
        if configuration.currentDirectory != requested.currentDirectory, let gone = requested.currentDirectory {
            localProcessLogger.notice("A local terminal starts in its fallback folder: its own is gone, \(gone, privacy: .private)")
        }
        if let failure = configuration.validationFailure {
            processState.failedToLaunch(failure)
            return
        }
        guard !terminalView.process.running else { return }

        didReportTermination = false
        terminalView.startProcess(
            executable: configuration.executable,
            args: configuration.arguments,
            environment: configuration.environment,
            execName: configuration.executableName,
            currentDirectory: configuration.currentDirectory
        )
        guard terminalView.process.running else {
            processState.failedToLaunch("The local terminal process could not be started.")
            return
        }
        processState.beganRunning(currentDirectory: configuration.currentDirectory)
        launchedShell = configuration.executable
        if let currentDirectory = configuration.currentDirectory {
            delegateProxy.hostCurrentDirectoryUpdate(
                source: terminalView,
                directory: currentDirectory
            )
        }
        updatePTYSize()
        onProcessReady()
    }

    func receive(_ data: Data) {
        let clock = ContinuousClock()
        let start = clock.now
        let kept = SwiftTermSelectionKeeper.take(from: terminalView)
        terminalView.feed(byteArray: terminalView.clearBlacks.filter(ArraySlice(data)))
        // Find's hit first: it knows where its own selection went. Any other selection after.
        reapplyFindHit()
        SwiftTermSelectionKeeper.restore(kept, in: terminalView)
        performanceDiagnostics.recordFeed(
            byteCount: data.count,
            duration: start.duration(to: clock.now)
        )
        refreshAccessibilityViewport()
    }

    func recordInput(byteCount: Int) {
        performanceDiagnostics.recordInput(byteCount: byteCount)
    }

    func sendUserInput(_ bytes: ArraySlice<UInt8>) {
        guard terminalView.process.running, !bytes.isEmpty else { return }
        recordInput(byteCount: bytes.count)
        emitBounded(Data(bytes), to: onInputData)
        terminalView.send(source: terminalView, data: bytes)
    }

    func focusIfActive() -> Bool {
        guard let window = terminalView.window, window.isKeyWindow else { return false }
        if window.firstResponder === terminalView { return true }
        guard !isComposingText else { return false }
        return window.makeFirstResponder(terminalView)
    }

    func focusLocalProcess() {
        _ = focusIfActive()
    }

    @discardableResult
    func sendLocalCommand(_ command: String) -> Bool {
        guard terminalView.process.running,
              !command.isEmpty,
              !command.utf8.contains(0),
              command.utf8.count <= SwiftTermPastePolicy.maximumPayloadBytes else {
            return false
        }
        var input = Data(command.utf8)
        input.append(0x0d)
        sendUserInput(ArraySlice(input))
        return true
    }

    func clearLocalDisplay() {
        terminalView.getTerminal().resetToInitialState()
        terminalView.needsDisplay = true
        refreshAccessibilityViewport()
    }

    func toggleLocalProcessFullScreen() {
        terminalView.window?.toggleFullScreen(nil)
    }

    func resignFocus() {
        guard let window = terminalView.window, window.firstResponder === terminalView else { return }
        window.makeFirstResponder(nil)
    }

    func terminateLocalProcess() {
        let processID = terminalView.process.shellPid
        guard processID > 0 else {
            reportProcessTermination(exitCode: nil)
            return
        }

        var waitStatus: Int32 = 0
        let waitResult = Self.nonblockingWait(processID, status: &waitStatus)
        if waitResult == processID {
            // PTY EOF can arrive before SwiftTerm's process source. Reap here
            // before the view disappears, without signalling a now-reusable PID.
            reportProcessTermination(
                exitCode: MacLocalProcessDelegateProxy.normalizedForkPTYExitCode(waitStatus)
            )
            return
        }
        if waitResult == -1, errno == ECHILD {
            // SwiftTerm's process source already won the waitpid race.
            reportProcessTermination(exitCode: nil)
            return
        }

        // SwiftTerm closes the PTY and sends SIGTERM, but also cancels its only
        // waitpid source. A dedicated reaper therefore owns this child from this
        // point forward and escalates only if the direct shell ignores SIGTERM.
        terminalView.terminate()
        reportProcessTermination(exitCode: nil)
        Self.reapTerminatedProcess(processID)
    }

    var hasActiveChildProcesses: Bool? {
        guard let process = terminalView.process,
              process.running, process.shellPid > 0, process.childfd >= 0 else { return nil }
        let foregroundGroup = tcgetpgrp(process.childfd)
        guard foregroundGroup > 0 else { return nil }
        if foregroundGroup != process.shellPid { return true }
        // Background jobs leave the shell in the foreground. Inspect its direct
        // children as well so closing a prompt does not silently kill a job.
        var children = [pid_t](repeating: 0, count: 64)
        errno = 0
        let bytes = children.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(process.shellPid),
                         buffer.baseAddress, Int32(buffer.count))
        }
        guard bytes > 0 || (bytes == 0 && errno == 0) else { return nil }
        return children.contains { $0 > 0 }
    }

    var foregroundCommandLine: String? {
        guard let process = terminalView.process, process.running, process.childfd >= 0 else { return nil }
        let group = tcgetpgrp(process.childfd)
        return group > 0 ? TerminalProcessTable.commandLine(of: group) : nil
    }

    var currentWorkingDirectory: String? {
        guard terminalView.process.running, terminalView.process.shellPid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(terminalView.process.shellPid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else {
            return nil
        }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { bytes in
            let path = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            return path.hasPrefix("/") ? path : nil
        }
    }

    @discardableResult
    func restartLocalProcess(_ configuration: SwiftTermLocalProcessConfiguration) -> Bool {
        guard !terminalView.process.running else { return false }
        terminalView.getTerminal().resetToInitialState()
        terminalView.needsDisplay = true
        start(configuration)
        return terminalView.process.running
    }

    fileprivate func processDidTerminate(waitStatus: Int32?) {
        reportProcessTermination(
            exitCode: MacLocalProcessDelegateProxy.normalizedForkPTYExitCode(waitStatus)
        )
    }

    private func reportProcessTermination(exitCode: Int32?) {
        guard !didReportTermination else { return }
        didReportTermination = true
        processState?.processTerminated(exitCode: exitCode)
        onProcessTerminated(exitCode)
    }

    nonisolated private static func nonblockingWait(
        _ processID: pid_t,
        status: inout Int32
    ) -> pid_t {
        while true {
            let result = waitpid(processID, &status, WNOHANG)
            if result == -1, errno == EINTR { continue }
            return result
        }
    }

    nonisolated private static func reapTerminatedProcess(_ processID: pid_t) {
        DispatchQueue.global(qos: .utility).async {
            let deadline = DispatchTime.now() + .seconds(2)
            var status: Int32 = 0
            while DispatchTime.now() < deadline {
                let result = nonblockingWait(processID, status: &status)
                if result == processID || (result == -1 && errno == ECHILD) {
                    return
                }
                if result == -1 { return }
                usleep(20_000)
            }

            if kill(processID, SIGKILL) == -1, errno == ESRCH { return }
            while waitpid(processID, &status, 0) == -1 {
                if errno == EINTR { continue }
                return
            }
        }
    }

    func refreshAccessibilityViewport() {
        let value = visibleText(lastNLines: 40).joined(separator: "\n")
        terminalView.setAccessibilityValue(value.isEmpty ? "No visible output" : value)
    }

    func visibleText(lastNLines: Int) -> [String] {
        let data = terminalView.getTerminal().getBufferAsData()
        let lines = (String(data: data, encoding: .utf8) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return Array(lines.suffix(max(0, lastNLines)))
    }

    private let findTracker = SwiftTermFindTracker()
    func find(_ term: String, towardOlder: Bool) -> SwiftTermFindResult {
        findTracker.find(term, towardOlder: towardOlder, in: terminalView)
    }
    func clearSearch() { findTracker.clear(in: terminalView) }
    var selectedFindLine: String? { findTracker.selectedLine(in: terminalView) }
    /// After each chunk of output, which clears the selection the hit is drawn with.
    func reapplyFindHit() { findTracker.reapply(in: terminalView) }

    func commitPaste(_ text: String, bracketed: Bool) {
        let data = SwiftTermPastePolicy.framedData(for: text, bracketed: bracketed)
        sendUserInput(ArraySlice(data))
    }

    func fitHostWindow(columns: Int, rows: Int) -> Bool {
        fitMacTerminalHostWindow(terminalView, columns: columns, rows: rows)
    }

    /// The shell's directory, read from the process itself shortly after output settles — a `cd`
    /// is followed by a new prompt — because macOS's zsh reports it (OSC 7) only to Terminal.app.
    /// It names the tab when nothing more specific does (2026-10-07). One read per quiet spell,
    /// never a timer, so a busy or idle shell costs nothing.
    private var workingDirectoryCheck: Task<Void, Never>?

    private func scheduleWorkingDirectoryCheck() {
        guard workingDirectoryCheck == nil else { return }
        workingDirectoryCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            workingDirectoryCheck = nil
            if let directory = currentWorkingDirectory {
                delegateProxy.hostCurrentDirectoryUpdate(source: terminalView, directory: directory)
            }
        }
    }

    private func recordProcessOutput(_ bytes: ArraySlice<UInt8>, duration: Duration) {
        performanceDiagnostics.recordFeed(byteCount: bytes.count, duration: duration)
        emitBounded(Data(bytes), to: onOutputData)
        refreshAccessibilityViewport()
    }

    private func updatePTYSize() {
        guard terminalView.process.running else { return }
        let terminal = terminalView.getTerminal()
        terminalView.sizeChanged(
            source: terminalView,
            newCols: terminal.cols,
            newRows: terminal.rows
        )
    }

    private func applyTheme(_ theme: SwiftTermTheme) {
        terminalView.clearBlacks.configure(theme)
        let fontSize = max(10, theme.fontSize)
        terminalView.font = theme.fontName == "SF Mono"
            ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : NSFont(name: theme.fontName, size: fontSize)
                ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminalView.nativeForegroundColor = NSColor(
            srgbRed: theme.foreground.red,
            green: theme.foreground.green,
            blue: theme.foreground.blue,
            alpha: 1
        )
        terminalView.nativeBackgroundColor = NSColor(
            srgbRed: theme.background.red,
            green: theme.background.green,
            blue: theme.background.blue,
            alpha: theme.background.alpha
        )
        terminalView.caretColor = NSColor(
            srgbRed: theme.cursor.red,
            green: theme.cursor.green,
            blue: theme.cursor.blue,
            alpha: 1
        )
        terminalView.selectedTextBackgroundColor = NSColor(
            srgbRed: theme.selection.red,
            green: theme.selection.green,
            blue: theme.selection.blue,
            alpha: theme.selection.alpha
        )
        terminalView.layer?.backgroundColor = NSColor.clear.cgColor
        if theme.ansiColors.count == 16 {
            terminalView.installColors(theme.ansiColors.map { color in
                SwiftTerm.Color(
                    red: Self.terminalColorComponent(color.red),
                    green: Self.terminalColorComponent(color.green),
                    blue: Self.terminalColorComponent(color.blue)
                )
            })
        }
    }

    private func applyRuntimeSettings(_ settings: SwiftTermRuntimeSettings) {
        let normalizedStyle = settings.cursorStyle.lowercased()
        let cursorStyle: CursorStyle
        switch (normalizedStyle, settings.blinkingCursor) {
        case ("underline", true): cursorStyle = .blinkUnderline
        case ("underline", false): cursorStyle = .steadyUnderline
        case ("bar", true): cursorStyle = .blinkBar
        case ("bar", false): cursorStyle = .steadyBar
        case (_, true): cursorStyle = .blinkBlock
        case (_, false): cursorStyle = .steadyBlock
        }
        terminalView.getTerminal().setCursorStyle(cursorStyle)
        terminalView.changeScrollback(settings.scrollbackLines)
        terminalView.optionAsMetaKey = settings.optionAsMetaKey
    }

    private func publishRendererDiagnostics() {
        let diagnostics = SwiftTermRendererDiagnostics(
            backend: .coreGraphicsFallback,
            isWindowAttached: terminalView.window != nil,
            hostBackingIsClear: terminalView.layer?.backgroundColor?.alpha == 0,
            rendererBackingIsClear: true,
            failureDescription: nil
        )
        rendererDiagnostics = diagnostics
        onRendererDiagnostics(diagnostics)
    }

    private func emitBounded(_ data: Data, to callback: (Data) -> Void) {
        guard !data.isEmpty else { return }
        var offset = data.startIndex
        while offset < data.endIndex {
            let end = data.index(
                offset,
                offsetBy: min(Self.maximumRecordingCallbackBytes, data.distance(from: offset, to: data.endIndex))
            )
            callback(Data(data[offset..<end]))
            offset = end
        }
    }

    private static func terminalColorComponent(_ component: Double) -> UInt16 {
        UInt16((min(1, max(0, component)) * Double(UInt16.max)).rounded())
    }
}

/// Explicit lifecycle owner for a local terminal engine. Workspace models keep
/// this object alive while SwiftUI replaces inactive tab content; only pane,
/// tab, or window closure calls `terminate()`.
@MainActor
public final class SwiftTermLocalProcessRuntime {
    public let model: SwiftTermHostModel
    public let processState: SwiftTermLocalProcessState
    public var launchedShell: String? { engine?.launchedShell }

    /// True for foreground or background jobs, false for an inspected idle
    /// shell, and nil when process inspection is unavailable.
    public var hasActiveChildProcesses: Bool? { engine?.hasActiveChildProcesses }

    /// The command line of the program in the terminal's foreground — the shell itself when it is
    /// idle; nil when it cannot be read. What tells which AI agent a terminal runs (2026-10-14).
    public var foregroundCommandLine: String? { engine?.foregroundCommandLine }

    /// Read the owned shell's directory even when it has no OSC 7 integration.
    public var currentWorkingDirectory: String? {
        if let directory = engine?.currentWorkingDirectory { return directory }
        guard let reported = processState.currentDirectory else { return nil }
        if reported.hasPrefix("/") { return reported }
        guard let url = URL(string: reported), url.isFileURL else { return nil }
        return url.path
    }

    private var engine: MacLocalProcessEngine?

    public init(
        model: SwiftTermHostModel = SwiftTermHostModel(),
        processState: SwiftTermLocalProcessState = SwiftTermLocalProcessState()
    ) {
        self.model = model
        self.processState = processState
    }

    isolated deinit {
        engine?.terminateLocalProcess()
    }

    public var hasEngine: Bool { engine != nil }

    /// Starts a workspace-owned PTY without requiring the tab's SwiftUI view to
    /// exist. Presenting the tab later attaches to this same engine and buffer.
    /// Repeated calls do not restart the process or replay its ready callback.
    public func start(
        configuration: SwiftTermLocalProcessConfiguration = .init(),
        theme: SwiftTermTheme,
        runtimeSettings: SwiftTermRuntimeSettings,
        onOutputData: @escaping (Data) -> Void = { _ in },
        onInputData: @escaping (Data) -> Void = { _ in },
        onResize: @escaping (Int, Int) -> Void = { _, _ in },
        onTitleChanged: @escaping (String) -> Void = { _ in },
        onCurrentDirectoryChanged: @escaping (String?) -> Void = { _ in },
        onBell: @escaping () -> Void = {},
        onProcessReady: @escaping () -> Void = {},
        onProcessTerminated: @escaping (Int32?) -> Void = { _ in }
    ) {
        guard engine == nil else { return }
        model.setFocusOwnershipAllowed(false)
        let resolved = resolveEngine(
            onPasteRequest: { [weak model] text, bracketed in
                model?.requestPaste(text, bracketed: bracketed)
            },
            onOutputData: onOutputData,
            onInputData: onInputData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onCurrentDirectoryChanged: onCurrentDirectoryChanged,
            onBell: onBell,
            onProcessReady: onProcessReady,
            onProcessTerminated: onProcessTerminated,
            onRendererDiagnostics: { [weak model] diagnostics in
                model?.updateRendererDiagnostics(diagnostics)
            },
            onOSC52Decision: { [weak model] decision in
                model?.recordOSC52Decision(decision)
            }
        )
        // Give programs a usable initial grid before a window supplies its real
        // dimensions. The existing view resize delegate updates the PTY later.
        resolved.engine.hostView.setFrameSize(NSSize(width: 800, height: 480))
        model.attach(resolved.engine)
        processState.attach(resolved.engine)
        resolved.engine.configure(theme: theme, runtimeSettings: runtimeSettings)
        resolved.engine.start(configuration)
    }

    public func terminate() {
        engine?.terminateLocalProcess()
        engine = nil
    }

    fileprivate func resolveEngine(
        onPasteRequest: @escaping (String, Bool) -> Void,
        onOutputData: @escaping (Data) -> Void,
        onInputData: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        onTitleChanged: @escaping (String) -> Void,
        onCurrentDirectoryChanged: @escaping (String?) -> Void,
        onBell: @escaping () -> Void,
        onProcessReady: @escaping () -> Void,
        onProcessTerminated: @escaping (Int32?) -> Void,
        onRendererDiagnostics: @escaping (SwiftTermRendererDiagnostics) -> Void,
        onOSC52Decision: @escaping (SwiftTermOSC52Decision) -> Void
    ) -> (engine: MacLocalProcessEngine, isNew: Bool) {
        if let engine {
            engine.updateCallbacks(
                hostModel: model,
                processState: processState,
                onPasteRequest: onPasteRequest,
                onOutputData: onOutputData,
                onInputData: onInputData,
                onResize: onResize,
                onTitleChanged: onTitleChanged,
                onCurrentDirectoryChanged: onCurrentDirectoryChanged,
                onBell: onBell,
                onProcessReady: onProcessReady,
                onProcessTerminated: onProcessTerminated,
                onRendererDiagnostics: onRendererDiagnostics,
                onOSC52Decision: onOSC52Decision
            )
            return (engine, false)
        }

        let engine = MacLocalProcessEngine(
            hostModel: model,
            processState: processState,
            onPasteRequest: onPasteRequest,
            onOutputData: onOutputData,
            onInputData: onInputData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onCurrentDirectoryChanged: onCurrentDirectoryChanged,
            onBell: onBell,
            onProcessReady: onProcessReady,
            onProcessTerminated: onProcessTerminated,
            onRendererDiagnostics: onRendererDiagnostics,
            onOSC52Decision: onOSC52Decision
        )
        self.engine = engine
        return (engine, true)
    }
}

/// An AppKit SwiftTerm host backed by a real local pseudo-terminal. A workspace
/// runtime keeps the PTY alive across representable reconstruction. The legacy
/// initializer retains view-owned teardown for standalone hosts and tests.
public struct SwiftTermLocalProcessHostView: NSViewRepresentable {
    let runtime: SwiftTermLocalProcessRuntime
    let terminatesOnDismantle: Bool
    @ObservedObject var model: SwiftTermHostModel
    @ObservedObject var processState: SwiftTermLocalProcessState
    let configuration: SwiftTermLocalProcessConfiguration
    let theme: SwiftTermTheme
    let runtimeSettings: SwiftTermRuntimeSettings
    let onOutputData: (Data) -> Void
    let onInputData: (Data) -> Void
    let onResize: (Int, Int) -> Void
    let onTitleChanged: (String) -> Void
    let onCurrentDirectoryChanged: (String?) -> Void
    let onBell: () -> Void
    let onProcessReady: () -> Void
    let onProcessTerminated: (Int32?) -> Void

    public init(
        model: SwiftTermHostModel,
        processState: SwiftTermLocalProcessState,
        configuration: SwiftTermLocalProcessConfiguration = .init(),
        theme: SwiftTermTheme,
        runtimeSettings: SwiftTermRuntimeSettings,
        onOutputData: @escaping (Data) -> Void = { _ in },
        onInputData: @escaping (Data) -> Void = { _ in },
        onResize: @escaping (Int, Int) -> Void = { _, _ in },
        onTitleChanged: @escaping (String) -> Void = { _ in },
        onCurrentDirectoryChanged: @escaping (String?) -> Void = { _ in },
        onBell: @escaping () -> Void = {},
        onProcessReady: @escaping () -> Void = {},
        onProcessTerminated: @escaping (Int32?) -> Void = { _ in }
    ) {
        self.runtime = SwiftTermLocalProcessRuntime(
            model: model,
            processState: processState
        )
        self.terminatesOnDismantle = true
        self.model = model
        self.processState = processState
        self.configuration = configuration
        self.theme = theme
        self.runtimeSettings = runtimeSettings
        self.onOutputData = onOutputData
        self.onInputData = onInputData
        self.onResize = onResize
        self.onTitleChanged = onTitleChanged
        self.onCurrentDirectoryChanged = onCurrentDirectoryChanged
        self.onBell = onBell
        self.onProcessReady = onProcessReady
        self.onProcessTerminated = onProcessTerminated
    }

    public init(
        runtime: SwiftTermLocalProcessRuntime,
        configuration: SwiftTermLocalProcessConfiguration = .init(),
        theme: SwiftTermTheme,
        runtimeSettings: SwiftTermRuntimeSettings,
        onOutputData: @escaping (Data) -> Void = { _ in },
        onInputData: @escaping (Data) -> Void = { _ in },
        onResize: @escaping (Int, Int) -> Void = { _, _ in },
        onTitleChanged: @escaping (String) -> Void = { _ in },
        onCurrentDirectoryChanged: @escaping (String?) -> Void = { _ in },
        onBell: @escaping () -> Void = {},
        onProcessReady: @escaping () -> Void = {},
        onProcessTerminated: @escaping (Int32?) -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.terminatesOnDismantle = false
        self.model = runtime.model
        self.processState = runtime.processState
        self.configuration = configuration
        self.theme = theme
        self.runtimeSettings = runtimeSettings
        self.onOutputData = onOutputData
        self.onInputData = onInputData
        self.onResize = onResize
        self.onTitleChanged = onTitleChanged
        self.onCurrentDirectoryChanged = onCurrentDirectoryChanged
        self.onBell = onBell
        self.onProcessReady = onProcessReady
        self.onProcessTerminated = onProcessTerminated
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(terminatesOnDismantle: terminatesOnDismantle)
    }

    public func makeNSView(context: Context) -> NSView {
        let resolved = runtime.resolveEngine(
            onPasteRequest: { [weak model] text, bracketed in
                model?.requestPaste(text, bracketed: bracketed)
            },
            onOutputData: onOutputData,
            onInputData: onInputData,
            onResize: onResize,
            onTitleChanged: onTitleChanged,
            onCurrentDirectoryChanged: onCurrentDirectoryChanged,
            onBell: onBell,
            onProcessReady: onProcessReady,
            onProcessTerminated: onProcessTerminated,
            onRendererDiagnostics: { [weak model] diagnostics in
                model?.updateRendererDiagnostics(diagnostics)
            },
            onOSC52Decision: { [weak model] decision in
                model?.recordOSC52Decision(decision)
            }
        )
        let engine = resolved.engine
        let coordinator = context.coordinator
        coordinator.engine = engine
        coordinator.lastTheme = theme
        coordinator.lastRuntimeSettings = runtimeSettings
        DispatchQueue.main.async {
            guard coordinator.engine === engine else { return }
            model.attach(engine)
            processState.attach(engine)
            engine.configure(theme: theme, runtimeSettings: runtimeSettings)
            // Any engine that has never started, not only one this call made: a view torn down
            // before this block ran left its engine unstarted, and every later view found it
            // already made, so the pane showed a terminal with no shell (2026-10-08).
            if !engine.hasStarted {
                engine.start(configuration)
            }
            coordinator.isReady = true
        }
        return engine.hostView
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let engine = context.coordinator.engine,
              engine.hostView === nsView,
              context.coordinator.isReady else { return }
        if context.coordinator.lastTheme != theme
            || context.coordinator.lastRuntimeSettings != runtimeSettings {
            context.coordinator.lastTheme = theme
            context.coordinator.lastRuntimeSettings = runtimeSettings
            engine.configure(theme: theme, runtimeSettings: runtimeSettings)
        }
        model.attach(engine)
        processState.attach(engine)
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if coordinator.terminatesOnDismantle {
            coordinator.engine?.terminateLocalProcess()
        } else {
            coordinator.engine?.resignFocus()
        }
        coordinator.engine = nil
        coordinator.isReady = false
    }

    @MainActor
    public final class Coordinator {
        fileprivate let terminatesOnDismantle: Bool
        fileprivate var engine: MacLocalProcessEngine?
        fileprivate var isReady = false
        fileprivate var lastTheme: SwiftTermTheme?
        fileprivate var lastRuntimeSettings: SwiftTermRuntimeSettings?

        fileprivate init(terminatesOnDismantle: Bool) {
            self.terminatesOnDismantle = terminatesOnDismantle
        }
    }
}
#endif

#if canImport(UIKit)
/// What SwiftTerm sends for each arrow (`iOSTerminalView.pressesBegan`): the cursor keys in normal or
/// application mode, and Option or Control with Left and Right as a word back or forward.
enum SwiftTermArrowKeys {
    static func bytes(input: String, modifiers: UIKeyModifierFlags, applicationCursor: Bool) -> [UInt8]? {
        switch input {
        case UIKeyCommand.inputUpArrow:
            return applicationCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal
        case UIKeyCommand.inputDownArrow:
            return applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal
        case UIKeyCommand.inputLeftArrow:
            if modifiers.contains(.alternate) { return EscapeSequences.emacsBack }
            if modifiers.contains(.control) { return EscapeSequences.controlLeft }
            return applicationCursor ? EscapeSequences.moveLeftApp : EscapeSequences.moveLeftNormal
        case UIKeyCommand.inputRightArrow:
            if modifiers.contains(.alternate) { return EscapeSequences.emacsForward }
            if modifiers.contains(.control) { return EscapeSequences.controlRight }
            return applicationCursor ? EscapeSequences.moveRightApp : EscapeSequences.moveRightNormal
        default:
            return nil
        }
    }
}
#endif
