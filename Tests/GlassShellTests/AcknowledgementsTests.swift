import Foundation
import Testing
@testable import GlassShell

/// The acknowledgements cover everything the app is built from. A dependency added, moved or
/// vendored without regenerating them fails here, with the command that fixes it.
@Suite("Acknowledgements cover every third-party component")
struct AcknowledgementsTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let regenerate = "run Tools/Licenses/generate-acknowledgements.py"

    private func json(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(path))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("the bundled list loads, and every component carries a licence text")
    func loadsWithTexts() throws {
        let components = try GlassAcknowledgements.load()
        #expect(components.count > 50)
        for component in components {
            #expect(!component.texts.isEmpty, "\(component.name) has no licence text")
            #expect(component.texts.allSatisfy { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                    "\(component.name) has an empty licence text")
            #expect(!component.license.isEmpty, "\(component.name) has no licence named")
        }
    }

    @Test("every resolved package is listed at its pinned revision")
    func everyPinAtItsRevision() throws {
        let pins = try #require(try json("Package.resolved")["pins"] as? [[String: Any]])
        let listed = Dictionary(try GlassAcknowledgements.load().compactMap { c in c.revision.map { ($0, c) } },
                                uniquingKeysWith: { first, _ in first })
        for pin in pins {
            let identity = pin["identity"] as? String ?? "?"
            let revision = try #require((pin["state"] as? [String: Any])?["revision"] as? String)
            #expect(listed[revision] != nil, "\(identity) @ \(revision.prefix(12)) is not acknowledged — \(Self.regenerate)")
        }
    }

    @Test("every vendored package has an entry")
    func everyVendoredPackage() throws {
        let manifest = try #require(try json("Tools/Licenses/components.json")["components"] as? [[String: Any]])
        let vendored = Set(manifest.compactMap { $0["vendored"] as? String })
        let packages = try FileManager.default.contentsOfDirectory(atPath: Self.root.appendingPathComponent("Packages").path)
            .filter { !$0.hasPrefix(".") }
        for package in packages {
            #expect(vendored.contains("Packages/\(package)"),
                    "Packages/\(package) has no entry in Tools/Licenses/components.json")
        }
    }

    @Test("Mermaid's package list is for the Mermaid that is bundled")
    func mermaidListMatchesBundle() throws {
        let bundled = try String(contentsOf: Self.root.appendingPathComponent("Sources/GlassEditor/Resources/Mermaid/VERSION"),
                                 encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let components = try GlassAcknowledgements.load()
        #expect(components.first { $0.id == "mermaid" }?.version == bundled, "\(Self.regenerate)")
        #expect(try json("Documentation/ThirdPartyLicenses/mermaid/bundled-packages.json")["mermaid"] as? String == bundled,
                "run Tools/Mermaid/update-mermaid.sh")
        #expect(components.filter { $0.group == "Inside Mermaid" }.count > 50)
    }

    /// The list's DOMPurify is the one inside the bundle (2026-10-12): npm resolved the newest in
    /// its range, 3.4.16, for a bundle carrying 3.4.12, and the acknowledgements said 3.4.16.
    @Test("Mermaid's list names DOMPurify at the version the bundle carries")
    func mermaidListMatchesBundledDOMPurify() throws {
        let bundle = try String(contentsOf: Self.root.appendingPathComponent("Sources/GlassEditor/Resources/Mermaid/mermaid.min.js"),
                                encoding: .utf8)
        let embedded = try #require(bundle.firstMatch(of: /DOMPurify (\d+\.\d+\.\d+)/)?.1).description
        let packages = try #require(json("Documentation/ThirdPartyLicenses/mermaid/bundled-packages.json")["packages"] as? [[String: Any]])
        let listed = packages.first { $0["name"] as? String == "dompurify" }?["version"] as? String
        #expect(listed == embedded, "run Tools/Mermaid/mermaid-licenses.py --pin-embedded, then generate-acknowledgements.py")
        #expect(try GlassAcknowledgements.load().first { $0.name.lowercased() == "dompurify" }?.version == embedded,
                "\(Self.regenerate)")
    }

    @Test("groups read in a fixed order, with nothing left out")
    func grouping() throws {
        let components = try GlassAcknowledgements.load()
        let groups = GlassAcknowledgements.grouped(components)
        #expect(groups.map(\.group).allSatisfy(GlassAcknowledgements.groupOrder.contains))
        #expect(groups.reduce(0) { $0 + $1.components.count } == components.count)
    }
}

/// The package manager's pins and Xcode's are one list. They drifted once without anything
/// noticing: Xcode resolved swift-crypto 3 and BigInt 5 while the package pinned 4 and 6, so the
/// app shipped different cryptography from the one the tests ran (2026-09-26).
@Suite("Package pins agree")
struct PackagePinAgreementTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func pins(_ path: String) throws -> [String: String] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(path))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pins = try #require(object["pins"] as? [[String: Any]])
        return Dictionary(uniqueKeysWithValues: pins.compactMap { pin in
            guard let identity = pin["identity"] as? String,
                  let revision = (pin["state"] as? [String: Any])?["revision"] as? String else { return nil }
            return (identity, revision)
        })
    }

    @Test("Package.resolved and the Xcode project's copy pin the same revisions")
    func samePins() throws {
        let package = try pins("Package.resolved")
        let xcode = try pins("GlassPowerTools.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        #expect(package == xcode, "resolve both: swift package resolve, then xcodebuild -resolvePackageDependencies")
    }
}
