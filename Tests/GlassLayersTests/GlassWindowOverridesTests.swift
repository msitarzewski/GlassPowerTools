//
//  GlassWindowOverridesTests.swift
//  Glass Power Tools — GlassLayersTests
//
//  W22 (owner, 2026-10-10): "the original idea was that anything in the system settings could be
//  overridden per window." One mechanism for every kind of window: a window keeps only what it
//  sets, each value resolves as the window's else the setting's, records read leniently and keep
//  what a newer build added, and a window's glass draws with its own Appearance.
//

import Foundation
import SwiftUI
import Testing
@testable import GlassLayers

/// A capability's settings, as one declares them.
private enum ExampleWindowSettings {
    static let size = GlassWindowSetting<Double>("example.size", title: "Size") {
        $0.isFinite ? min(36, max(8, $0.rounded())) : nil
    }
    static let wraps = GlassWindowSetting<Bool>("example.wraps", title: "Wraps")
    static let name = GlassWindowSetting<String>("example.name", title: "Name")
    static let lines = GlassWindowSetting<Int>("example.lines", title: "Lines")
}

@Suite("A window's own settings over the app's (W22)")
struct GlassWindowOverridesTests {
    private typealias S = ExampleWindowSettings

    private func json(_ overrides: GlassWindowOverrides) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(overrides)) as? [String: Any])
    }

    private func decoded(_ object: Any) throws -> GlassWindowOverrides {
        try JSONDecoder().decode(GlassWindowOverrides.self, from: JSONSerialization.data(withJSONObject: object,
                                                                                       options: .fragmentsAllowed))
    }

    @Test("each setting the window sets wins; every other follows its setting")
    func resolution() {
        var window = GlassWindowOverrides()
        #expect(window.isEmpty)
        #expect(window.value(of: S.size, over: 13) == 13, "a window that sets nothing follows every setting")

        window[S.size] = 18
        window[S.wraps] = false
        #expect(window.value(of: S.size, over: 13) == 18)
        #expect(window.value(of: S.wraps, over: true) == false)
        #expect(window.value(of: S.name, over: "Menlo") == "Menlo", "left unset, it follows")
        #expect(window.sets(S.size) && !window.sets(S.name))

        window[S.size] = nil
        #expect(window.value(of: S.size, over: 13) == 13, "reset: back to following")
        window.reset(S.wraps.key)
        #expect(window.isEmpty)
    }

    @Test("only the settings a window sets are stored: one flat object, nothing for the rest")
    func onlyWhatIsSetIsStored() throws {
        var window = GlassWindowOverrides()
        window[S.size] = 18
        window[S.name] = "Menlo"
        window[S.lines] = 5000
        window[S.wraps] = true
        let object = try json(window)
        #expect(object.count == 4)
        #expect(object["example.size"] as? Double == 18)
        #expect(object["example.name"] as? String == "Menlo")
        #expect(object["example.lines"] as? Int == 5000)
        #expect(object["example.wraps"] as? Bool == true)
        #expect(try decoded(object) == window, "and read back as it was")

        struct Record: Codable { var settings: GlassWindowOverrides
            enum CodingKeys: CodingKey { case settings }
            func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encodeIfNotEmpty(settings, forKey: .settings)
            }
        }
        let empty = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(Record(settings: .init())))
                                 as? [String: Any])
        #expect(empty["settings"] == nil, "a window that sets nothing stores nothing")
    }

    @Test("read leniently: an entry that can't be read is dropped and the rest kept; a record that isn't an object sets nothing")
    func readsLeniently() throws {
        let mixed: [String: Any] = ["example.size": 18, "example.name": ["not": "a value"], "example.wraps": true,
                                    "example.lines": NSNull()]
        let window = try decoded(mixed)
        #expect(window[S.size] == 18 && window[S.wraps] == true)
        #expect(window[S.name] == nil && window.keys == ["example.size", "example.wraps"])

        for unreadable in ["red", 42, [1, 2]] as [Any] {
            #expect(try decoded(unreadable).isEmpty)
        }

        // In a record: what can't be read costs the record its settings, never the record.
        struct Record: Decodable {
            var name: String
            var settings: GlassWindowOverrides
            enum CodingKeys: CodingKey { case name, settings }
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                name = try container.decode(String.self, forKey: .name)
                settings = GlassWindowOverrides.lenientlyDecoded(from: container, forKey: .settings)
            }
        }
        for settings in ["red", 7, NSNull()] as [Any] {
            let data = try JSONSerialization.data(withJSONObject: ["name": "Builds", "settings": settings])
            let record = try JSONDecoder().decode(Record.self, from: data)
            #expect(record.name == "Builds" && record.settings.isEmpty)
        }
        let absent = try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: ["name": "Builds"]))
        #expect(absent.settings.isEmpty)
    }

    @Test("keys a newer build added survive this one reading and saving the record")
    func unknownKeysSurvive() throws {
        let newer: [String: Any] = ["example.size": 18, "editor.minimap": true, "desktop.scale": 1.5]
        var window = try decoded(newer)
        window[S.size] = 20
        let saved = try json(window)
        #expect(saved["editor.minimap"] as? Bool == true && saved["desktop.scale"] as? Double == 1.5)
        #expect(saved["example.size"] as? Double == 20)
    }

    @Test("every value passes its setting's check, on the way in and on the way out")
    func valuesAreChecked() throws {
        var window = GlassWindowOverrides()
        window[S.size] = 400
        #expect(window[S.size] == 36, "clamped as it is set")
        window[S.size] = .nan
        #expect(window[S.size] == nil && window.isEmpty, "refused: the same as following")

        let hostile = try decoded(["example.size": 4000, "example.wraps": "yes", "example.lines": 12.5])
        #expect(hostile[S.size] == 36, "a record from elsewhere is checked as it is read")
        #expect(hostile[S.wraps] == nil, "a text is not a switch")
        #expect(hostile[S.lines] == 13, "a whole number, rounded")

        #expect(GlassLayerSettings.opacity.checked(3) == 1 && GlassLayerSettings.opacity.checked(-1) == 0)
        #expect(GlassLayerSettings.opacity.checked(.infinity) == nil)
    }

    @Test("never more than a window sets, nor longer texts")
    func bounded() throws {
        var many: [String: Any] = [:]
        for index in 0..<200 { many["example.k\(index)"] = index }
        #expect(try decoded(many).keys.count == GlassWindowOverrides.maximumCount)

        var window = GlassWindowOverrides()
        window[S.name] = String(repeating: "x", count: GlassWindowOverrides.maximumTextLength + 1)
        #expect(window[S.name] == nil)
        let long = try decoded([String(repeating: "k", count: 200): 1, "example.name": String(repeating: "x", count: 5000)])
        #expect(long.isEmpty)
    }

    @Test("merging: the other's entries win where both set one; restricting and removing by key")
    func merging() {
        var mine = GlassWindowOverrides()
        mine[S.size] = 18
        mine[S.name] = "Menlo"
        var theirs = GlassWindowOverrides()
        theirs[S.size] = 20
        theirs[S.wraps] = true
        let merged = mine.merging(theirs)
        #expect(merged[S.size] == 20 && merged[S.name] == "Menlo" && merged[S.wraps] == true)
        #expect(merged.restricted(to: [S.size.key]).keys == [S.size.key])
        #expect(merged.removing([S.size.key]).keys == [S.name.key, S.wraps.key])
    }

    // MARK: Appearance, per window

    @Test("Appearance, per window: the window's opacity, frost and material over the app's, field by field")
    func appearanceOverlay() {
        let app = GlassLayerState(opacity: 0.2, frost: 1, material: .regular)
        #expect(app.overlaid(by: GlassWindowOverrides()) == app, "a window that sets nothing draws the app's")

        var window = GlassWindowOverrides()
        window[GlassLayerSettings.opacity] = 0.9
        #expect(app.overlaid(by: window) == GlassLayerState(opacity: 0.9, frost: 1, material: .regular))
        window[GlassLayerSettings.frost] = 0
        window[GlassLayerSettings.material] = .thick
        #expect(app.overlaid(by: window) == GlassLayerState(opacity: 0.9, frost: 0, material: .thick))
        #expect(GlassLayerSettings.keys == ["appearance.opacity", "appearance.frost", "appearance.material"])
    }

    @Test("a window's glass resolves its own Appearance first, then Reduce Transparency and a self-painting surface")
    func windowResolution() {
        let app = GlassLayerState(opacity: 0, frost: 1, material: .regular)
        var window = GlassWindowOverrides()
        window[GlassLayerSettings.opacity] = 0.7
        window[GlassLayerSettings.material] = .thin

        #expect(GlassLayerResolution.resolve(app, window: window, reduceTransparency: false)
                == GlassLayerState(opacity: 0.7, frost: 1, material: .thin))
        #expect(GlassLayerResolution.resolve(app, window: window, reduceTransparency: true)
                == GlassLayerState(opacity: 1, frost: 1, material: .thin), "an opaque window is an accessibility promise")
        #expect(GlassLayerResolution.resolve(app, window: window, reduceTransparency: false, paintsTheme: false)
                == GlassLayerState(opacity: 0, frost: 1, material: .thin), "a surface that paints its own theme")
    }

    // MARK: This Window's rows

    @Test("This Window's control shows the window's value, else the setting's, and writes the window's own")
    func rowBinding() {
        var stored = GlassWindowOverrides()
        let overrides = Binding(get: { stored }, set: { stored = $0 })
        let size = GlassWindowSettingBinding.value(S.size, in: overrides, over: 13)
        #expect(size.wrappedValue == 13 && stored.isEmpty)
        size.wrappedValue = 13
        #expect(stored[S.size] == 13, "chosen for this window, even at the setting's own value")
        size.wrappedValue = 22
        #expect(stored[S.size] == 22 && size.wrappedValue == 22)
    }

    @Test("each row says where its value comes from")
    func rowCaption() {
        #expect(GlassWindowSettingSource.caption(isSet: false, inheritsFrom: "All Terminals") == "Same as All Terminals")
        #expect(GlassWindowSettingSource.caption(isSet: true, inheritsFrom: "Appearance") == "This window only")
    }
}

#if os(macOS)
import AppKit

/// The window's glass is drawn from its own overrides: `GlassLayeredWindow` and a panel in it read
/// them from the environment the window's root sets.
@Suite("A window's glass draws its own Appearance (W22)", .serialized)
@MainActor
struct GlassLayeredWindowOverridesTests {
    private func store() throws -> (GlassLayerStore, UserDefaults, String) {
        let suite = "GlassWindowOverridesTests.\(UUID())"
        let defaults = try #require(UserDefaults.forTest(suiteName: suite))
        let store = GlassLayerStore(defaults: defaults, legacyDefaults: [])
        // The app's glass: clear, no theme paint, no frost.
        store.state = GlassLayerState(opacity: 0, frost: 0, material: .regular)
        return (store, defaults, suite)
    }

    /// The pixel at the centre of `view`, drawn 80 × 80: red, green, blue and alpha, premultiplied.
    private func centre(_ view: some View) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: 80, height: 80))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -40, y: -40, width: image.width, height: image.height))
        return pixel
    }

    private func centreAlpha(_ view: some View) throws -> Double {
        Double(try centre(view)[3]) / 255
    }

    private var opaqueWindow: GlassWindowOverrides {
        var window = GlassWindowOverrides()
        window[GlassLayerSettings.opacity] = 1
        return window
    }

    @Test("a presented panel paints the window's own opacity, not the app's clear glass")
    func panelPaintsTheWindowsOpacity() throws {
        let (layers, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let panel = GlassLayeredPanel(cornerRadius: 0, role: .presented) { Color.clear }.glassLayers(layers)
        #expect(try centreAlpha(panel) == 0, "the app's glass is clear")
        #expect(try centreAlpha(panel.glassWindowOverrides(opaqueWindow)) > 0.95, "this window's is opaque")
    }

    /// The window's theme paint, as an opaque panel draws it — compared by colour, because behind a
    /// clear window the renderer draws its stand-in for the AppKit window reader instead.
    @Test("a layered window paints the window's own opacity, not the app's clear glass")
    func windowPaintsItsOwnOpacity() throws {
        let (layers, defaults, suite) = try store()
        defer { defaults.removePersistentDomain(forName: suite) }
        let themePaint = try centre(GlassLayeredPanel(cornerRadius: 0, role: .presented) { Color.clear }
            .glassLayers(layers).glassWindowOverrides(opaqueWindow))
        let plain = try centre(GlassLayeredWindow { Color.clear }.glassLayers(layers))
        let own = try centre(GlassLayeredWindow { Color.clear }.glassLayers(layers).glassWindowOverrides(opaqueWindow))
        #expect(own == themePaint, "this window's glass is painted opaque")
        #expect(plain != themePaint, "and the app's is not")
    }
}
#endif
