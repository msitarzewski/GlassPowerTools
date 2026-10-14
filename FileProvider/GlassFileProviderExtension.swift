//
//  GlassFileProviderExtension.swift
//  Glass Power Tools — machines as locations in the Finder (D72 phase 5, a spike)
//
//  SPIKE, not a feature: `memory-bank/tasks/2026-10/2026-10-13_file-provider-spike.md`. Step 1 measures
//  whether a sandboxed File Provider extension links the app's SSH stack and signs with the Keychain
//  access group; it presents an empty, read-only root and registers no domain. Nothing here is shown
//  to anyone until the owner has seen the measurements.
//

import FileProvider
import GlassSSHTransport
import UniformTypeIdentifiers

final class GlassFileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    let domain: NSFileProviderDomain

    /// The SSH stack, linked: step 1 of the spike measures the extension with it inside.
    static let transport: Any.Type = SSHTransport.self

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {}

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, (any Error)?) -> Void) -> Progress {
        if identifier == .rootContainer {
            completionHandler(GlassFileProviderRoot(), nil)
        } else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
        }
        return Progress()
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, (any Error)?) -> Void) -> Progress {
        completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
        return Progress()
    }

    /// Read-only: nothing is created, changed or deleted on a machine from here.
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?,
                    options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void) -> Progress {
        completionHandler(nil, [], false, CocoaError(.featureUnsupported))
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields, contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, (any Error)?) -> Void) -> Progress {
        completionHandler(nil, [], false, CocoaError(.featureUnsupported))
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest,
                    completionHandler: @escaping ((any Error)?) -> Void) -> Progress {
        completionHandler(CocoaError(.featureUnsupported))
        return Progress()
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        GlassFileProviderEmptyEnumerator()
    }
}

final class GlassFileProviderRoot: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { "Machine" }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsReading, .allowsContentEnumerating] }
    var itemVersion: NSFileProviderItemVersion { NSFileProviderItemVersion(contentVersion: Data([1]), metadataVersion: Data([1])) }
}

final class GlassFileProviderEmptyEnumerator: NSObject, NSFileProviderEnumerator {
    func invalidate() {}
    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        observer.finishEnumerating(upTo: nil)
    }
}
