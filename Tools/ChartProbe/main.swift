import SwiftUI
import Charts
import AppKit

struct Item: Identifiable { let id = UUID(); let name: String; let value: Int }
let items = [("shop", 12_000_000), ("inventory", 8_000_000), ("performance_schema", 2_300_000),
             ("analytics", 90_000), ("crm", 60_000), ("tenant_7c1e2a90-4b6d-4f1e-9a3c-5d8e2f1b0a47", 30_000),
             ("reports", 20_000), ("mysql", 10_000)].map { Item(name: $0.0, value: $0.1) }

var preset: AxisMarkPreset {
    switch CommandLine.arguments.dropFirst(2).first ?? "" {
    case "aligned": .aligned
    case "extended": .extended
    case "inset": .inset
    default: .automatic
    }
}

struct Probe: View {
    var body: some View {
        VStack(alignment: .leading) {
            Text("Largest by Rows").font(.title3.bold())
            Chart(items) { item in
                BarMark(x: .value("Rows", item.value), y: .value("Database", item.name))
                    .foregroundStyle(.blue).cornerRadius(3)
                    .annotation(position: .leading, alignment: .trailing, spacing: 8,
                                overflowResolution: .init(x: .disabled, y: .fit)) {
                        Text(item.name).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(width: 150, alignment: .trailing)
                    }
                    // The hover tooltip, forced on two rows so a headless render shows both the
                    // long-bar case (does it fit at the edge?) and the sliver case.
                    .annotation(position: .trailing, alignment: .leading, spacing: 6,
                                overflowResolution: .init(x: .fit, y: .fit)) {
                        if item.name == "shop" || item.name == "mysql" {
                            Text("\(item.value.formatted(.number)) rows")
                                .font(.caption.monospacedDigit())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine(); AxisTick()
                    AxisValueLabel { if let rows = value.as(Int.self) { Text(rows, format: .number.notation(.compactName)) } }
                }
            }
            .chartYAxis(.hidden)
            .padding(.leading, 158)
            .chartYAxis {
                if false { AxisMarks(preset: preset, position: .leading) { value in
                    AxisValueLabel(centered: true, horizontalSpacing: 8) {
                        if let name = value.as(String.self) {
                            Text(name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 160, alignment: .trailing)
                        }
                    }
                } }
            }
        }
        .padding(24).frame(width: 720, height: 300).background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor func render() {
    let renderer = ImageRenderer(content: Probe())
    renderer.scale = 2
    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("rendered")
    } else { print("render failed") }
}
@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        MainActor.assumeIsolated { render() }
    }
}
