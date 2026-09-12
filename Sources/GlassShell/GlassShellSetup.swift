import SwiftUI
import GlassConnectionKit
import GlassConnectionUI

/// What the one host sheet is doing. Add Host offers every service right away; Add a service
/// and Edit service open the same sheet on the service's tab; Edit Host edits only the machine.
public enum GlassShellSetupMode: Identifiable, Sendable {
    case addHost
    case editHost(GlassShellHost)
    case addService(GlassShellHost, HostServiceKind)
    case editService(GlassShellHost, HostServiceLink)

    /// Adding a machine is the one mode that must end with a service.
    public var isAddHost: Bool { if case .addHost = self { return true }; return false }

    public var id: String {
        switch self {
        case .addHost: "add-host"
        case .editHost(let host): "edit-host-\(host.id.rawValue.uuidString)"
        case .addService(let host, let kind): "add-service-\(host.id.rawValue.uuidString)-\(kind.rawValue)"
        case .editService(_, let service): "edit-service-\(service.endpointID.rawValue.uuidString)"
        }
    }

    var host: GlassShellHost? {
        switch self {
        case .addHost: nil
        case .editHost(let host), .addService(let host, _), .editService(let host, _): host
        }
    }
}

/// The host sheet's state and its save, kept out of the view so the order of operations —
/// host first, then each enabled service, all or nothing — is unit-testable with fake
/// capabilities. A service is created complete: its capability commits configuration and
/// credentials under the endpoint id before the shell records the link.
@MainActor @Observable
public final class GlassShellSetupModel {
    public enum HostField: String, Hashable, Sendable { case name, address }

    public let mode: GlassShellSetupMode
    private let model: GlassShellModel

    public var name: String
    public var address: String
    public var aliases: [String]
    public var tags: [String]
    /// The kind being added, or nil for "no service". Selecting a tab **is** the decision to add
    /// that service — there is no separate toggle, and a sheet adds at most one new service.
    public var selection: HostServiceKind?
    /// The tab whose fields are on screen. Nil selection still shows a tab, so the user can see
    /// what a kind would ask for before choosing it.
    public var selectedKind: HostServiceKind
    public var enabledKinds: Set<HostServiceKind> { selection.map { [$0] } ?? [] }
    /// Host-field problems, shown once a save was attempted.
    public private(set) var hostIssues: [GlassSetupIssue] = []
    public private(set) var attemptedSave = false
    public var error: String?
    public private(set) var isSaving = false
    private var drafts: [HostServiceKind: any GlassServiceDraft] = [:]

    public init(model: GlassShellModel, mode: GlassShellSetupMode) {
        self.model = model
        self.mode = mode
        let host = mode.host
        name = host?.displayName ?? ""
        address = host?.address ?? ""
        aliases = GlassTagList.normalized(host?.aliases ?? [])
        tags = GlassTagList.normalized(host?.tags ?? [])
        switch mode {
        case .addHost, .editHost:
            // The first tab that can actually be enabled; the user's order is Terminal, Database, Desktop.
            selectedKind = Self.tabOrder.first { model.registry.capability(for: $0) != nil } ?? Self.tabOrder[0]
            // Adding a machine adds a service: a machine with nothing on it is not worth a row.
            // Editing one does not, since its services are managed from the detail.
            selection = mode.isAddHost && model.registry.capability(for: selectedKind) != nil ? selectedKind : nil
        case .addService(_, let kind):
            selectedKind = kind
            selection = kind
        case .editService(_, let service):
            selectedKind = service.kind
            selection = service.kind
        }
    }

    // MARK: What the sheet shows

    public var title: String {
        switch mode {
        case .addHost: "Add Host"
        case .editHost: "Edit Host"
        case .addService(let host, let kind): "Add \(GlassServicePresentation.displayName(for: kind)) to \(host.displayName)"
        case .editService(let host, let service): "Edit \(GlassServicePresentation.displayName(for: service.kind)) on \(host.displayName)"
        }
    }

    public var confirmationTitle: String {
        switch mode {
        case .addHost: enabledKinds.isEmpty ? "Add Host" : "Add"
        case .editHost, .editService: "Save"
        case .addService: "Add"
        }
    }

    public var nameEditable: Bool {
        switch mode {
        case .addHost, .editHost: true
        case .addService, .editService: false
        }
    }

    /// This sheet is about the device itself (D8): no address is collected, and it cannot be
    /// deleted from here.
    public var isLocalHost: Bool { mode.host?.isLocal == true }

    /// The address is always the host's. It is editable when the host is being defined, and
    /// when an existing host has none yet — a service cannot be created without one. Never on
    /// the device itself, which has none and is never asked for one.
    public var addressEditable: Bool {
        guard !isLocalHost else { return false }
        switch mode {
        case .addHost, .editHost: return true
        case .addService(let host, _), .editService(let host, _): return host.address == nil
        }
    }

    public var showsServiceTabs: Bool {
        if case .editHost = mode { return false }
        return !offeredKinds.isEmpty
    }

    /// The host this sheet edits, when it is the machine itself being edited. Only that mode
    /// offers to delete it: adding, or editing one service, is not where a machine is removed.
    /// The device's own host is never deletable, so it never reaches the delete section either.
    public var editedHost: GlassShellHost? {
        if case .editHost(let host) = mode, !host.isLocal { return host }
        return nil
    }

    public var showsOrganizeSection: Bool {
        switch mode {
        case .addHost, .editHost: true
        case .addService, .editService: false
        }
    }

    /// The user's tab order: `[ Terminal | Database | Desktop ]`.
    public static let tabOrder: [HostServiceKind] = [.ssh, .database, .rdp]

    /// The tabs offered, in `tabOrder`; a kind whose capability is not in this build is shown
    /// disabled. In edit mode only the service's own kind is offered.
    public var offeredKinds: [HostServiceKind] {
        if case .editService(_, let service) = mode { return [service.kind] }
        return Self.setupKinds(for: mode.host, registry: model.registry)
    }

    /// Which kinds a host will take. Every kind on a machine you reach. On the device itself
    /// (D8) only the kinds a capability will actually create locally, plus the kinds no
    /// capability owns in this build — those stay visible and disabled here as they do
    /// everywhere else, rather than vanishing and implying the device cannot ever have them.
    public static func setupKinds(for host: GlassShellHost?, registry: GlassCapabilityRegistry) -> [HostServiceKind] {
        guard host?.isLocal == true else { return tabOrder }
        let local = Set(registry.localSetupKinds)
        return tabOrder.filter { local.contains($0) || registry.capability(for: $0) == nil }
    }

    public func isAvailable(_ kind: HostServiceKind) -> Bool {
        model.registry.capability(for: kind) != nil
    }

    public func isEnabled(_ kind: HostServiceKind) -> Bool { selection == kind }

    /// Whether the sheet offers a "no service" choice. Only while **editing** a machine: adding
    /// one adds a service (a machine with nothing on it is not worth a row), an Add-a-service
    /// sheet exists to add one, and an edit sheet is editing one.
    public var allowsNoService: Bool {
        if case .editHost = mode { return true }
        return false
    }

    /// Choosing a tab selects that service; a kind with no capability in this build cannot be
    /// chosen, and choosing nothing is only possible where `allowsNoService` says so.
    public func select(_ kind: HostServiceKind?) {
        guard let kind else {
            if allowsNoService { selection = nil }
            return
        }
        selectedKind = kind
        selection = isAvailable(kind) ? kind : nil
    }

    /// The capability's draft for a kind, created on first use: fresh for a new service,
    /// loaded from the service in edit mode. Nil when the kind has no capability, or the edited
    /// service has no configuration behind it.
    public func draft(for kind: HostServiceKind) -> (any GlassServiceDraft)? {
        if let existing = drafts[kind] { return existing }
        guard let capability = model.registry.capability(for: kind) else { return nil }
        let draft: (any GlassServiceDraft)?
        if case .editService(let host, let service) = mode, service.kind == kind,
           let owner = host.member(owning: service.endpointID) {
            draft = capability.setupDraft(for: service, host: owner)
        } else {
            draft = capability.makeSetupDraft()
        }
        drafts[kind] = draft
        return draft
    }

    /// Edit mode on a link whose capability holds nothing: the sheet says so instead of a form.
    public var editedServiceIsBroken: Bool {
        guard case .editService(_, let service) = mode else { return false }
        return isAvailable(service.kind) && draft(for: service.kind) == nil
    }

    // MARK: Validation

    public func hostIssue(_ field: HostField) -> String? {
        hostIssues.first { $0.field == field.rawValue }?.message
    }

    static func hostIssues(name: String, address: String, nameRequired: Bool, addressRequired: Bool) -> [GlassSetupIssue] {
        var issues: [GlassSetupIssue] = []
        if nameRequired, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(GlassSetupIssue(field: HostField.name.rawValue, message: "Enter a name for this host."))
        }
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if addressRequired, trimmedAddress.isEmpty {
            issues.append(GlassSetupIssue(field: HostField.address.rawValue, message: "Enter the machine's hostname or IP address."))
        } else if !trimmedAddress.isEmpty, (try? HostProfile.normalizedAddress(trimmedAddress)) == nil {
            issues.append(GlassSetupIssue(field: HostField.address.rawValue,
                                          message: "The address must be a hostname or an IP address, with no user, port or spaces."))
        }
        return issues
    }

    /// The address the enabled services will be committed with. On the device itself the host
    /// has none and never asks for one, so its services are committed against loopback (D8) —
    /// the one that needs no address at all, SQLite, ignores it and saves a file path instead.
    private var effectiveAddress: String {
        if isLocalHost { return GlassLocalHost.address }
        let typed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return mode.host?.address ?? ""
    }

    /// Host issues, then each enabled draft's, in kind order. Empty means Save may proceed.
    /// Also reveals the messages in the sheet and moves focus to the first problem.
    @discardableResult
    public func validateForSave() -> (host: [GlassSetupIssue], services: [HostServiceKind: [GlassSetupIssue]]) {
        attemptedSave = true
        // An address is required whenever a service is being created or the host is being
        // defined; editing only the machine may leave it blank.
        let addressRequired: Bool
        switch mode {
        case .addHost: addressRequired = true
        case .editHost: addressRequired = false
        case .addService, .editService: addressRequired = true
        }
        hostIssues = Self.hostIssues(name: name, address: address, nameRequired: nameEditable,
                                     addressRequired: addressRequired && addressEditable)
        var serviceIssues: [HostServiceKind: [GlassSetupIssue]] = [:]
        for kind in offeredKinds where enabledKinds.contains(kind) {
            guard let draft = draft(for: kind) else { continue }
            let issues = draft.validate(address: effectiveAddress)
            if !issues.isEmpty { serviceIssues[kind] = issues }
        }
        if hostIssues.isEmpty, let firstKind = offeredKinds.first(where: { serviceIssues[$0] != nil }),
           let draft = draft(for: firstKind) {
            selectedKind = firstKind
            draft.focusFirstIssue(serviceIssues[firstKind] ?? [])
        }
        return (hostIssues, serviceIssues)
    }

    // MARK: Save

    /// Saves the sheet. Returns the host's id on success; nil (with `error` set) when nothing was
    /// saved. From the user's point of view a save is all or nothing: when a later service fails,
    /// the services created by this save are removed again, their capabilities roll back, and
    /// a host created by this save is deleted.
    public func save() async -> HostID? {
        let issues = validateForSave()
        guard issues.host.isEmpty, issues.services.isEmpty else { return nil }
        isSaving = true
        defer { isSaving = false }
        error = nil
        do {
            switch mode {
            case .editHost(let host):
                try await model.updateHost(host.id, displayName: name, address: address,
                                           aliases: GlassTagList.normalized(aliases), tags: GlassTagList.normalized(tags))
                return host.id
            case .editService(let host, let service):
                guard let draft = draft(for: service.kind), let owner = host.member(owning: service.endpointID) else {
                    throw GlassShellError.serviceNotFound(service.endpointID)
                }
                if addressEditable { try await model.setHostAddress(address, for: host.id) }
                let record = model.record(owner.id) ?? owner
                try await draft.commit(endpointID: service.endpointID, host: record, address: effectiveAddress)
                return host.id
            case .addHost:
                let created = try await model.addHost(displayName: name, address: address,
                                                      aliases: GlassTagList.normalized(aliases), tags: GlassTagList.normalized(tags))
                do {
                    try await commitEnabledServices(on: created.id, record: created)
                } catch {
                    try? await model.deleteHost(created.id)
                    throw error
                }
                return created.id
            case .addService(let host, _):
                if addressEditable { try await model.setHostAddress(address, for: host.id) }
                let record = model.record(host.id) ?? host.canonical
                try await commitEnabledServices(on: host.id, record: record)
                return host.id
            }
        } catch {
            self.error = GlassShellError.message(for: error)
            return nil
        }
    }

    /// Commits every enabled draft in kind order: the capability first, then the link. On a
    /// failure everything this call created is undone before the error propagates.
    private func commitEnabledServices(on hostID: HostID, record: HostProfile) async throws {
        var created: [(HostServiceKind, EndpointID)] = []
        let address = effectiveAddress
        for kind in offeredKinds where enabledKinds.contains(kind) {
            guard let draft = draft(for: kind) else { continue }
            let endpointID = EndpointID()
            do {
                try await draft.commit(endpointID: endpointID, host: record, address: address)
                created.append((kind, endpointID))
                try await model.addService(kind: kind, displayName: draft.serviceDisplayName(hostName: record.displayName),
                                           endpointID: endpointID, to: hostID)
            } catch {
                for (kind, endpointID) in created.reversed() {
                    if model.services(for: hostID).contains(where: { $0.endpointID == endpointID }) {
                        try? await model.removeService(endpointID, from: hostID)   // asks the capability too
                    } else {
                        await self.draft(for: kind)?.rollback(endpointID: endpointID)
                    }
                }
                if !created.contains(where: { $0.1 == endpointID }) { await draft.rollback(endpointID: endpointID) }
                throw error
            }
        }
    }
}

/// The one host sheet: the machine on top, the services as tabs beneath, the organising fields
/// under a disclosure. Apple's sheet pattern throughout (project rule 15): title header,
/// grouped form, Cancel and the primary action in the bottom bar.
public struct GlassShellHostSetupSheet: View {
    @State private var setup: GlassShellSetupModel
    private let model: GlassShellModel
    private let onSaved: (HostID) -> Void
    @FocusState private var focusedHostField: GlassShellSetupModel.HostField?
    @State private var organizeExpanded = false
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    public init(model: GlassShellModel, mode: GlassShellSetupMode, onSaved: @escaping (HostID) -> Void = { _ in }) {
        self.model = model
        self.onSaved = onSaved
        _setup = State(initialValue: GlassShellSetupModel(model: model, mode: mode))
    }

    public var body: some View {
        NavigationStack {
            Form {
                machineSection
                if setup.showsServiceTabs { servicesSection }
                if setup.showsOrganizeSection { organizeSection }
                if let host = setup.editedHost { deleteSection(host) }
                if let error = setup.error {
                    Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("host-editor-error") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(setup.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("host-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(setup.confirmationTitle) { save() }
                        .disabled(setup.isSaving || setup.editedServiceIsBroken)
                        .accessibilityIdentifier("host-editor-save")
                        #if os(macOS)
                        .keyboardShortcut(.defaultAction)
                        #endif
                }
            }
            #if os(macOS)
            .frame(minWidth: 560, idealWidth: 620, maxWidth: 720, minHeight: 480, idealHeight: 640, maxHeight: 820)
            #elseif os(visionOS)
            .frame(minWidth: 620, idealWidth: 680, minHeight: 560)
            #endif
        }
        .onAppear {
            if setup.nameEditable { focusedHostField = .name } else if setup.addressEditable { focusedHostField = .address }
        }
    }

    // MARK: Machine

    private var machineSection: some View {
        Section("Machine") {
            // Each row's content is one control; the validation text is its own row. A label
            // over a stacked content recursed in AppKit's accessibility (W4, 2026-09-10).
            if setup.nameEditable {
                LabeledContent("Name") {
                    TextField("Name", text: $setup.name, prompt: Text("Name"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .focused($focusedHostField, equals: .name)
                        .accessibilityIdentifier("host-editor-name")
                }
                issueText(setup.hostIssue(.name), id: "host-editor-name-validation")
            } else {
                LabeledContent("Name", value: setup.name).accessibilityIdentifier("host-editor-name")
            }
            if setup.addressEditable {
                LabeledContent("Address") {
                    TextField("Address", text: $setup.address, prompt: Text("Hostname or IP"))
                        .labelsHidden()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .focused($focusedHostField, equals: .address)
                        .accessibilityIdentifier("host-editor-address")
                }
                issueText(setup.hostIssue(.address), id: "host-editor-address-validation")
                if case .addService(let host, _) = setup.mode, host.address == nil {
                    Text("\(host.displayName) has no address yet. It is saved on the host and shared by every service.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let host = setup.mode.host, host.addresses.count > 1 {
                    Text("The records that make up this host disagree: \(host.addresses.joined(separator: ", ")). Saving applies one address to all of them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if setup.isLocalHost {
                // The device has no address and is never asked for one (D8). Saying "This device"
                // is the honest label; "Not set" would read as something still to be filled in.
                LabeledContent("Address", value: "This device").accessibilityIdentifier("host-editor-address")
                Text("Services on \(GlassLocalHost.displayName) reach it at \(GlassLocalHost.address), or open a file you choose.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                LabeledContent("Address", value: setup.address).accessibilityIdentifier("host-editor-address")
            }
        }
    }

    // MARK: Services

    private var servicesSection: some View {
        Section {
            if setup.offeredKinds.count > 1 || setup.allowsNoService {
                // The tab **is** the choice: picking one adds that service, and a sheet adds at
                // most one. "None" exists only where a machine may be saved without a service.
                Picker("Service", selection: Binding(
                    get: { setup.selection },
                    set: { setup.select($0) }
                )) {
                    if setup.allowsNoService {
                        Text("None").tag(HostServiceKind?.none)
                    }
                    ForEach(setup.offeredKinds, id: \.self) { kind in
                        Text(GlassServicePresentation.displayName(for: kind))
                            .tag(HostServiceKind?.some(kind))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("setup-sections")
            }
            tabContent(setup.selectedKind)
        } header: {
            Text("Services")
        } footer: {
            if !setup.isAvailable(setup.selectedKind) {
                Text(Self.unavailableNote(for: setup.selectedKind))
            }
        }
    }

    /// Shown when no capability is registered for a kind, so the tab is disabled rather than
    /// offering a half-made service. Phrased for what the user can see, not for our build order:
    /// a released build that is missing a capability says so plainly instead of naming a stage.
    static func unavailableNote(for kind: HostServiceKind) -> String {
        let name = GlassServicePresentation.displayName(for: kind)
        return "\(name) services are not available in this build."
    }

    @ViewBuilder
    private func tabContent(_ kind: HostServiceKind) -> some View {
        let name = GlassServicePresentation.displayName(for: kind)
        if !setup.isAvailable(kind) {
            EmptyView()
        } else if setup.editedServiceIsBroken {
            Text("This \(name.lowercased()) has no saved configuration behind it. Remove the service and add it again.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("setup-broken-\(kind.rawValue)")
        } else {
            if setup.isEnabled(kind), let draft = setup.draft(for: kind) {
                draft.requiredFields()
                DisclosureGroup {
                    draft.advancedFields()
                } label: {
                    Text("Advanced").accessibilityIdentifier("setup-advanced-\(kind.rawValue)")
                }
                .disclosureGroupStyle(GlassFormDisclosureStyle())
            }
        }
    }

    // MARK: Delete

    /// Removing a machine is deliberate: it sits at the bottom of the sheet that edits it, behind
    /// a confirmation, rather than beside Connect in the detail's action bar. The library row's
    /// context menu is the other way to reach it.
    private func deleteSection(_ host: GlassShellHost) -> some View {
        Section {
            Button("Delete Host…", role: .destructive) { confirmingDelete = true }
                .accessibilityIdentifier("host-editor-delete")
        } footer: {
            Text(host.services.isEmpty
                 ? "Removes \(host.displayName) from the shared library. Credentials are not touched."
                 : "Removes \(host.displayName) and its \(host.services.count) service link\(host.services.count == 1 ? "" : "s") from the shared library. Credentials are not touched.")
        }
        .alert("Delete Host?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    do { try await model.deleteHost(host.id) } catch { model.errorMessage = GlassShellError.message(for: error) }
                    dismiss()
                }
            }
            .accessibilityIdentifier("host-delete-confirm")
            Button("Cancel", role: .cancel) { confirmingDelete = false }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: Organise

    private var organizeSection: some View {
        Section {
            DisclosureGroup(isExpanded: $organizeExpanded) {
                LabeledContent("Also known as") {
                    GlassTagField(tags: $setup.aliases, placeholder: "Add a name…",
                                  accessibilityIdentifier: "host-editor-aliases")
                }
                LabeledContent("Collections") {
                    GlassTagField(tags: $setup.tags, suggestions: model.tagVocabulary, placeholder: "Add a collection…",
                                  accessibilityIdentifier: "host-editor-tags")
                }
            } label: {
                Text("Also known as & Collections").accessibilityIdentifier("host-editor-organize")
            }
            .disclosureGroupStyle(GlassFormDisclosureStyle())
        }
        .onAppear { organizeExpanded = !setup.aliases.isEmpty || !setup.tags.isEmpty }
    }

    @ViewBuilder
    private func issueText(_ message: String?, id: String) -> some View {
        if let message {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .font(.caption).foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(id)
                .accessibilityLabel("Error: \(message)")
        }
    }

    private func save() {
        Task {
            if let id = await setup.save() {
                onSaved(id)
                dismiss()
            } else if let first = setup.hostIssues.first {
                focusedHostField = GlassShellSetupModel.HostField(rawValue: first.field)
            }
        }
    }
}

/// A disclosure row for grouped forms whose whole label is the control: a plain button with a
/// chevron, so it toggles from a click anywhere on the row, from the keyboard, and under UI
/// automation (the stock macOS disclosure triangle ignored synthesized clicks, 2026-09-11).
public struct GlassFormDisclosureStyle: DisclosureGroupStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.snappy) { configuration.isExpanded.toggle() }
        } label: {
            HStack {
                configuration.label
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(configuration.isExpanded ? .degrees(90) : .zero)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isExpanded ? [.isSelected] : [])
        .accessibilityValue(configuration.isExpanded ? "expanded" : "collapsed")
        if configuration.isExpanded {
            configuration.content
        }
    }
}
