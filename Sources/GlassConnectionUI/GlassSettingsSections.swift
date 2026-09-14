import SwiftUI

/// The Glass session-settings section picker and content layout.
/// The presenting app owns navigation, dismissal, size and preference state.
///
/// The picker adapts to the platform: a segmented control on the Mac and a regular-width
/// iPad, a vertical tab list on a compact iPhone, and a leading column of vertical tabs on
/// visionOS. The control never shows a visible label; its accessibility label stays
/// "Settings Section".
public struct GlassSettingsSections<Selection: Hashable, Content: View>: View {
    @Binding private var selection: Selection
    private let options: [Selection]
    private let title: (Selection) -> String
    private let pickerIdentifier: String
    private let content: (Selection) -> Content
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(
        selection: Binding<Selection>,
        options: [Selection],
        title: @escaping (Selection) -> String,
        pickerIdentifier: String,
        @ViewBuilder content: @escaping (Selection) -> Content
    ) {
        _selection = selection
        self.options = options
        self.title = title
        self.pickerIdentifier = pickerIdentifier
        self.content = content
    }

    public var body: some View {
        #if os(visionOS)
        // A leading column of vertical tabs inside the surface. A TabView's ornament and a
        // hand-built `.ornament` both vanish from the accessibility hierarchy when the sections
        // sit in a sheet on visionOS (element trees captured 2026-09-11 show only the page
        // content), so the tabs live in the window itself, sidebar-style, where they are visible
        // and reachable.
        HStack(spacing: 0) {
            ScrollView {
                verticalTabs
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            }
            .frame(width: 220)
            Divider()
            sectionContent
        }
        #elseif os(iOS)
        if horizontalSizeClass == .compact {
            // iPhone: the Settings-app pattern — a list of pages, each pushing its own screen.
            // Showing the sections and the selected page stacked on one narrow screen left the
            // page's content stranded below the list (observed on device, 2026-09-11).
            pushList
        } else {
            segmentedLayout
        }
        #else
        segmentedLayout
        #endif
    }

    /// One row per section; the presenter owns the surrounding `NavigationStack`, so each row is
    /// a link that pushes the page with its own title and back button.
    private var pushList: some View {
        List {
            ForEach(options, id: \.self) { option in
                NavigationLink {
                    content(option)
                        .navigationTitle(title(option))
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                } label: {
                    Text(title(option))
                }
                .accessibilityIdentifier("\(pickerIdentifier).\(String(describing: option))")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings Section")
        .accessibilityIdentifier(pickerIdentifier)
    }

    private var segmentedLayout: some View {
        VStack(spacing: 0) {
            Picker("Settings Section", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityIdentifier(pickerIdentifier)

            Divider()

            sectionContent
        }
    }

    /// One button per section, stacked. The group carries the picker identifier and the
    /// "Settings Section" accessibility label so tests and assistive technology find the same
    /// control on every platform.
    private var verticalTabs: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .font(.body.weight(selected ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityIdentifier("\(pickerIdentifier).\(String(describing: option))")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings Section")
        .accessibilityIdentifier(pickerIdentifier)
    }

    private var sectionContent: some View {
        content(selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
