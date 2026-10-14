//
//  DesktopDisplayConnection.swift
//  Glass Power Tools — GlassDesktop
//
//  W38 (owner, 2026-10-11, on the Vision Pro, sharing a Mac with a Retina display beside a 1x one):
//  "can we have the Mac chill on the 2x retina resolution when screen sharing?"
//
//  **Why a second connection.** A Mac scales its whole framebuffer by one factor (`SetServerScaling`),
//  so a Retina display and a 1x one in the same picture cannot both arrive at 1x: 0.5 halves the 1x
//  display too, and 1 sends the Retina display at its own pixels — four times the bytes. Apple's
//  viewer does not try; over mixed densities it takes the native picture (remotex's notes, "Combined
//  Display over mixed densities"). So where the densities are mixed, a display's window that shows
//  one display gets a connection of its own: `SetDisplay` narrows that connection's framebuffer to
//  its display, and `SetServerScaling` asks for that display's 1x. The desktop's own connection then
//  fetches only the displays still shown from it — the desktop's window's — which share one density
//  and so are asked for at 1x too (`RFBStreamPlanner`).
//
//  **What it shares, and what it does not.** The same endpoint and the credential the desktop's
//  connection signed in with, held in memory for that attempt only (`DesktopSessionModel`): the
//  person signs in once, and nothing is stored anywhere new. Its own picture, link figures and input:
//  a window with its own connection draws that connection's frames and sends its pointer and keys
//  there, in that display's pixels (divided by the factor in force, as on every Mac connection). The
//  pointer's shape and where it is are the session's, whichever connection says so, so the pointer is
//  drawn in the window whose display it is on. The clipboard stays the desktop's connection's (D42a):
//  a second connection is opened with clipboard sharing off.
//
//  **When it ends.** With its window, when its window shows another display or all of them, when
//  the densities stop being mixed or Retina Displays is Native, and with the session. One that fails
//  before showing anything — a Mac that will not take a second session from the same viewer, say —
//  is not tried again for this connection: the window shows its display from the desktop's
//  connection, at its own pixels, as before W38, and Desktop Settings ▸ Connection says why.
//

import Foundation
import VNCKit
import Observation
import CoreGraphics
import GlassRDPTransport
import GlassVNCTransport

/// A display window's own connection to a Mac (W38): one display, at 1x.
@MainActor @Observable
public final class DesktopDisplayConnection: Identifiable {
    public let id = UUID()
    /// The Mac's display this connection sends.
    public let display: UInt32
    /// The window it is for (`DesktopViewport.id`).
    let viewportID: UUID
    @ObservationIgnored let transport: any GlassDesktopTransport
    public private(set) var state = GlassRDPState.connecting
    public private(set) var frame: GlassRDPFrame?
    public private(set) var linkStatistics: GlassDesktopLinkStatistics?
    /// The display's density as this connection's layout states it.
    public private(set) var density: Double?
    @ObservationIgnored weak var session: DesktopSessionModel?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private let disconnect: @MainActor (any GlassDesktopTransport) async -> Void
    @ObservationIgnored private(set) var isClosed = false

    init(display: UInt32, viewportID: UUID, transport: any GlassDesktopTransport,
         disconnect: @escaping @MainActor (any GlassDesktopTransport) async -> Void) {
        self.display = display
        self.viewportID = viewportID
        self.transport = transport
        self.disconnect = disconnect
    }

    /// Its window draws its picture and sends its input here: connected, with a picture.
    public var isShowing: Bool { !isClosed && state == .connected && frame != nil }

    /// Opens the connection at the session's quality and Retina setting, fetching its display
    /// while its window is on screen.
    func start(_ configuration: GlassVNCConfiguration, quality: GlassDesktopStreamQuality,
               retina: GlassDesktopRetinaDisplays, onScreen: Bool,
               connect: @escaping @MainActor (any GlassDesktopTransport, DesktopTransportConfiguration) async throws -> Void) {
        let target = transport
        observe()
        VNCDiagnostics.record(category: "display-connection", "event=open display=\(display) quality=\(quality.rawValue) retina=\(retina.rawValue) onScreen=\(onScreen)")
        Task { [weak self] in
            await target.setStreamQuality(quality)
            await target.setRetinaDisplays(retina)
            await target.setVisibleRegions(onScreen ? nil : [])
            do {
                try await connect(target, .vnc(configuration))
            } catch {
                self?.receive(.state(.failed(error.localizedDescription)))
            }
        }
    }

    func setOnScreen(_ onScreen: Bool) {
        let target = transport
        Task { await target.setVisibleRegions(onScreen ? nil : []) }
    }

    func setQuality(_ value: GlassDesktopStreamQuality) {
        let target = transport
        Task { await target.setStreamQuality(value) }
    }

    func setRetinaDisplays(_ value: GlassDesktopRetinaDisplays) {
        let target = transport
        Task { await target.setRetinaDisplays(value) }
    }

    /// Ends it: its window closed, or no longer wants it.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        VNCDiagnostics.record(category: "display-connection", "event=close display=\(display)")
        eventTask?.cancel(); frameTask?.cancel()
        eventTask = nil; frameTask = nil
        frame = nil
        let target = transport, disconnect = disconnect
        Task { await disconnect(target) }
    }

    private func observe() {
        let target = transport
        eventTask = Task { [weak self] in
            for await event in target.events {
                guard let self, !Task.isCancelled, !isClosed else { break }
                receive(event)
            }
        }
        frameTask = Task { [weak self] in
            for await value in target.frames {
                guard let self, !Task.isCancelled, !isClosed else { break }
                receive(value)
            }
        }
    }

    // The reducers: shared by the real streams and deterministic tests.

    func receive(_ event: GlassRDPEvent) {
        guard !isClosed else { return }
        switch event {
        case .state(let value):
            state = value
            VNCDiagnostics.record(category: "display-connection", "event=state display=\(display) state=\(value)")
            session?.displayConnectionChanged(self)
        case .cursor(let value):
            session?.receive(value, from: self)
        case .screens(let value):
            density = value.first(where: { $0.id == display })?.density ?? value.first?.density
        case .linkStatistics(let value):
            if state == .connected { linkStatistics = value }
        case .clipboard, .clipboardReady, .audio, .certificate, .displayCapabilities, .highPerformance:
            // The clipboard is the desktop's connection's (D42a), and a Mac sends no sound or
            // certificate; nor does a display connection resize its display.
            break
        }
    }

    func receive(_ value: GlassRDPFrame) {
        guard !isClosed, state == .connecting || state == .connected else { return }
        let first = frame == nil
        frame = value
        if first { session?.displayConnectionChanged(self) }
    }
}
