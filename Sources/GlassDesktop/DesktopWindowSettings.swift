//
//  DesktopWindowSettings.swift
//  Glass Power Tools — GlassDesktop
//
//  W25 (owner, 2026-10-10): "the original idea was that anything in the system settings could be
//  overridden per window", for every kind of window. W22 built the mechanism (GlassLayers'
//  `GlassWindowOverrides`) and did terminal windows; this is the remote desktop's.
//
//  A desktop window keeps a `GlassWindowOverrides` over Settings ▸ Desktops (**All Desktops**): its
//  glass, its background removal, its Detail and, on iPad and iPhone, its pointer. Each resolves as
//  the window's value, else All Desktops' (`DesktopWindowProfile`), and the session draws and
//  drives with the result (`DesktopSessionModel.apply`).
//
//  **What a desktop window is.** `WindowGroup(id: "desktop-session", for: UUID.self)` opens one window
//  per saved desktop, keyed by its endpoint id, and Connect on an open desktop brings that window
//  forward; on iPhone the desktop is a cover, one at a time. Desktop windows are not restored at
//  launch (`.restorationBehavior(.disabled)`), so there is no window record to keep settings in.
//  A window's settings are kept by the desktop's endpoint id instead, on this device
//  (`DesktopWindowSettingsStore`), and come back whenever that desktop opens here — the same scope
//  as the All Desktops settings they override, which have always been this device's.
//
//  **The session's own presentation.** `PresentationSettings` was the desktop's per-session state,
//  written back into the device-wide defaults as it changed (so a window's sheet silently edited
//  every desktop). Now its mode, opacity, key colour, tolerance and edge softness are *derived*:
//  This Window edits the overlay, All Desktops edits the defaults, and `apply` writes the resolved
//  values into the presentation the renderer reads. Its zoom, pan and tilt stay the session's,
//  moved by gestures and Local Scale, as before.
//
//  Not per window, and why:
//  - Match Window Size, the display shown, Desktop Resolution, Local Scale (zoom and pan): the
//    session's live state, not settings — nothing in Settings holds them; each session starts
//    with Match Window Size on, the whole framebuffer, the service's size and 100%.
//  - Clipboard sharing and remote audio: already the desktop's own (the service's Advanced
//    settings), and a desktop has one window. Both are negotiated when the session connects (the
//    RDP clipboard and sound channels, VNC's cut text), so an edit applies on the next connect.
//  - Account, domain, password and its storage, NLA/TLS, the certificate pin, host and port,
//    protocol and the initial Desktop size: the connection's, edited with the service; they
//    apply on the next connect. Security does not differ by window.
//  - Important Session Notices: this device's notification permission.
//  - Remove Wallpaper: this window's for the session that chose its image, never saved — the
//    image reference lives only in that session (`DesktopWallpaperStore`), as before.
//

import Foundation
import SwiftUI
import GlassConnectionKit
import GlassLayers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension TransparencyMode: GlassWindowSettingValue {}
extension DesktopSourceScale: GlassWindowSettingValue {}
extension DesktopPointerMode: GlassWindowSettingValue {}

// MARK: - The settings a desktop window can keep

/// The desktop settings a window can override (W25), each under a stable key.
nonisolated enum DesktopWindowSettings {
    /// Fades the whole desktop (Settings ▸ Desktops ▸ Opacity). Not Appearance's opacity, which
    /// paints a theme colour behind content: this fades the content itself.
    static let opacity = GlassWindowSetting<Double>.unit("desktop.opacity", title: "Opacity")
    /// The glass behind the desktop (Settings ▸ Desktops ▸ Glass): a window's frost,
    /// so under the key every window's frost shares.
    static let frost = GlassLayerSettings.frost

    static let backgroundRemoval = GlassWindowSetting<TransparencyMode>.choice("desktop.backgroundRemoval",
                                                                              title: "Presentation")
    /// "#RRGGBB", as Color Code shows it.
    static let keyColor = GlassWindowSetting<String>("desktop.keyColor", title: "Background Color") {
        DesktopKeyColor.canonical($0)
    }
    static let tolerance = GlassWindowSetting<Double>("desktop.tolerance", title: "Tolerance") {
        $0.isFinite ? min(DesktopDefaults.toleranceRange.upperBound, max(0, $0)) : nil
    }
    static let edgeSoftness = GlassWindowSetting<Double>("desktop.edgeSoftness", title: "Edge Softness") {
        $0.isFinite ? min(DesktopDefaults.edgeSoftnessRange.upperBound, max(0, $0)) : nil
    }

    /// RDP only: remote pixels per point.
    static let detail = GlassWindowSetting<DesktopSourceScale>.choice("desktop.detail", title: "Detail")
    /// iPad and iPhone: how touch drives the pointer.
    static let pointer = GlassWindowSetting<DesktopPointerMode>.choice("desktop.pointer", title: "Pointer")

    static var keys: Set<String> {
        [opacity.key, frost.key, backgroundRemoval.key, keyColor.key, tolerance.key, edgeSoftness.key,
         detail.key, pointer.key]
    }

    /// Where Opacity and Glass apply: a see-through window, on the Mac and the headset.
    /// Settings ▸ Desktops offers them only there too.
    static var offersGlass: Bool {
        #if os(visionOS) || os(macOS)
        true
        #else
        false
        #endif
    }

    /// Where touch has a pointer choice: iPad and iPhone.
    static var offersTouchPointer: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    /// What a window keeps once its session ends: everything except Remove Wallpaper, whose image
    /// is this session's alone. A window that chose it follows All Desktops' presentation again.
    static func persistable(_ settings: GlassWindowOverrides) -> GlassWindowOverrides {
        settings[backgroundRemoval] == .removeWallpaper ? settings.removing([backgroundRemoval.key]) : settings
    }
}

extension GlassWindowOverrides {
    /// **Show Original** for one desktop window: the complete image, fully opaque, in this window
    /// only. glassDT put it in Desktop Settings' toolbar, opposite Done; it is on This Window now,
    /// under Presentation, so every window's Settings sheet has Done alone in its bar (W27).
    mutating func showDesktopOriginal() {
        self[DesktopWindowSettings.backgroundRemoval] = .original
        if DesktopWindowSettings.offersGlass { self[DesktopWindowSettings.opacity] = 1 }
    }
}

// MARK: - All Desktops

/// Keys of Settings ▸ Desktops on this device: glassDT's, kept as they were.
enum DesktopPreferenceKey {
    static let opacity = "display.glass.opacity"
    /// The frost amount, under glassDT's name for it.
    static let frost = "display.glass.material"
    static let backgroundRemoval = "display.glass.mode"
    static let keyRed = "display.glass.red"
    static let keyGreen = "display.glass.green"
    static let keyBlue = "display.glass.blue"
    static let tolerance = "display.glass.tolerance"
    static let edgeSoftness = "display.glass.feather"
    static let detail = "display.source.scale"
    /// Empty for Automatic.
    static let pointer = "display.pointer.mode"
}

/// Settings ▸ Desktops (**All Desktops**): what every desktop window on this device uses until it
/// sets its own. Stored on this device under `DesktopPreferenceKey`, and read through
/// `init(storedOpacity:…)`, which keeps whatever is stored in range.
struct DesktopDefaults: Equatable, Sendable {
    static let toleranceRange: ClosedRange<Double> = 0...0.25
    static let edgeSoftnessRange: ClosedRange<Double> = 0...0.12
    static let standard = DesktopDefaults()

    var opacity: Double = 1
    var frost: Double = 0.25
    /// Never Remove Wallpaper: it needs an image chosen in a session.
    var backgroundRemoval: TransparencyMode = .original
    var keyColor: SIMD3<Float> = [1, 0, 1]
    var tolerance: Double = 0.04
    var edgeSoftness: Double = 0.02
    var detail: DesktopSourceScale = .automatic
    /// Nil is Automatic: Trackpad on a compact screen, Direct Touch otherwise.
    var pointer: DesktopPointerMode?

    init() {}

    /// The stored values, kept in range: what another build or a hand edit left is never drawn
    /// out of range, and an unknown choice is the standard one.
    init(storedOpacity: Double, frost: Double, backgroundRemoval: String, red: Double, green: Double, blue: Double,
         tolerance: Double, edgeSoftness: Double, detail: String, pointer: String) {
        self.opacity = storedOpacity.isFinite ? min(1, max(0, storedOpacity)) : Self.standard.opacity
        self.frost = frost.isFinite ? min(1, max(0, frost)) : Self.standard.frost
        let mode = TransparencyMode(rawValue: backgroundRemoval) ?? .original
        self.backgroundRemoval = mode == .removeWallpaper ? .original : mode
        var presentation = PresentationSettings()
        presentation.keyColor = SIMD3(Float(red), Float(green), Float(blue))
        self.keyColor = presentation.keyColor
        self.tolerance = tolerance.isFinite ? min(Self.toleranceRange.upperBound, max(0, tolerance)) : Self.standard.tolerance
        self.edgeSoftness = edgeSoftness.isFinite
            ? min(Self.edgeSoftnessRange.upperBound, max(0, edgeSoftness)) : Self.standard.edgeSoftness
        self.detail = DesktopSourceScale(rawValue: detail) ?? .automatic
        self.pointer = DesktopPointerMode(rawValue: pointer)
    }

    /// The pointer every window follows on a screen this size.
    func pointer(compactScreen: Bool) -> DesktopPointerMode {
        pointer ?? .standard(forCompactScreen: compactScreen)
    }
}

// MARK: - What a desktop window uses

/// Everything one desktop window draws and drives with (W25): each of its own settings over All
/// Desktops'. Reduce Transparency wins over both, as it always has: Original, opaque and frosted.
struct DesktopWindowProfile: Equatable {
    let opacity: Double
    let frost: Double
    let backgroundRemoval: TransparencyMode
    let keyColor: SIMD3<Float>
    let tolerance: Float
    let edgeSoftness: Float
    let detail: DesktopSourceScale
    /// Nil where touch has no pointer choice (Mac, Vision Pro): the session's own is left alone.
    let pointer: DesktopPointerMode?

    /// - Parameters:
    ///   - glass: whether Opacity and Glass apply here (`offersGlass`); where they
    ///     don't, the desktop is opaque, as it always was.
    ///   - touch: whether touch has a pointer choice here (`offersTouchPointer`).
    init(window: GlassWindowOverrides, defaults: DesktopDefaults,
         glass: Bool = DesktopWindowSettings.offersGlass, touch: Bool = DesktopWindowSettings.offersTouchPointer,
         compactScreen: Bool = false, reduceTransparency: Bool) {
        let opacity = window.value(of: DesktopWindowSettings.opacity, over: defaults.opacity)
        let frost = window.value(of: DesktopWindowSettings.frost, over: defaults.frost)
        let mode = window.value(of: DesktopWindowSettings.backgroundRemoval, over: defaults.backgroundRemoval)
        if reduceTransparency {
            self.opacity = 1
            self.frost = 1
            self.backgroundRemoval = .original
        } else {
            self.opacity = glass ? opacity : 1
            self.frost = frost
            self.backgroundRemoval = mode
        }
        self.keyColor = window[DesktopWindowSettings.keyColor].flatMap(DesktopKeyColor.color) ?? defaults.keyColor
        self.tolerance = Float(window.value(of: DesktopWindowSettings.tolerance, over: defaults.tolerance))
        self.edgeSoftness = Float(window.value(of: DesktopWindowSettings.edgeSoftness, over: defaults.edgeSoftness))
        self.detail = window.value(of: DesktopWindowSettings.detail, over: defaults.detail)
        self.pointer = touch
            ? window.value(of: DesktopWindowSettings.pointer, over: defaults.pointer(compactScreen: compactScreen))
            : nil
    }

    /// Whether the window already shows what **Show Original** asks for: the complete image, opaque.
    var showsOriginal: Bool { backgroundRemoval == .original && opacity == 1 }
}

extension DesktopSessionModel {
    /// Draws and drives this session with its window's settings (W25). Only what a window can set:
    /// zoom, pan, tilt and the display shown stay the session's own, and nothing changes that is
    /// already so — a changed Detail asks the server for the window again.
    func apply(_ profile: DesktopWindowProfile) {
        var drawn = presentation
        drawn.mode = profile.backgroundRemoval
        drawn.opacity = profile.opacity
        drawn.keyColor = profile.keyColor
        drawn.threshold = profile.tolerance
        drawn.feather = profile.edgeSoftness
        if drawn != presentation { presentation = drawn }
        if sourceScale != profile.detail { sourceScale = profile.detail }
        if let pointer = profile.pointer, pointerMode != pointer { pointerMode = pointer }
    }
}

// MARK: - The key colour, as text

/// The colour Remove Background Color removes, as Color Code shows it: "#RRGGBB".
enum DesktopKeyColor {
    /// `text` as "#RRGGBB" in capitals, or nil when it isn't a "#" and six hexadecimal digits.
    static func canonical(_ text: String) -> String? {
        let digits = text.trimmingCharacters(in: .whitespaces)
        guard digits.count == 7, digits.first == "#",
              digits.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return digits.uppercased()
    }

    static func hex(_ color: SIMD3<Float>) -> String {
        func byte(_ value: Float) -> Int { value.isFinite ? Int((min(1, max(0, value)) * 255).rounded()) : 0 }
        return String(format: "#%02X%02X%02X", byte(color.x), byte(color.y), byte(color.z))
    }

    static func color(_ text: String) -> SIMD3<Float>? {
        guard let hex = canonical(text), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return SIMD3(Float((value >> 16) & 0xFF) / 255, Float((value >> 8) & 0xFF) / 255, Float(value & 0xFF) / 255)
    }

    /// A colour picker's binding over a key colour.
    @MainActor
    static func binding(_ color: Binding<SIMD3<Float>>) -> Binding<Color> {
        Binding(get: {
            let value = color.wrappedValue
            return Color(.sRGB, red: Double(value.x), green: Double(value.y), blue: Double(value.z), opacity: 1)
        }, set: { picked in
            #if os(macOS)
            guard let rgb = NSColor(picked).usingColorSpace(.sRGB) else { return }
            color.wrappedValue = [Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent)]
            #else
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(picked).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            color.wrappedValue = [Float(red), Float(green), Float(blue)]
            #endif
        })
    }

    @MainActor
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - Where a window's settings are kept

/// One desktop window's record on this device: its own settings, only when it sets any.
struct DesktopWindowRecord: Codable, Equatable {
    var windowSettings = GlassWindowOverrides()

    init(windowSettings: GlassWindowOverrides = GlassWindowOverrides()) {
        self.windowSettings = windowSettings
    }

    private enum CodingKeys: String, CodingKey { case windowSettings }

    /// Never throws: a record that isn't one is a window that sets nothing.
    init(from decoder: any Decoder) {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        windowSettings = GlassWindowOverrides.lenientlyDecoded(from: container, forKey: .windowSettings)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfNotEmpty(windowSettings, forKey: .windowSettings)
    }
}

/// Each desktop window's own settings on this device (W25), by the desktop's endpoint id — the
/// window's identity (`GlassDesktopScenes`). Kept as one record per window under `key`, read
/// leniently: an entry that can't be read costs only itself, keys a newer build wrote are kept,
/// and a window that sets nothing has no entry. Never in the synced catalog: like All Desktops,
/// a window's look belongs to the device it is on.
@MainActor
public final class DesktopWindowSettingsStore {
    static let key = "desktop.windows"
    /// More windows than anyone keeps settings for; what is past it was not written by this app.
    static let maximumCount = 1024

    private let defaults: UserDefaults?
    private var records: [EndpointID: DesktopWindowRecord]

    /// - Parameter defaults: where to keep them; nil keeps them in memory only (a preview, the
    ///   screenshot demo, a test that doesn't look).
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
        records = Self.read(defaults?.data(forKey: Self.key))
    }

    /// The window's own settings for this desktop; empty when it follows All Desktops.
    func settings(for id: EndpointID) -> GlassWindowOverrides {
        records[id]?.windowSettings ?? GlassWindowOverrides()
    }

    /// Keeps `settings` for this desktop's window — all of it except what lasts a session only.
    func save(_ settings: GlassWindowOverrides, for id: EndpointID) {
        let kept = DesktopWindowSettings.persistable(settings)
        guard records[id]?.windowSettings != kept else { return }
        if kept.isEmpty {
            records.removeValue(forKey: id)
        } else {
            guard records[id] != nil || records.count < Self.maximumCount else { return }
            records[id] = DesktopWindowRecord(windowSettings: kept)
        }
        write()
    }

    /// The desktop is gone: so is what its window kept.
    func remove(_ id: EndpointID) {
        guard records.removeValue(forKey: id) != nil else { return }
        write()
    }

    private func write() {
        guard let defaults else { return }
        if records.isEmpty {
            defaults.removeObject(forKey: Self.key)
            return
        }
        let byKey = Dictionary(uniqueKeysWithValues: records.map { ($0.key.rawValue.uuidString, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(byKey) else { return }
        defaults.set(data, forKey: Self.key)
    }

    static func read(_ data: Data?) -> [EndpointID: DesktopWindowRecord] {
        guard let data, let byKey = try? JSONDecoder().decode([String: DesktopWindowRecord].self, from: data) else {
            return [:]
        }
        var records: [EndpointID: DesktopWindowRecord] = [:]
        for (key, record) in byKey.sorted(by: { $0.key < $1.key }) {
            guard records.count < maximumCount, let id = UUID(uuidString: key), !record.windowSettings.isEmpty else {
                continue
            }
            records[EndpointID(rawValue: id)] = record
        }
        return records
    }
}
