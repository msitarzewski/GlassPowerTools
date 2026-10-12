//
//  DesktopKeyboardAccessory.swift
//  Glass Power Tools — GlassDesktop
//
//  The bar above the software keyboard on an iPhone and an iPad, as a terminal's is: hide the
//  keyboard, the window's tools (the keyboard covers its status bar), the arrow pad and the Keys menu
//  (`DesktopAccessoryKeys`). visionOS has no accessory view; the desktop's toolbar carries the keys
//  and the pad there.
//

#if os(iOS)
import SwiftUI
import UIKit

@MainActor
final class DesktopKeyboardAccessory: UIInputView {
    private let content: UIView & UIContentView
    private weak var session: DesktopSessionModel?
    private let dismiss: @MainActor () -> Void

    init(session: DesktopSessionModel, tools: AnyView?, dismiss: @escaping @MainActor () -> Void) {
        self.session = session
        self.dismiss = dismiss
        content = UIHostingConfiguration { DesktopKeyboardBar(session: session, tools: tools, dismiss: dismiss) }
            .margins(.all, 0).makeContentView()
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.height), inputViewStyle: .keyboard)
        allowsSelfSizing = false
        autoresizingMask = [.flexibleWidth]
        content.backgroundColor = .clear
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        accessibilityIdentifier = "session.keyboard-accessory"
    }

    required init?(coder: NSCoder) { nil }

    static let height: CGFloat = 52

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    /// The window's tools change with its state: their menu is built again from the view's latest.
    func update(tools: AnyView?) {
        guard let session else { return }
        content.configuration = UIHostingConfiguration { DesktopKeyboardBar(session: session, tools: tools, dismiss: dismiss) }
            .margins(.all, 0)
    }
}

/// What the bar shows: hide the keyboard; then the tools, the arrow pad and the Keys menu.
struct DesktopKeyboardBar: View {
    let session: DesktopSessionModel
    let tools: AnyView?
    let dismiss: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("Hide Keyboard", systemImage: "keyboard.chevron.compact.down") { dismiss() }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("session.keyboard-dismiss")
            Spacer()
            if let tools {
                Menu { tools } label: { Label("Tools", systemImage: "wrench.and.screwdriver").labelStyle(.iconOnly) }
                    .accessibilityIdentifier("session.keyboard-tools")
            }
            DesktopArrowPad(session: session)
            DesktopKeysMenu(session: session)
                .labelStyle(.iconOnly)
        }
        .frame(maxHeight: .infinity)
        .font(.body)
    }
}
#endif
