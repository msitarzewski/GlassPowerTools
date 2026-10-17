import GlassLayers
import SwiftUI
import GlassConnectionUI
import GlasSecretStore
import GlassWidgetData

public enum GlassShellSettingsPage: String, CaseIterable, Hashable, Sendable {
    case general, appearance, privacy, about

    public var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    /// The toolbar icon on a Mac, where Settings is a row of icon tabs.
    public var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

/// A page in the one settings surface: the shell's own, or one a capability contributes.
public enum GlassShellSettingsSelection: Hashable, Sendable {
    case shell(GlassShellSettingsPage)
    case capability(String)

    /// The shell's pages first, then every registered capability's, in kind order.
    public static func options(shell: [GlassShellSettingsPage] = GlassShellSettingsPage.allCases,
                               capabilityPages: [GlassCapabilitySettingsPage]) -> [GlassShellSettingsSelection] {
        shell.map(GlassShellSettingsSelection.shell) + capabilityPages.map { .capability($0.id) }
    }
}

/// The one settings surface. Pages are the glassDT set plus whatever the registered
/// capabilities contribute; nothing adds a second surface.
public struct GlassShellSettingsView: View {
    private let model: GlassShellModel
    @State private var page = GlassShellSettingsSelection.shell(.general)
    #if os(macOS) || os(visionOS)
    /// HIG: a settings window reopens on the pane last viewed.
    @AppStorage("com.glasspowertools.settings.pane", store: GlassUITestRun.settingsDefaults) private var storedPane = "general"
    #endif
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init(model: GlassShellModel) { self.model = model }

    private var capabilityPages: [GlassCapabilitySettingsPage] { model.registry.settingsPages }

    private func title(_ selection: GlassShellSettingsSelection) -> String {
        switch selection {
        case .shell(let page): page.title
        case .capability(let id): capabilityPages.first { $0.id == id }?.title ?? id
        }
    }

    private func systemImage(_ selection: GlassShellSettingsSelection) -> String {
        switch selection {
        case .shell(let page): page.systemImage
        case .capability(let id): capabilityPages.first { $0.id == id }?.systemImage ?? "puzzlepiece"
        }
    }

    private var options: [GlassShellSettingsSelection] {
        GlassShellSettingsSelection.options(capabilityPages: capabilityPages)
    }

    public var body: some View {
        #if os(macOS) || os(visionOS)
        tabs
        #else
        sections
        #endif
    }

    #if os(macOS) || os(visionOS)
    /// **Icon tabs: the Mac's toolbar row, the headset's leading ornament** — one `TabView`, drawn
    /// natively by each (2026-09-25, the user pointing at AudioPaper's, then: *"These become
    /// ornaments in visionOS naturally right?"*). On the Mac it was a segmented picker the width of
    /// eight titles, which made the window ~900 pt wide and left every grouped form floating in
    /// wide margins. On visionOS it was a column of buttons inside the window, built on 2026-09-11
    /// when Settings was a *sheet* and a `TabView`'s ornament vanished from the accessibility tree;
    /// Settings is its own window there now, where an ornament is the ordinary case.
    private var tabs: some View {
        TabView(selection: Binding(
            get: { options.first { key($0) == storedPane } ?? .shell(.general) },
            set: { storedPane = key($0) })) {
            ForEach(options, id: \.self) { selection in
                Tab(title(selection), systemImage: systemImage(selection), value: selection) {
                    #if os(visionOS)
                    // The root of the window must be the `TabView` for the ornament; each pane
                    // keeps its own stack for whatever it pushes.
                    NavigationStack {
                        pageContent(selection).navigationTitle(title(selection))
                    }
                    #else
                    if case .capability = selection {
                        // A capability's page can be long (Terminal's is): a set height, scrolling.
                        pageContent(selection).frame(height: 540)
                    } else {
                        // HIG, and AudioPaper's: the window fits the pane rather than scrolling it.
                        pageContent(selection)
                            .scrollDisabled(true)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    #endif
                }
            }
        }
        .accessibilityIdentifier("settings-sections")
        #if os(macOS)
        // Wide enough for every tab. A fixed 640 held eight; with Databases and Desktops the last
        // pages fell into the toolbar's overflow and Editor could not be reached (2026-09-30).
        // Toolbar tabs do not scroll, so the window follows the count.
        .frame(width: max(640, CGFloat(options.count) * 84))
        #endif
    }

    private func key(_ selection: GlassShellSettingsSelection) -> String {
        switch selection {
        case .shell(let page): page.rawValue
        case .capability(let id): id
        }
    }
    #endif

    private var sections: some View {
        GlassSettingsSections(selection: $page,
                              options: options,
                              title: title, pickerIdentifier: "settings-sections") { selection in
            pageContent(selection)
            #if os(iOS)
            // A compact iPhone pushes each page onto the sheet's stack, and the presenter's Done
            // button stays behind on the root. A modal must be dismissable from wherever the user
            // is, so every pushed page carries its own Done beside the back button.
            .toolbar {
                if horizontalSizeClass == .compact {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.accessibilityIdentifier("settings-done")
                    }
                }
            }
            #endif
        }
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private func pageContent(_ selection: GlassShellSettingsSelection) -> some View {
            // **A contributed page owns its own container.** The shell's own pages are
            // `Section`s and need a `Form` around them; a capability's page is already one —
            // and a `Form` inside a `Form` collapses on iOS into a single clipped row, which is
            // what Settings ▸ Terminal was on a phone: the word "Theme", cut in half, and
            // nothing else (photographed 2026-09-19). On a Mac the nesting merely drew a box
            // inside a box, so it survived there unnoticed.
            switch selection {
            case .shell(.about):
                // Not a form: an identity card, centred (AudioPaper's, which the user asked for).
                GlassShellAboutView()
            case .shell(let page):
                Form { shellPage(page) }
                    .formStyle(.grouped)
            case .capability(let id):
                if let page = capabilityPages.first(where: { $0.id == id }) {
                    page.makeView().accessibilityIdentifier("settings-page-\(id)")
                } else {
                    ContentUnavailableView("Settings Unavailable", systemImage: "gearshape",
                                           description: Text("This page belongs to a capability that is not loaded."))
                }
            }
    }

    /// The shell's own four. Each is a set of `Section`s, so the caller supplies the `Form`.
    @ViewBuilder
    private func shellPage(_ page: GlassShellSettingsPage) -> some View {
        switch page {
        case .general: general
        case .appearance:
            GlassLayerControls()
            #if os(macOS)
            showAllWindowsSection
            #endif
        case .privacy: privacy
        case .about: EmptyView()   // `GlassShellAboutView`, outside a form
        }
    }

    @AppStorage(GlassAvailabilityMonitor.settingKey, store: GlassUITestRun.settingsDefaults) private var showsAvailability = false
    #if os(visionOS)
    @AppStorage(GlassConnectionsIdleShrink.settingKey, store: GlassUITestRun.settingsDefaults) private var idleShrinkSeconds = GlassConnectionsIdleShrink.standard.rawValue
    #endif

    #if os(macOS)
    @AppStorage(GlassShowAllWindows.blursPreviewsKey, store: GlassUITestRun.settingsDefaults)
    private var blursShowAllWindowsPreviews = false

    /// Show All Windows' look, beside every window's own: it applies to every window in that view (the
    /// owner, 2026-10-13: "We should move it to appearance since it applies to all of the windows in that
    /// mode"). It was on the terminal's Connections page, where he did not find it.
    private var showAllWindowsSection: some View {
        Section(GlassShowAllWindows.title) {
            Toggle("Blur previews", isOn: $blursShowAllWindowsPreviews)
                .accessibilityIdentifier("settings-show-all-windows-blur")
            Text("Softens what each window shows in Show All Windows (⇧⌘\\), so a screenshot of it can be shared. Names stay sharp. This Mac only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    #endif

    /// This device's name as typed, before it is kept (on Return, or on leaving the page).
    @State private var deviceNameDraft = ""

    private var general: some View {
        Group {
        Section {
            TextField(GlassDeviceName.system, text: $deviceNameDraft)
                .onAppear { deviceNameDraft = model.customDeviceName ?? "" }
                .onSubmit { model.setDeviceName(deviceNameDraft) }
                .onDisappear { model.setDeviceName(deviceNameDraft) }
                .accessibilityLabel("This device's name")
                .accessibilityIdentifier("settings-device-name")
        } header: {
            Text("This Device")
        } footer: {
            Text("What Your Library calls this device when it counts connections on all your devices. Left empty, it is what the system calls it.")
        }
        Section {
            Toggle("Show service availability", isOn: $showsAvailability)
                .accessibilityIdentifier("settings-show-availability")
        } header: {
            Text("Library")
        } footer: {
            Text("A dot beside each service: green when it answers, orange when it answers slowly, red when it does not. This device opens a connection to each service's port about once a minute while the library is on screen, and closes it at once. It never signs in.")
        }
        #if os(visionOS)
        // W29: the Connections window shrinking into its orb.
        Section {
            Picker("Shrink Connections when idle", selection: Binding(
                get: { GlassConnectionsIdleShrink(storedSeconds: idleShrinkSeconds) },
                set: { idleShrinkSeconds = $0.rawValue })) {
                ForEach(GlassConnectionsIdleShrink.allCases) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("settings-connections-idle-shrink")
        } footer: {
            Text("While other windows are open, Connections becomes a small orb after this long without a tap, scroll or typing in it. Look at the orb to see its name; pinch it to bring the window back as it was.")
        }
        #endif
        Section("Host Library") {
            LabeledContent("Storage", value: model.hasSharedContainer ? "App group container" : "This app's container")
            Text(model.hostLibraryStatus).font(.footnote).foregroundStyle(.secondary)
            LabeledContent("Hosts", value: model.hosts.count, format: .number)
            // Counted against the catalog's own hosts: this device is not one of its records
            // and would otherwise make the two numbers differ on every launch.
            if model.records.count != model.catalogHosts.count {
                // Diagnostics only: the family apps each published their own record per machine.
                LabeledContent("Catalog records", value: model.records.count, format: .number)
                Text("Records that describe the same machine are shown as one host. They are combined here, not rewritten in the shared library.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("Library file", value: model.catalogFileURL.lastPathComponent)
            LabeledContent("Appearance migrated from", value: model.layers.migrationSource == .none ? "Defaults" : model.layers.migrationSource.rawValue)
            if let problem = model.preferencesProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
            // The device's own host is kept out of the shared file on purpose (D8), so its state
            // is reported separately — including when it could not be created at all.
            if let problem = model.localHostProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
                    .accessibilityIdentifier("settings-local-host-problem")
            } else {
                LabeledContent("This device", value: "Kept in this app only, never shared")
            }
        }
        }
    }

    /// Settings ▸ Privacy ▸ Show Machines in Search (D72): off unless switched on.
    @AppStorage(GlassSpotlight.settingKey, store: GlassUITestRun.settingsDefaults) private var showsMachinesInSearch = false

    private var privacy: some View {
        Group {
            Section("Credentials") {
                LabeledContent("Store", value: "GlasSecretStore in the Keychain")
                LabeledContent("Access group", value: model.secretConfiguration.accessGroup ?? "Not shared (no access group)")
                LabeledContent("Default mobility", value: model.secretConfiguration.mobilityPolicy == .deviceOnly ? "This device only" : "iCloud Keychain")
                    .accessibilityIdentifier("settings-credential-mobility")
                Text("Each service keeps its own credential and trust. Nothing here reads a secret; capabilities ask for what they need when connecting.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            // D20: say what travels and what does not.
            //
            // With sync on by default (D21), a user is entitled to know which of their secrets
            // reaches their other devices before they find out by a connection failing on one.
            // The Secure Enclave line is the one that matters: a key protected by this device's
            // biometrics is bound to this device's hardware and CANNOT sync — `validateMobility`
            // refuses it outright — so a service set to require authentication will ask for its
            // password again elsewhere. That is correct behaviour and indefensible as a surprise.
            Section("On your other devices") {
                LabeledContent("Host library", value: model.catalogSyncStatusDescription)
                    .accessibilityIdentifier("settings-catalog-sync-status")
                Text("Passwords, SSH key passphrases and private keys travel with you through "
                     + "iCloud Keychain, encrypted so that only your devices can read them.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("A service set to require authentication does not. Its password is protected "
                     + "by this device's biometrics and cannot leave it, so you will be asked for "
                     + "that one again on another device.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-device-bound-note")
            }
            // D72: the system's search knows your machines only if you say so.
            Section {
                Toggle("Show Machines in Search", isOn: $showsMachinesInSearch)
                    .accessibilityIdentifier("settings-search-machines")
            } footer: {
                Text("Your machines' and workgroups' names in Spotlight and Siri on this device, to open them from there. Names only; addresses and credentials are never indexed.")
            }
        }
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

/// App identity, links and licence — the family's About layout (AudioPaper's, 2026-09-25: *"get our
/// about section all schnappy like this one"*). Links only to pages that exist: the repository and
/// help pages are added when they do.
struct GlassShellAboutView: View {
    private static let sponsor = URL(string: "https://github.com/sponsors/msitarzewski")!
    @State private var showsAcknowledgements = false

    var body: some View {
        VStack(spacing: 10) {
            #if os(macOS)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            #endif
            Text("Glass Power Tools").font(.title2.weight(.semibold))
            Text("Version \(GlassShellSettingsView.versionString)")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("settings-about-version")
            Text("Terminals, databases, remote desktops and an editor for every machine you own — on Mac, iPad, iPhone and Vision Pro.")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                // A couple of balanced lines rather than one running the full width.
                .frame(maxWidth: 380)
            HStack(spacing: 18) {
                Link(destination: Self.sponsor) {
                    Label("Sponsor", systemImage: "heart.fill")
                }
                // Drawn like the link beside it; `.link` exists only on macOS.
                Button("Acknowledgements") { showsAcknowledgements = true }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("settings-about-acknowledgements")
            }
            .font(.callout)
            .padding(.top, 2)
            #if os(macOS) && canImport(Sparkle)
            GlassShellUpdateSettings()
                .padding(.top, 4)
            #endif
            Text("MIT · © 2026 Michael Sitarzewski")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal)
        .sheet(isPresented: $showsAcknowledgements) { GlassShellAcknowledgementsView() }
    }
}
