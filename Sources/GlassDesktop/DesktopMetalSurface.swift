import SwiftUI
import MetalKit
import GlassConnectionUI
import GlassRDPTransport

#if os(macOS)
import AppKit
struct DesktopMetalSurface: NSViewRepresentable {
    let session: DesktopSessionModel
    /// The window this surface is in (W30); nil is the desktop's own.
    var viewport: DesktopViewport?
    var inputEnabled = true
    func makeNSView(context: Context) -> DesktopMTKView { DesktopMTKView(session: session, inputEnabled: inputEnabled) }
    func updateNSView(_ view: DesktopMTKView, context: Context) { view.update(session, viewport: viewport, inputEnabled: inputEnabled) }
    static func dismantleNSView(_ view: DesktopMTKView, coordinator: ()) { view.shutdown() }
}
#else
import UIKit
struct DesktopMetalSurface: UIViewRepresentable {
    let session: DesktopSessionModel
    /// The window this surface is in (W30); nil is the desktop's own.
    var viewport: DesktopViewport?
    var inputEnabled = true
    func makeUIView(context: Context) -> DesktopMTKView { DesktopMTKView(session: session, inputEnabled: inputEnabled) }
    func updateUIView(_ view: DesktopMTKView, context: Context) { view.update(session, viewport: viewport, inputEnabled: inputEnabled) }
    static func dismantleUIView(_ view: DesktopMTKView, coordinator: ()) { view.shutdown() }
}
#endif

@MainActor
final class DesktopMTKView: MTKView {
    var input: DesktopInput?
    private var renderer: DesktopMetalRenderer?
    private(set) var inputEnabled = true
    private weak var session: DesktopSessionModel?
    /// The window: its display, zoom, pan and pointer (W30). Nil is the desktop's own window.
    private weak var viewport: DesktopViewport?
    private var shown: DesktopViewport? { viewport ?? session?.primaryViewport }
    private weak var inputTransport: (any GlassDesktopTransport)?
    private var pressedKeys = Set<UInt16>()
    private var lastCapsLock: Bool?
    private var wasConnected = false
    #if os(macOS)
    private var tracking: NSTrackingArea?
    private var marked = NSAttributedString(string: "")
    private var markedSelection = NSRange(location: 0, length: 0)
    private var compositionLabel: NSTextField?
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { inputEnabled }
    override var isFlipped: Bool { true }
    #else
    private var hasInputGestures = false
    private var activeButton = GlassRDPPointerButton.left
    private var modifierState = DesktopModifierState()
    private var scrollTranslation = CGPoint.zero
    private var pinchStartZoom: Double = 1
    #if os(iOS)
    private var trackpad: TrackpadPointerController?
    /// Only the first finger down steers the pointer. UIKit reports just the touches that changed in
    /// each event, so counting them would mistake an arriving second finger for the pointing one and
    /// jump the cursor to wherever that finger landed.
    private weak var primaryTouch: UITouch?
    private var pointerMode = DesktopPointerMode.trackpad
    /// A zero-height input view keeps this the first responder for hardware keys while leaving the
    /// software keyboard hidden until it is explicitly asked for.
    private let suppressedKeyboard = UIView(frame: .zero)
    var wantsSoftwareKeyboard = false {
        didSet { if wantsSoftwareKeyboard != oldValue { reloadInputViews() } }
    }
    #endif
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    override var canBecomeFirstResponder: Bool { inputEnabled }
    #endif

    init(session: DesktopSessionModel, inputEnabled: Bool = true) {
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        configure(session)
        setInputEnabled(inputEnabled)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        // Decoding a view configures its presentation; the owning representable supplies a session through update.
        setupPresentation()
    }

    private func setupPresentation() {
        if device == nil { device = MTLCreateSystemDefaultDevice() }
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        framebufferOnly = true
        isPaused = true
        enableSetNeedsDisplay = true
        #if os(macOS)
        wantsLayer = true
        layer?.isOpaque = false
        setAccessibilityLabel("Remote desktop")
        #else
        isOpaque = false
        backgroundColor = .clear
        accessibilityLabel = "Remote desktop"
        isAccessibilityElement = true
        isMultipleTouchEnabled = true
        #endif
    }

    private func configure(_ session: DesktopSessionModel) {
        self.session = session
        inputTransport = session.transport
        setupPresentation()
        input = DesktopInput(session: session.transport) { [weak session] in session?.errorMessage = $0 }
        guard let device else { session.rendererError = RendererError.unavailable.localizedDescription; return }
        do {
            renderer = try DesktopMetalRenderer(device: device, pixelFormat: colorPixelFormat) { [weak session] in session?.rendererError = $0 }
            delegate = renderer
        } catch { session.rendererError = error.localizedDescription }
        #if !os(macOS)
        if !hasInputGestures {
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hover(_:))))
            // Two fingers on the glass.
            let scroll = UIPanGestureRecognizer(target: self, action: #selector(scrollGesture(_:)))
            scroll.minimumNumberOfTouches = 2
            scroll.maximumNumberOfTouches = 2
            addGestureRecognizer(scroll)
            // Scroll events with no touch at all: a trackpad or mouse wheel on an iPad, and a Mac's
            // trackpad driving Vision Pro. They carry zero touches, so the two-touch recognizer
            // above never saw them — a two-finger swipe on a MacBook's trackpad did not scroll the
            // remote desktop on the headset (2026-10-05). Scroll events only, no touches.
            let wheel = UIPanGestureRecognizer(target: self, action: #selector(scrollGesture(_:)))
            wheel.allowedScrollTypesMask = .all
            wheel.allowedTouchTypes = []
            addGestureRecognizer(wheel)
            // Pinch zooms this window's own image. It never touches the remote desktop, so it works
            // even on a host that cannot resize, and it runs alongside the two-finger scroll.
            // visionOS is excluded on purpose: there a pinch is the system's select gesture, so
            // claiming it here would fight every tap. That platform resizes the window instead.
            #if !os(visionOS)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinchGesture(_:)))
            pinch.delegate = self
            addGestureRecognizer(pinch)
            #endif
            #if os(iOS)
            let secondary = UITapGestureRecognizer(target: self, action: #selector(secondaryTapGesture(_:)))
            secondary.numberOfTouchesRequired = 2
            secondary.delegate = self
            addGestureRecognizer(secondary)
            #endif
            hasInputGestures = true
        }
        #endif
    }

    func update(_ session: DesktopSessionModel, viewport: DesktopViewport? = nil, inputEnabled: Bool = true) {
        if self.session !== session { shutdown(); configure(session) }
        self.viewport = viewport
        let shown = viewport ?? session.primaryViewport
        if inputTransport !== session.transport || session.isConnected != wasConnected {
            input?.stop()
            input = DesktopInput(session: session.transport) { [weak session] in session?.errorMessage = $0 }
            inputTransport = session.transport
            releaseFocusState()
            wasConnected = session.isConnected
        }
        setInputEnabled(inputEnabled)
        #if os(iOS)
        if pointerMode != shown.pointerMode {
            pointerMode = shown.pointerMode
            trackpad = nil
            input?.send(.release)
        }
        wantsSoftwareKeyboard = session.wantsKeyboard && inputEnabled
        if wantsSoftwareKeyboard, !isFirstResponder { becomeFirstResponder() }
        #endif
        renderer?.frame = session.frame
        renderer?.region = session.region(for: shown)
        renderer?.settings = shown.presentation
        renderer?.setWallpaper(session.wallpaperURL)
        #if os(macOS)
        if let window { GlassWindowChrome.installTitlebarMaterial(in: window) }
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }

    func shutdown() {
        setInputEnabled(false)
        input?.stop()
        input = nil
        renderer?.frame = nil
        renderer?.setWallpaper(nil)
        delegate = nil
        renderer = nil
        session = nil
        inputTransport = nil
        releaseFocusState()
    }

    private func setInputEnabled(_ enabled: Bool) {
        guard inputEnabled != enabled else { return }
        inputEnabled = enabled
        #if !os(macOS)
        isUserInteractionEnabled = enabled
        #endif
        guard !enabled else { return }
        // The queue discards unsent events and releases after any event already in flight.
        releaseFocusState()
        #if os(macOS)
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        #else
        if isFirstResponder { _ = resignFirstResponder() }
        #endif
    }

    private func releaseFocusState() {
        input?.send(.release)
        pressedKeys.removeAll()
        lastCapsLock = nil
        #if os(macOS)
        unmarkText()
        #else
        modifierState.reset()
        scrollTranslation = .zero
        activeButton = .left
        #endif
    }

    private func synchronizeCapsLock(_ enabled: Bool) {
        guard inputEnabled, session?.isConnected == true, lastCapsLock != enabled else { return }
        input?.send(.synchronize(enabled))
        lastCapsLock = enabled
    }

    private func point(_ location: CGPoint, clamp: Bool = false) -> DesktopPoint? {
        guard inputEnabled, let session, let shown, session.isConnected else { return nil }
        // Input follows this window's region, so clicks land on the display it shows: a point in a
        // display window lands inside that display's rectangle of the framebuffer (W30).
        let region = session.region(for: shown)
        let mapped = DesktopCoordinates.map(x: location.x, y: location.y, viewWidth: bounds.width,
                                      viewHeight: bounds.height, desktop: region.size,
                                      origin: region.origin, clamp: clamp)
        if let mapped { session.pointerPosition = mapped }
        return mapped
    }

    #if os(macOS)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { inputEnabled }
    override func hitTest(_ point: NSPoint) -> NSView? { inputEnabled ? super.hitTest(point) : nil }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window { NotificationCenter.default.addObserver(self, selector: #selector(windowLostFocus(_:)), name: NSWindow.didResignKeyNotification, object: window) }
        window?.acceptsMouseMovedEvents = true
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
        if let window { GlassWindowChrome.installTitlebarMaterial(in: window) }
        if window == nil { releaseFocusState() }
    }
    @objc private func windowLostFocus(_ notification: Notification) { releaseFocusState() }
    override func becomeFirstResponder() -> Bool {
        guard inputEnabled else { return false }
        let accepted = super.becomeFirstResponder()
        if accepted { synchronizeCapsLock(NSEvent.modifierFlags.contains(.capsLock)) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        releaseFocusState()
        return super.resignFirstResponder()
    }
    override func mouseMoved(with event: NSEvent) {
        if let point = point(convert(event.locationInWindow, from: nil)) { input?.send(.move(point)) }
    }
    override func mouseDragged(with event: NSEvent) { drag(event) }
    override func rightMouseDragged(with event: NSEvent) { drag(event) }
    override func otherMouseDragged(with event: NSEvent) { drag(event) }
    private func drag(_ event: NSEvent) {
        if let point = point(convert(event.locationInWindow, from: nil), clamp: true) { input?.send(.move(point)) }
    }
    override func mouseDown(with event: NSEvent) { guard inputEnabled else { return }; window?.makeFirstResponder(self); button(.left, true, event) }
    override func mouseUp(with event: NSEvent) { button(.left, false, event) }
    override func rightMouseDown(with event: NSEvent) { guard inputEnabled else { return }; window?.makeFirstResponder(self); button(.right, true, event) }
    override func rightMouseUp(with event: NSEvent) { button(.right, false, event) }
    override func otherMouseDown(with event: NSEvent) { guard inputEnabled else { return }; window?.makeFirstResponder(self); button(otherButton(event), true, event) }
    override func otherMouseUp(with event: NSEvent) { button(otherButton(event), false, event) }
    private func otherButton(_ event: NSEvent) -> GlassRDPPointerButton { event.buttonNumber == 3 ? .back : (event.buttonNumber == 4 ? .forward : .middle) }
    private func button(_ button: GlassRDPPointerButton, _ down: Bool, _ event: NSEvent) {
        if let point = point(convert(event.locationInWindow, from: nil), clamp: !down) { input?.send(.button(button, down, point)) }
    }
    override func scrollWheel(with event: NSEvent) {
        guard let point = point(convert(event.locationInWindow, from: nil)) else { return }
        let multiplier = event.hasPreciseScrollingDeltas ? 10.0 : 120.0
        input?.send(.scroll(Int((event.scrollingDeltaY * multiplier).rounded()), Int((event.scrollingDeltaX * multiplier).rounded()), point))
    }
    override func keyDown(with event: NSEvent) {
        guard inputEnabled else { return }
        guard session?.isConnected == true else { super.keyDown(with: event); return }
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .shift, .control, .option]) == [.command, .shift] {
            window?.makeFirstResponder(nil); return
        }
        synchronizeCapsLock(event.modifierFlags.contains(.capsLock))
        synchronizeMacModifiers(event.modifierFlags)
        if hasMarkedText() { interpretKeyEvents([event]); return }
        if let key = MacRDPKeyboardMapping.scancode(forKeyCode: event.keyCode), MacRDPKeyboardMapping.shouldSendScancode(for: event) {
            pressedKeys.insert(event.keyCode)
            input?.send(.key(key.code, key.isExtended, true, event.isARepeat))
        } else { interpretKeyEvents([event]) }
    }
    override func keyUp(with event: NSEvent) {
        guard inputEnabled, pressedKeys.remove(event.keyCode) != nil, let key = MacRDPKeyboardMapping.scancode(forKeyCode: event.keyCode) else { return }
        input?.send(.key(key.code, key.isExtended, false, false))
    }
    override func flagsChanged(with event: NSEvent) {
        guard inputEnabled, session?.isConnected == true else { return }
        synchronizeCapsLock(event.modifierFlags.contains(.capsLock))
        guard let key = MacRDPKeyboardMapping.modifierScancode(forKeyCode: event.keyCode) else { return }
        let down = MacRDPKeyboardMapping.modifierFlag(forKeyCode: event.keyCode).map { event.modifierFlags.contains($0) } == true
            && !pressedKeys.contains(event.keyCode)
        if down { pressedKeys.insert(event.keyCode) } else { pressedKeys.remove(event.keyCode) }
        input?.send(.key(key.code, key.isExtended, down, false))
    }
    private func synchronizeMacModifiers(_ flags: NSEvent.ModifierFlags) {
        let groups: [(NSEvent.ModifierFlags, [UInt16])] = [(.shift, [56, 60]), (.control, [59, 62]),
            (.option, [58, 61]), (.command, [55, 54])]
        for (flag, codes) in groups {
            let held = codes.filter { pressedKeys.contains($0) }
            if flags.contains(flag), held.isEmpty, let first = codes.first,
               let key = MacRDPKeyboardMapping.modifierScancode(forKeyCode: first) {
                pressedKeys.insert(first)
                input?.send(.key(key.code, key.isExtended, true, false))
            } else if !flags.contains(flag) {
                for code in held {
                    pressedKeys.remove(code)
                    if let key = MacRDPKeyboardMapping.modifierScancode(forKeyCode: code) { input?.send(.key(key.code, key.isExtended, false, false)) }
                }
            }
        }
    }
    override func doCommand(by selector: Selector) {
        guard inputEnabled, session?.isConnected == true else { return }
        if hasMarkedText() {
            if selector == #selector(NSResponder.cancelOperation(_:)) { unmarkText(); return }
            if selector == #selector(NSResponder.insertNewline(_:)) { insertText(marked, replacementRange: markedRange()); return }
        }
        let key: UInt16?
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): key = 0x1c
        case #selector(NSResponder.insertTab(_:)): key = 0x0f
        case #selector(NSResponder.deleteBackward(_:)): key = 0x0e
        case #selector(NSResponder.cancelOperation(_:)): key = 0x01
        default: key = nil
        }
        if let key { input?.send(.key(key, false, true, false)); input?.send(.key(key, false, false, false)) }
        else { super.doCommand(by: selector) }
    }
    #else
    override func resignFirstResponder() -> Bool {
        releaseFocusState()
        return super.resignFirstResponder()
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        if window != nil { NotificationCenter.default.addObserver(self, selector: #selector(applicationLostFocus(_:)), name: UIApplication.willResignActiveNotification, object: nil) }
        if window == nil { releaseFocusState() }
    }
    @objc private func applicationLostFocus(_ notification: Notification) { releaseFocusState() }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        becomeFirstResponder()
        #if os(iOS)
        if pointerMode == .trackpad {
            let active = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? touches.count
            guard active <= 1, primaryTouch == nil else {
                // More than one finger means a pinch or a two-finger tap, not pointing.
                endTrackpadInteraction()
                return
            }
            primaryTouch = touch
            withTrackpad { $0.began(at: touch.location(in: self), time: touch.timestamp) }
            return
        }
        #endif
        guard let point = point(touch.location(in: self)) else { return }
        activeButton = event?.buttonMask.contains(.secondary) == true ? .right : .left
        input?.send(.button(activeButton, true, point))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        #if os(iOS)
        if pointerMode == .trackpad {
            guard let primary = primaryTouch, touches.contains(primary) else { return }
            withTrackpad { $0.moved(to: primary.location(in: self), time: primary.timestamp) }
            return
        }
        #endif
        if let point = point(touch.location(in: self), clamp: true) { input?.send(.move(point)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputEnabled else { return }
        #if os(iOS)
        if pointerMode == .trackpad {
            guard let primary = primaryTouch, touches.contains(primary) else { return }
            primaryTouch = nil
            withTrackpad { $0.ended(time: primary.timestamp) }
            return
        }
        #endif
        if let touch = touches.first, let point = point(touch.location(in: self), clamp: true) { input?.send(.button(activeButton, false, point)) }
        else { input?.send(.release) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        #if os(iOS)
        if pointerMode == .trackpad {
            if let primary = primaryTouch, touches.contains(primary) { endTrackpadInteraction() }
            return
        }
        #endif
        input?.send(.release)
    }

    #if os(iOS)
    override var inputView: UIView? { wantsSoftwareKeyboard ? nil : suppressedKeyboard }

    /// Drops the pointing finger and releases anything it was dragging.
    private func endTrackpadInteraction() {
        guard primaryTouch != nil || trackpad?.isDragging == true else { return }
        primaryTouch = nil
        withTrackpad { $0.cancelled() }
    }

    @objc private func secondaryTapGesture(_ gesture: UITapGestureRecognizer) {
        guard inputEnabled, pointerMode == .trackpad, gesture.state == .ended else { return }
        withTrackpad { $0.secondaryTap() }
    }

    /// The controller is a value type, so it is mutated in place here and stored back. Reading a copy
    /// and mutating that would silently discard the cursor position.
    private func withTrackpad(_ body: (inout TrackpadPointerController) -> [TrackpadAction]) {
        let region = session.flatMap { session in shown.map { session.region(for: $0) } } ?? .whole(width: 1, height: 1)
        if trackpad == nil {
            trackpad = TrackpadPointerController(region: region, viewSize: bounds.size,
                                                 position: session?.pointerPosition)
        }
        guard var controller = trackpad else { return }
        controller.update(region: region, viewSize: bounds.size)
        let actions = body(&controller)
        trackpad = controller
        apply(actions, at: controller.position)
    }

    private func apply(_ actions: [TrackpadAction], at position: DesktopPoint) {
        for action in actions {
            switch action {
            case .move(let point):
                session?.pointerPosition = point
                input?.send(.move(point))
            case .press(let button):
                input?.send(.button(button == .right ? .right : .left, true, position))
            case .release(let button):
                input?.send(.button(button == .right ? .right : .left, false, position))
            }
        }
    }
    #endif
    @objc private func hover(_ gesture: UIHoverGestureRecognizer) {
        if let point = point(gesture.location(in: self)) { input?.send(.move(point)) }
    }
    @objc private func scrollGesture(_ gesture: UIPanGestureRecognizer) {
        guard inputEnabled else { return }
        if gesture.state == .began { input?.send(.release); scrollTranslation = .zero }
        let current = gesture.translation(in: self)
        let delta = CGPoint(x: current.x - scrollTranslation.x, y: current.y - scrollTranslation.y)
        scrollTranslation = current
        guard gesture.state == .began || gesture.state == .changed else { return }
        // While the image is zoomed in, two fingers move the view instead of scrolling the desktop,
        // because otherwise the parts outside the window would be unreachable.
        if let shown, shown.presentation.zoom > 1 {
            let panned = PresentationSettings.clampedPan(x: shown.presentation.panX + delta.x,
                                                         y: shown.presentation.panY + delta.y,
                                                         zoom: shown.presentation.zoom, viewport: bounds.size)
            shown.presentation.panX = panned.x
            shown.presentation.panY = panned.y
            return
        }
        guard let point = point(gesture.location(in: self), clamp: true) else { return }
        input?.send(.scroll(Int((delta.y * 10).rounded()), Int((delta.x * 10).rounded()), point))
    }

    #if !os(visionOS)
    @objc private func pinchGesture(_ gesture: UIPinchGestureRecognizer) {
        guard inputEnabled, let shown else { return }
        switch gesture.state {
        case .began:
            #if os(iOS)
            endTrackpadInteraction()
            #endif
            input?.send(.release)
            pinchStartZoom = shown.presentation.zoom
        case .changed:
            let candidate = pinchStartZoom * Double(gesture.scale)
            let bounded = min(DesktopZoomLimits.maximum, max(DesktopZoomLimits.minimum, candidate))
            // Settle on 100% so an exact one-to-one image is reachable with fingers.
            shown.presentation.zoom = abs(bounded - 1) < 0.02 ? 1 : bounded
            let panned = PresentationSettings.clampedPan(x: shown.presentation.panX, y: shown.presentation.panY,
                                                         zoom: shown.presentation.zoom, viewport: bounds.size)
            shown.presentation.panX = panned.x
            shown.presentation.panY = panned.y
        default:
            break
        }
    }
    #endif

    private func synchronizeUIKitModifiers(_ flags: UIKeyModifierFlags, changedUsage: Int, isDown: Bool) {
        synchronizeCapsLock(flags.contains(.alphaShift))
        for (key, down) in modifierState.update(shift: flags.contains(.shift), control: flags.contains(.control),
            alternate: flags.contains(.alternate), command: flags.contains(.command), changedUsage: changedUsage, isDown: isDown) {
            input?.send(.key(key.scancode, key.extended, down, false))
        }
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard inputEnabled else { super.pressesBegan(presses, with: event); return }
        guard session?.isConnected == true else { super.pressesBegan(presses, with: event); return }
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key else { unhandled.insert(press); continue }
            let usage = key.keyCode.rawValue
            synchronizeUIKitModifiers(key.modifierFlags, changedUsage: usage, isDown: true)
            if (224...231).contains(usage) || usage == 57 { continue }
            let special = usage >= 58 || [40,41,42,43].contains(usage)
            let shortcut = !key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty
            if usage == 41, key.modifierFlags.intersection([.command, .shift, .control, .alternate]) == [.command, .shift] { _ = resignFirstResponder(); continue }
            if (special || shortcut), let code = DesktopKeyboard.key(hidUsage: usage) {
                let repeated = !pressedKeys.insert(UInt16(usage)).inserted
                input?.send(.key(code.scancode, code.extended, true, repeated))
            } else { unhandled.insert(press) }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard inputEnabled else { super.pressesEnded(presses, with: event); return }
        var unhandled = Set<UIPress>()
        for press in presses {
            if let key = press.key {
                synchronizeUIKitModifiers(key.modifierFlags, changedUsage: key.keyCode.rawValue, isDown: false)
                if (224...231).contains(key.keyCode.rawValue) || key.keyCode.rawValue == 57 { continue }
            }
            if let key = press.key, pressedKeys.remove(UInt16(key.keyCode.rawValue)) != nil,
               let code = DesktopKeyboard.key(hidUsage: key.keyCode.rawValue) {
                input?.send(.key(code.scancode, code.extended, false, false))
            } else { unhandled.insert(press) }
        }
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        releaseFocusState()
        super.pressesCancelled(presses, with: event)
    }
    #endif
}

#if os(macOS)
extension DesktopMTKView: @MainActor NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard inputEnabled, session?.isConnected == true else { return }
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        unmarkText()
        if !text.isEmpty { input?.send(.text(text)) }
    }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard inputEnabled, session?.isConnected == true else { return }
        marked = (string as? NSAttributedString) ?? NSAttributedString(string: string as? String ?? "")
        let location = min(marked.length, selectedRange.location == NSNotFound ? marked.length : selectedRange.location)
        markedSelection = NSRange(location: location, length: min(selectedRange.length, marked.length - location))
        let label = compositionLabel ?? NSTextField(labelWithString: "")
        if compositionLabel == nil { addSubview(label); compositionLabel = label }
        label.drawsBackground = true
        label.backgroundColor = .textBackgroundColor
        label.attributedStringValue = marked
        label.sizeToFit()
        label.frame.origin = CGPoint(x: max(0, min(bounds.width - label.frame.width, bounds.midX)), y: bounds.midY)
        label.isHidden = marked.length == 0
    }
    func unmarkText() { marked = NSAttributedString(string: ""); markedSelection = NSRange(location: 0, length: 0); compositionLabel?.isHidden = true }
    func selectedRange() -> NSRange { markedSelection }
    func markedRange() -> NSRange { marked.length == 0 ? NSRange(location: NSNotFound, length: 0) : NSRange(location: 0, length: marked.length) }
    func hasMarkedText() -> Bool { marked.length > 0 }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [.underlineStyle, .markedClauseSegment] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard hasMarkedText(), range.location < marked.length else { return nil }
        let result = NSIntersectionRange(range, NSRange(location: 0, length: marked.length))
        actualRange?.pointee = result
        return marked.attributedSubstring(from: result)
    }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound } // The remote bitmap has no local document indices.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = markedRange()
        let local = NSRect(x: bounds.midX, y: bounds.midY, width: 1, height: 20)
        return window?.convertToScreen(convert(local, to: nil)) ?? local
    }
}
#else
extension DesktopMTKView: UIKeyInput {
    var hasText: Bool { true } // Backspace remains available even though the remote document is not locally inspectable.
    func insertText(_ text: String) {
        guard inputEnabled, session?.isConnected == true else { return }
        if text == "\n" || text == "\t" {
            let code: UInt16 = text == "\n" ? 0x1c : 0x0f
            input?.send(.key(code, false, true, false)); input?.send(.key(code, false, false, false))
        } else { input?.send(.text(text)) }
    }
    func deleteBackward() { guard inputEnabled, session?.isConnected == true else { return }; input?.send(.key(0x0e, false, true, false)); input?.send(.key(0x0e, false, false, false)) }
}
#endif

#if !os(macOS)
extension DesktopMTKView: UIGestureRecognizerDelegate {
    /// Pinch and the two-finger drag share the same touches, so both must be allowed to run.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif
