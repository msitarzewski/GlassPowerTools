//
//  UITestCapture.swift
//  GlassPowerToolsUITests
//
//  One screenshot helper for every suite. Project rule 11: capture our own windows only, never
//  a whole display — on the user's two-display Mac a display capture shows other applications.
//
//  Element screenshots do that on iOS and visionOS. On macOS `XCUIElement.screenshot()` fails
//  ("Image creation failed") whenever the window sits on a display other than the primary one,
//  which is where the app opens when the user works there. So on macOS the helper finds the
//  display that holds the window, captures that display, and crops the image to the window's
//  frame — the same content an element screenshot would give.
//

import XCTest
#if os(macOS)
import AppKit
#endif

extension XCTestCase {
    var uiTestPlatformName: String {
        #if os(macOS)
        "mac"
        #elseif os(visionOS)
        "vision"
        #else
        "ios"
        #endif
    }

    /// Attaches a capture of `subject` (the app's own window, sheet or view) under `name`, and
    /// writes it as `<platform>-<name>.png` under `GPT_SHOTS_DIR` when that is set. A capture
    /// that cannot be produced is recorded as an activity, never as a failure: the screenshot
    /// is evidence, not the behaviour under test.
    func captureOwnWindow(_ subject: XCUIElement, app: XCUIApplication, name: String) {
        let fileName = "\(uiTestPlatformName)-\(name).png"
        guard let png = ownWindowPNG(subject, app: app) else {
            XCTContext.runActivity(named: "capture \(name): no image (subject frame \(subject.exists ? "\(subject.frame)" : "missing"))") { _ in }
            return
        }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["GPT_SHOTS_DIR"] {
            let url = URL(fileURLWithPath: dir, isDirectory: true).appendingPathComponent(fileName)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: url)
        }
    }

    private func ownWindowPNG(_ subject: XCUIElement, app: XCUIApplication) -> Data? {
        #if os(macOS)
        // The display crop shows whatever is frontmost in the window's rectangle, so make sure
        // that is our window: the user may be working in another application on that display.
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let frame = subject.exists ? subject.frame : app.windows.firstMatch.frame
        guard !frame.isEmpty else { return nil }
        return Self.croppedDisplayCapture(of: frame)
        #else
        let target = subject.exists ? subject : app
        return target.screenshot().pngRepresentation
        #endif
    }

    #if os(macOS)
    /// XCUITest frames use a top-left origin at the primary display's top-left corner; AppKit's
    /// use a bottom-left origin there. Locate the display containing `frame`, capture it, and
    /// crop to `frame` in that display's pixels.
    private static func croppedDisplayCapture(of frame: CGRect) -> Data? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        let primaryHeight = primary.frame.height
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        var located: (index: Int, screen: NSScreen, rect: CGRect)?
        for (index, screen) in screens.enumerated() {
            let f = screen.frame
            let xcuiRect = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            if xcuiRect.contains(centre) { located = (index, screen, xcuiRect); break }
        }
        guard let located else { return nil }
        // XCUIScreen.screens lists the main screen first, like NSScreen.screens; confirm by size
        // and fall back to a size match if the orders differ.
        let xcuiScreens = XCUIScreen.screens
        let expectedPixels = CGSize(width: located.screen.frame.width * located.screen.backingScaleFactor,
                                    height: located.screen.frame.height * located.screen.backingScaleFactor)
        var capture: XCUIScreenshot?
        if xcuiScreens.indices.contains(located.index) {
            let shot = xcuiScreens[located.index].screenshot()
            if Self.pixelSize(of: shot.image) == expectedPixels { capture = shot }
        }
        if capture == nil {
            capture = xcuiScreens.map { $0.screenshot() }.first { Self.pixelSize(of: $0.image) == expectedPixels }
        }
        guard let capture, let cgImage = capture.image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = located.screen.backingScaleFactor
        let local = CGRect(x: (frame.minX - located.rect.minX) * scale, y: (frame.minY - located.rect.minY) * scale,
                           width: frame.width * scale, height: frame.height * scale)
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        guard let cropped = cgImage.cropping(to: local.intersection(bounds).integral) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cropped)
        return rep.representation(using: .png, properties: [:])
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .zero }
        return CGSize(width: cg.width, height: cg.height)
    }
    #endif
}
