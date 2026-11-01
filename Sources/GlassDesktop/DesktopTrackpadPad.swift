//
//  DesktopTrackpadPad.swift
//  Glass Power Tools — GlassDesktop
//
//  The trackpad below an iPhone Duo's fold (D93, 2026-10-31, the owner: "the top screen a remote
//  desktop, then the bottom a keyboard and a toggleable trackpad"). The remote screen sits above
//  the fold and this fills the lower half while the keyboard is put away, as UTM's touchpad does:
//  one finger moves the pointer, a tap clicks, tap and drag drags, two fingers tap for a right
//  click or move to scroll, and a click is felt. It steers the same pointer as a finger on the
//  picture (`DesktopMTKView.padBegan`), so the cursor carries on from where it is.
//

#if os(iOS)
import SwiftUI
import UIKit

struct DesktopTrackpadPad: View {
    let session: DesktopSessionModel
    /// Beside the keyboard's shortcuts (`DesktopFoldKeysPanel`): its name alone, no margin.
    var compact = false

    var body: some View {
        let corner: CGFloat = compact ? 12 : 22
        DesktopTrackpadPadSurface(session: session)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                Text(compact ? "Trackpad" : "Tap to click · two fingers to scroll · two-finger tap for a right click")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(compact ? 6 : 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, compact ? 0 : 16)
            .padding(.bottom, compact ? 0 : 12)
            .disabled(!session.isConnected)
            .accessibilityElement()
            .accessibilityLabel("Trackpad")
            .accessibilityValue(pointerValue)
            .accessibilityHint("Moves the remote pointer. Tap to click.")
            .accessibilityIdentifier("desktop-fold-trackpad")
    }

    /// Where the remote pointer is, in the desktop's pixels: what VoiceOver says of the pad.
    private var pointerValue: String {
        guard let point = session.pointerPosition else { return "Pointer not placed yet" }
        return "Pointer at \(point.x), \(point.y)"
    }
}

private struct DesktopTrackpadPadSurface: UIViewRepresentable {
    let session: DesktopSessionModel

    func makeUIView(context: Context) -> PadView { PadView(session: session) }

    func updateUIView(_ view: PadView, context: Context) { view.session = session }

    final class PadView: UIView {
        weak var session: DesktopSessionModel?
        /// Only the first finger down points; a second turns it into a two-finger gesture.
        private weak var primary: UITouch?
        private var scrolled = CGPoint.zero
        private let haptics = UIImpactFeedbackGenerator(style: .light)

        init(session: DesktopSessionModel) {
            self.session = session
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            backgroundColor = .clear
            let rightClick = UITapGestureRecognizer(target: self, action: #selector(secondaryTap(_:)))
            rightClick.numberOfTouchesRequired = 2
            rightClick.cancelsTouchesInView = false
            addGestureRecognizer(rightClick)
            let scroll = UIPanGestureRecognizer(target: self, action: #selector(scroll(_:)))
            scroll.minimumNumberOfTouches = 2
            scroll.maximumNumberOfTouches = 2
            scroll.cancelsTouchesInView = false
            addGestureRecognizer(scroll)
        }

        required init?(coder: NSCoder) { nil }

        private var target: DesktopMTKView? { session?.padTarget }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            let down = event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? touches.count
            guard down <= 1, primary == nil else {
                // A second finger: a right click or a scroll, not pointing.
                if primary != nil { primary = nil; target?.padCancelled() }
                return
            }
            primary = touch
            haptics.prepare()
            feel(target?.padBegan(at: touch.location(in: self), time: touch.timestamp))
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let primary, touches.contains(primary) else { return }
            feel(target?.padMoved(to: primary.location(in: self), time: primary.timestamp))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let primary, touches.contains(primary) else { return }
            self.primary = nil
            feel(target?.padEnded(time: primary.timestamp))
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let primary, touches.contains(primary) else { return }
            self.primary = nil
            target?.padCancelled()
        }

        @objc private func secondaryTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            feel(target?.padSecondaryTap())
        }

        @objc private func scroll(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                scrolled = .zero
            case .changed:
                let current = gesture.translation(in: self)
                target?.padScroll(by: CGPoint(x: current.x - scrolled.x, y: current.y - scrolled.y))
                scrolled = current
            default:
                break
            }
        }

        private func feel(_ clicked: Bool?) {
            if clicked == true { haptics.impactOccurred() }
        }
    }
}
#endif
